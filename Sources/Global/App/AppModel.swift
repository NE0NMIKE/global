import AppKit
import Combine
import ServiceManagement

/// Central coordinator: combines settings, this Mac's location and the
/// partner's typed-in city into a `RenderModel` for the wallpaper.
@MainActor
final class AppModel: ObservableObject {
    let settings: AppSettings
    let location = LocationService()
    let wallpaper = WallpaperController()

    @Published private(set) var renderModel = RenderModel()

    private var cancellables: Set<AnyCancellable> = []
    private var appearanceObserver: NSKeyValueObservation?

    init(settings: AppSettings = .shared) {
        self.settings = settings
    }

    func start() {
        wallpaper.setFrameRate(settings.frameRate)
        wallpaper.setUserPaused(settings.paused)
        wallpaper.setPauseOnBattery(settings.pauseOnBattery)
        rebuildModel()
        wallpaper.start()
        location.start()

        // Any settings or location change → rebuild the render model.
        // objectWillChange fires *before* the value changes, so hop a runloop turn.
        Publishers.MergeMany(
            settings.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            location.objectWillChange.map { _ in () }.eraseToAnyPublisher()
        )
        .debounce(for: .milliseconds(30), scheduler: RunLoop.main)
        .sink { [weak self] in self?.rebuildModel() }
        .store(in: &cancellables)

        settings.$frameRate.removeDuplicates().sink { [weak self] in self?.wallpaper.setFrameRate($0) }
            .store(in: &cancellables)
        settings.$paused.removeDuplicates().sink { [weak self] in self?.wallpaper.setUserPaused($0) }
            .store(in: &cancellables)
        settings.$pauseOnBattery.removeDuplicates().sink { [weak self] in self?.wallpaper.setPauseOnBattery($0) }
            .store(in: &cancellables)
        // Follow the system light/dark setting in "Match System" mode.
        appearanceObserver = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.rebuildModel() }
        }
    }

    // MARK: - Model

    var isDark: Bool {
        switch settings.appearance {
        case .dark: return true
        case .light: return false
        case .system:
            return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }

    private func rebuildModel() {
        var m = RenderModel()
        m.style = settings.style
        m.motion = settings.motion
        m.isDark = isDark
        m.globeScale = settings.globeScale
        m.motionSpeed = settings.motionSpeed
        m.showDistance = settings.showDistance
        m.showLocalTimes = settings.showLocalTimes
        m.showDayNight = settings.showDayNight
        m.showInfoPanel = settings.showInfoPanel
        m.showGlobeTags = settings.showGlobeTags
        m.useMiles = settings.useMiles
        m.use24Hour = settings.use24Hour
        m.sinceDate = settings.sinceDate

        // Me: this Mac's location, else the city typed in Settings, else a
        // placeholder (on this Mac's clock, so the local time is still right).
        let myName = settings.myName.isEmpty ? "You" : settings.myName
        if let p = location.place ?? settings.myPlace {
            m.me = Person(place: p, name: myName)
        } else {
            m.me = Person(place: .placeholderMe, name: myName)
            m.me.timeZoneID = TimeZone.current.identifier
        }

        // Partner: the city typed in at setup or in Settings.
        m.partner = Person(place: settings.partnerPlace ?? .placeholderPartner,
                           name: settings.partnerName.isEmpty ? "Partner" : settings.partnerName)

        if m != renderModel {
            renderModel = m
            wallpaper.update(model: m)
        }
    }
}

/// Launch-at-login via the modern ServiceManagement API.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns an error message on failure.
    @discardableResult
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            Log.error("Launch at login: \(error.localizedDescription)")
            return error.localizedDescription
        }
    }

    /// True when macOS wants the user to approve the login item.
    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }
}

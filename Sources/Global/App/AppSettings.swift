import Combine
import Foundation

/// User preferences, persisted in UserDefaults.
///
/// Every property writes through on change; `objectWillChange` drives both
/// the SwiftUI settings window and the wallpaper renderer.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults: UserDefaults

    // MARK: Appearance
    @Published var style: GlobeStyle { didSet { save(style.rawValue, .style) } }
    @Published var appearance: AppearanceMode { didSet { save(appearance.rawValue, .appearance) } }
    @Published var motion: MotionMode { didSet { save(motion.rawValue, .motion) } }
    @Published var globeScale: Double { didSet { save(globeScale, .globeScale) } }
    @Published var motionSpeed: Double { didSet { save(motionSpeed, .motionSpeed) } }
    @Published var frameRate: Int { didSet { save(frameRate, .frameRate) } }

    // MARK: People
    @Published var myName: String { didSet { save(myName, .myName) } }
    @Published var partnerName: String { didSet { save(partnerName, .partnerName) } }
    /// The partner's city, typed in and looked up once (see `CityLookup`).
    @Published var partnerPlace: Place? { didSet { savePlace(partnerPlace, .partnerPlace) } }
    /// Used for this Mac when Location is off or hasn't found a fix yet.
    @Published var myPlace: Place? { didSet { savePlace(myPlace, .myPlace) } }

    // MARK: Overlays
    @Published var showDistance: Bool { didSet { save(showDistance, .showDistance) } }
    @Published var showLocalTimes: Bool { didSet { save(showLocalTimes, .showLocalTimes) } }
    @Published var showDayNight: Bool { didSet { save(showDayNight, .showDayNight) } }
    @Published var showInfoPanel: Bool { didSet { save(showInfoPanel, .showInfoPanel) } }
    @Published var showGlobeTags: Bool { didSet { save(showGlobeTags, .showGlobeTags) } }
    /// "Since …" date shown in the panel; nil hides the line.
    @Published var sinceDate: Date? { didSet { save(sinceDate?.timeIntervalSince1970 ?? 0, .sinceDate) } }
    @Published var useMiles: Bool { didSet { save(useMiles, .useMiles) } }
    @Published var use24Hour: Bool { didSet { save(use24Hour, .use24Hour) } }

    // MARK: Behaviour
    @Published var paused: Bool { didSet { save(paused, .paused) } }
    @Published var pauseOnBattery: Bool { didSet { save(pauseOnBattery, .pauseOnBattery) } }
    @Published var hasLaunchedBefore: Bool { didSet { save(hasLaunchedBefore, .hasLaunchedBefore) } }

    private enum Key: String {
        case style, appearance, motion, globeScale, motionSpeed, frameRate
        case myName, partnerName, partnerPlace, myPlace
        case showDistance, showLocalTimes, showDayNight, showInfoPanel, showGlobeTags, sinceDate, useMiles, use24Hour
        case paused, pauseOnBattery, hasLaunchedBefore
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func get<T>(_ k: Key, _ fallback: T) -> T { defaults.object(forKey: k.rawValue) as? T ?? fallback }

        style = GlobeStyle(rawValue: get(.style, "")) ?? .realistic
        appearance = AppearanceMode(rawValue: get(.appearance, "")) ?? .dark
        motion = MotionMode(rawValue: get(.motion, "")) ?? .framed
        globeScale = get(.globeScale, 0.62)
        motionSpeed = get(.motionSpeed, 1.0)
        frameRate = get(.frameRate, 30)

        func place(_ k: Key) -> Place? {
            defaults.data(forKey: k.rawValue).flatMap { try? JSONDecoder().decode(Place.self, from: $0) }
        }
        myName = get(.myName, "")
        partnerName = get(.partnerName, "")
        partnerPlace = place(.partnerPlace)
        myPlace = place(.myPlace)

        showDistance = get(.showDistance, true)
        showLocalTimes = get(.showLocalTimes, true)
        showDayNight = get(.showDayNight, false)
        showInfoPanel = get(.showInfoPanel, true)
        showGlobeTags = get(.showGlobeTags, false)
        let since: Double = get(.sinceDate, 0)
        sinceDate = since > 0 ? Date(timeIntervalSince1970: since) : nil
        useMiles = get(.useMiles, false)
        use24Hour = get(.use24Hour, true)

        paused = get(.paused, false)
        pauseOnBattery = get(.pauseOnBattery, true)
        hasLaunchedBefore = get(.hasLaunchedBefore, false)
    }

    private func save(_ value: Any, _ key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }

    private func savePlace(_ place: Place?, _ key: Key) {
        if let place, let data = try? JSONEncoder().encode(place) {
            save(data, key)
        } else {
            defaults.removeObject(forKey: key.rawValue)
        }
    }
}

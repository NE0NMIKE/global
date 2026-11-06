import AppKit

/// Owns one borderless, click-through, desktop-level window per display.
///
/// macOS has no public live-wallpaper API, so the globe is drawn in a window
/// that sits at the desktop window level: above the real wallpaper, below
/// desktop icons and every app window, and present on all Spaces.
final class WallpaperController {
    private final class Display {
        let window: NSWindow
        let view: WallpaperView
        var isVisible = true
        init(window: NSWindow, view: WallpaperView) { self.window = window; self.view = view }
    }

    private var displays: [CGDirectDisplayID: Display] = [:]
    private var model = RenderModel()
    private var frameRate = 30
    private var userPaused = false
    private var pauseOnBattery = true
    private var screensAsleep = false
    private let power = PowerMonitor()
    private var clockTimer: Timer?
    private var clockTicks = 0
    private var observers: [NSObjectProtocol] = []

    /// Called whenever the effective animation state changes (for the menu).
    var onStateChange: (() -> Void)?

    init() {
        power.onChange = { [weak self] in self?.updateAnimationState() }
    }

    func start() {
        rebuildWindows()

        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                        object: nil, queue: .main) { [weak self] _ in
            self?.rebuildWindows()
        })

        let ws = NSWorkspace.shared.notificationCenter
        for (name, asleep) in [(NSWorkspace.screensDidSleepNotification, true),
                               (NSWorkspace.screensDidWakeNotification, false),
                               (NSWorkspace.sessionDidResignActiveNotification, true),
                               (NSWorkspace.sessionDidBecomeActiveNotification, false)] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.screensAsleep = asleep
                self?.updateAnimationState()
            })
        }
        // Space changes can alter occlusion without a window notification.
        observers.append(ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                        object: nil, queue: .main) { [weak self] _ in
            self?.refreshOcclusion()
        })

        #if DEBUG
        // Debug hook: `scripts/debug-snapshot.sh <dir>` asks every live view to
        // save what it is currently showing (no screen-recording permission needed).
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("io.github.ne0nmike.global.debugSnapshot"), object: nil, queue: .main
        ) { [weak self] note in
            guard let dir = note.object as? String else { return }
            self?.writeSnapshots(to: URL(fileURLWithPath: dir))
        })
        #endif

        // Keep the panel's clocks current (it is only redrawn when its text
        // changes). While paused, also re-render the globe every 30 s so the
        // day/night line keeps moving.
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.clockTicks += 1
            let refreshGlobe = self.clockTicks % 6 == 0
            self.displays.values.forEach { $0.view.tick(refreshGlobe: refreshGlobe) }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        clockTimer = timer
    }

    // MARK: - Inputs

    func update(model: RenderModel) {
        self.model = model
        displays.values.forEach { $0.view.setModel(model) }
    }

    func setFrameRate(_ fps: Int) {
        frameRate = fps
        displays.values.forEach { $0.view.setFrameRate(fps) }
    }

    func setUserPaused(_ paused: Bool) {
        userPaused = paused
        updateAnimationState()
    }

    func setPauseOnBattery(_ on: Bool) {
        pauseOnBattery = on
        updateAnimationState()
    }

    /// Why the animation is currently paused, or nil if it is running.
    var pauseReason: String? {
        if userPaused { return "Paused" }
        if screensAsleep { return "Paused while the display sleeps" }
        if pauseOnBattery && power.isOnBattery { return "Paused on battery" }
        if pauseOnBattery && power.isLowPowerMode { return "Paused in Low Power Mode" }
        return nil
    }

    private func writeSnapshots(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (id, d) in displays {
            guard let image = d.view.compositeSnapshot(),
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            else { continue }
            try? png.write(to: dir.appendingPathComponent("display-\(id).png"))
        }
        // Any visible titled window (the Settings window).
        for (i, w) in NSApp.windows.enumerated() where w.isVisible && w.styleMask.contains(.titled) {
            guard let view = w.contentView?.superview ?? w.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("window-\(i).png"))
            }
        }
        Log.info("Wrote debug snapshots to \(dir.path)")
    }

    // MARK: - Windows

    private func rebuildWindows() {
        let screens = NSScreen.screens
        let ids = Set(screens.compactMap(\.displayID))

        // Remove windows for displays that went away.
        for (id, d) in displays where !ids.contains(id) {
            d.window.orderOut(nil)
            displays[id] = nil
        }

        for screen in screens {
            guard let id = screen.displayID else { continue }
            if let existing = displays[id] {
                existing.window.setFrame(screen.frame, display: true)
                continue
            }
            let window = makeWindow(for: screen)
            let view = WallpaperView(frame: NSRect(origin: .zero, size: screen.frame.size), frameRate: frameRate)
            view.autoresizingMask = [.width, .height]
            window.contentView = view
            view.setModel(model)
            window.orderFrontRegardless()

            let display = Display(window: window, view: view)
            displays[id] = display
            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self, weak display] _ in
                guard let display else { return }
                display.isVisible = display.window.occlusionState.contains(.visible)
                self?.updateAnimationState()
            })
        }
        updateAnimationState()
    }

    private func makeWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.setFrame(screen.frame, display: false)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        window.ignoresMouseEvents = true
        window.isOpaque = true
        window.hasShadow = false
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.title = "Global Wallpaper"
        return window
    }

    private func refreshOcclusion() {
        for d in displays.values { d.isVisible = d.window.occlusionState.contains(.visible) }
        updateAnimationState()
    }

    // MARK: - Animation state

    private func updateAnimationState() {
        let globallyPaused = pauseReason != nil
        for d in displays.values {
            // Fully covered displays (e.g. a full-screen app) stop rendering.
            d.view.setAnimating(!globallyPaused && d.isVisible)
        }
        onStateChange?()
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

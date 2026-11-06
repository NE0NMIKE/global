import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var menu: StatusMenuController!
    private var settingsWindow: SettingsWindowController?
    private var welcomeWindow: WelcomeWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        model.start()
        menu = StatusMenuController(model: model) { [weak self] in self?.showSettings() }

        // Until set up, greet with a short form for the names and partner's city.
        if !model.settings.hasLaunchedBefore { showWelcome() }
        #if DEBUG
        installDebugCommands()
        #endif
        Log.info("Global started")
    }

    #if DEBUG
    /// Debug builds only: `scripts/debug-command.sh style=dotMatrix` etc.
    /// Lets settings be driven from the terminal for testing.
    private func installDebugCommands() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("io.github.ne0nmike.global.debugCommand"), object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated { self?.handleDebugCommand(note.object as? String) }
        }
    }

    private func handleDebugCommand(_ command: String?) {
        guard let cmd = command else { return }
        let parts = cmd.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        let s = model.settings
        switch parts[0] {
        case "style": if let v = GlobeStyle(rawValue: parts[1]) { s.style = v }
        case "appearance": if let v = AppearanceMode(rawValue: parts[1]) { s.appearance = v }
        case "motion": if let v = MotionMode(rawValue: parts[1]) { s.motion = v }
        case "daynight": s.showDayNight = parts[1] == "1"
        case "panel": s.showInfoPanel = parts[1] == "1"
        case "tags": s.showGlobeTags = parts[1] == "1"
        case "paused": s.paused = parts[1] == "1"
        case "settings": showSettings()
        case "welcome": showWelcome()
        case "tab": settingsWindow?.selectTab(Int(parts[1]) ?? 0)
        default: Log.info("Unknown debug command \(cmd)")
        }
    }
    #endif

    /// Re-opening the app (e.g. double-clicking it again) shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model.settings.hasLaunchedBefore ? showSettings() : showWelcome()
        return false
    }

    func showWelcome() {
        if welcomeWindow == nil { welcomeWindow = WelcomeWindowController(settings: model.settings) }
        welcomeWindow?.show()
    }

    func showSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindowController(model: model) }
        settingsWindow?.show()
    }
}

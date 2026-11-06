import AppKit

// Entry point. `--snapshot` renders PNGs offscreen and exits (used for
// checking styles during development); otherwise run as a menu bar app.
if let i = CommandLine.arguments.firstIndex(of: "--icon"), i + 1 < CommandLine.arguments.count {
    exit(SnapshotTool.renderIcon(to: URL(fileURLWithPath: CommandLine.arguments[i + 1])))
}
if CommandLine.arguments.contains("--snapshot") {
    exit(SnapshotTool.run(arguments: CommandLine.arguments))
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)   // no Dock icon (also LSUIElement in Info.plist)
    withExtendedLifetime(delegate) { app.run() }
}

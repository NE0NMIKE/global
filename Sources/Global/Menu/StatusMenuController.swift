import AppKit

/// The menu bar icon and its menu. Rebuilt each time it opens, so it always
/// reflects the current settings.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let model: AppModel
    private let openSettings: () -> Void

    private var settings: AppSettings { model.settings }

    init(model: AppModel, openSettings: @escaping () -> Void) {
        self.model = model
        self.openSettings = openSettings
        super.init()
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "globe.europe.africa.fill", accessibilityDescription: "Global")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Global"
        }
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let m = model.renderModel

        // Header: who and how far.
        let km = GeoMath.distanceKm(m.me.coordinate, m.partner.coordinate)
        let header = NSMenuItem(title: "\(m.me.name) & \(m.partner.name)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        header.attributedTitle = NSAttributedString(
            string: "\(m.me.name) & \(m.partner.name)",
            attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)])
        menu.addItem(header)
        menu.addItem(info("\(Format.distance(km: km, useMiles: m.useMiles)) · \(InfoContent.timeDifference(partner: m.partner, me: m.me, now: Date()))"))
        if let reason = model.wallpaper.pauseReason {
            menu.addItem(info(reason, symbol: "pause.circle"))
        }
        menu.addItem(.separator())

        // Style.
        let styleMenu = NSMenu()
        for s in GlobeStyle.allCases {
            styleMenu.addItem(item(s.title, symbol: s.symbol, checked: settings.style == s) { [weak self] in
                self?.settings.style = s
            })
        }
        menu.addItem(submenu("Style", symbol: "paintpalette", styleMenu))

        let appearanceMenu = NSMenu()
        for a in AppearanceMode.allCases {
            appearanceMenu.addItem(item(a.title, symbol: a.symbol, checked: settings.appearance == a) { [weak self] in
                self?.settings.appearance = a
            })
        }
        menu.addItem(submenu("Appearance", symbol: "circle.lefthalf.filled", appearanceMenu))

        let motionMenu = NSMenu()
        for mode in MotionMode.allCases {
            motionMenu.addItem(item(mode.title, symbol: mode.symbol, checked: settings.motion == mode) { [weak self] in
                self?.settings.motion = mode
            })
        }
        menu.addItem(submenu("Motion", symbol: "rotate.3d", motionMenu))

        let showMenu = NSMenu()
        showMenu.addItem(toggle("Info Panel", \.showInfoPanel))
        showMenu.addItem(toggle("Name Tags on Globe", \.showGlobeTags))
        showMenu.addItem(.separator())
        showMenu.addItem(toggle("Distance", \.showDistance))
        showMenu.addItem(toggle("Local Times", \.showLocalTimes))
        showMenu.addItem(toggle("Day & Night", \.showDayNight))
        menu.addItem(submenu("Show", symbol: "eye", showMenu))

        menu.addItem(.separator())
        menu.addItem(toggle("Pause Animation", \.paused, symbol: "pause"))
        menu.addItem(toggle("Pause on Battery", \.pauseOnBattery, symbol: "battery.50"))
        menu.addItem(item("Launch at Login", symbol: "power", checked: LaunchAtLogin.isEnabled) {
            LaunchAtLogin.set(!LaunchAtLogin.isEnabled)
        })

        menu.addItem(.separator())
        let settingsItem = item("Settings…", symbol: "gearshape", checked: false) { [weak self] in
            self?.openSettings()
        }
        settingsItem.keyEquivalent = ","
        menu.addItem(settingsItem)
        let quit = item("Quit Global", symbol: nil, checked: false) { NSApp.terminate(nil) }
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    // MARK: - Item helpers

    private func info(_ title: String, symbol: String? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        if let symbol { i.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return i
    }

    private func submenu(_ title: String, symbol: String, _ sub: NSMenu) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        i.submenu = sub
        return i
    }

    private func item(_ title: String, symbol: String?, checked: Bool,
                      _ action: @escaping () -> Void) -> NSMenuItem {
        let i = ClosureMenuItem(title: title, handler: action)
        i.state = checked ? .on : .off
        if let symbol { i.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return i
    }

    private func toggle(_ title: String, _ key: ReferenceWritableKeyPath<AppSettings, Bool>,
                        symbol: String? = nil) -> NSMenuItem {
        item(title, symbol: symbol, checked: settings[keyPath: key]) { [weak self] in
            guard let self else { return }
            self.settings[keyPath: key].toggle()
        }
    }
}

/// NSMenuItem that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func run() { handler() }
}

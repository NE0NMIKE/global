import AppKit
import SwiftUI

/// Native preferences-style window: toolbar tabs, each hosting a SwiftUI form.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = [.crossfade, .allowUserInteraction]

        let s = model.settings
        func tab<V: View>(_ title: String, _ symbol: String, _ view: V) -> NSTabViewItem {
            let size = NSSize(width: 560, height: 520)
            let host = NSHostingController(rootView: view.frame(width: size.width, height: size.height))
            host.preferredContentSize = size
            host.title = title   // shown as the window title, like System Settings panes
            let item = NSTabViewItem(viewController: host)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            return item
        }
        tabs.addTabViewItem(tab("General", "gearshape", GeneralSettingsView(settings: s, appModel: model)))
        tabs.addTabViewItem(tab("Appearance", "paintpalette", AppearanceSettingsView(settings: s)))
        tabs.addTabViewItem(tab("Location", "location", LocationSettingsView(settings: s, location: model.location)))
        tabs.addTabViewItem(tab("About", "info.circle", AboutSettingsView()))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.title = "Global"
        super.init(window: window)
        window.delegate = self
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func selectTab(_ index: Int) {
        guard let tabs = contentViewController as? NSTabViewController,
              tabs.tabViewItems.indices.contains(index) else { return }
        tabs.selectedTabViewItemIndex = index
    }

    func show() {
        // Menu-bar apps must activate explicitly for the window to come forward.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

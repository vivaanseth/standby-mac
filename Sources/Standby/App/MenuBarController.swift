import AppKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private var item: NSStatusItem?
    private let controller: StandbyController
    private let store: ConfigStore
    private let openSettings: () -> Void

    init(controller: StandbyController, store: ConfigStore, openSettings: @escaping () -> Void) {
        self.controller = controller
        self.store = store
        self.openSettings = openSettings
        super.init()
    }

    func setVisible(_ visible: Bool) {
        if visible, item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            let image = NSImage(systemSymbolName: "deskclock.fill", accessibilityDescription: "Standby")
                ?? NSImage(systemSymbolName: "clock.fill", accessibilityDescription: "Standby")
            image?.isTemplate = true
            item.button?.image = image
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            self.item = item
        } else if !visible, let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let config = store.config

        let status = NSMenuItem(title: controller.statusText, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let show = NSMenuItem(title: controller.isShowing ? "Hide Standby" : "Show Standby Now", action: #selector(toggleNow), keyEquivalent: "")
        if config.hotKeyEnabled {
            show.keyEquivalent = "s"
            show.keyEquivalentModifierMask = [.control, .option, .command]
        }
        show.target = self
        menu.addItem(show)

        if controller.pausedUntil != nil {
            menu.addItem(item("Resume", #selector(resume)))
        } else {
            let pause = NSMenuItem(title: "Pause", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for (title, minutes) in [("For 30 Minutes", 30), ("For 1 Hour", 60), ("For 2 Hours", 120), ("Until I Resume", 0)] {
                let i = item(title, #selector(pause(_:)))
                i.tag = minutes
                sub.addItem(i)
            }
            pause.submenu = sub
            menu.addItem(pause)
        }

        let enabled = item("Enabled", #selector(toggleEnabled))
        enabled.state = config.enabled ? .on : .off
        menu.addItem(enabled)

        menu.addItem(.separator())
        let settings = item("Settings…", #selector(showSettings))
        settings.keyEquivalent = ","
        menu.addItem(settings)
        menu.addItem(item("Quit Standby", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    @objc private func toggleNow() { controller.toggle() }
    @objc private func resume() { controller.resume() }
    @objc private func pause(_ sender: NSMenuItem) {
        controller.pause(for: sender.tag == 0 ? nil : TimeInterval(sender.tag * 60))
    }
    @objc private func toggleEnabled() { store.config.enabled.toggle() }
    @objc private func showSettings() { openSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}

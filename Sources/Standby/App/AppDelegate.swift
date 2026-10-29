import AppKit
import Combine
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = ConfigStore()
    let nav = StandbyNavigator()
    let weather = WeatherService()
    let calendar = CalendarService()
    let photos = PhotoRotator()
    let power = PowerService()

    private var controller: StandbyController!
    private var menuBar: MenuBarController!
    private var settingsWindow: NSWindow?
    private var hotKey: HotKey?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        controller = StandbyController(store: store, nav: nav, weather: weather, calendar: calendar, photos: photos, power: power)
        menuBar = MenuBarController(controller: controller, store: store) { [weak self] in self?.showSettings() }
        controller.start()

        store.$config.map(\.showMenuBarIcon).removeDuplicates()
            .sink { [weak self] visible in self?.menuBar.setVisible(visible) }
            .store(in: &cancellables)
        store.$config.map(\.hotKeyEnabled).removeDuplicates()
            .sink { [weak self] enabled in self?.setHotKey(enabled) }
            .store(in: &cancellables)

        if !store.config.hasLaunchedBefore {
            store.config.hasLaunchedBefore = true
            showSettings()
        }
    }

    /// Opening the app again (e.g. from Finder while it's running) brings up
    /// Settings — the way back in if the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKey?.invalidate()
    }

    func showSettings() {
        if settingsWindow == nil {
            let root = SettingsView(store: store, controller: controller)
                .environmentObject(weather)
                .environmentObject(calendar)
                .environmentObject(photos)
                .environmentObject(power)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 720),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = "Standby Settings"
            window.titlebarAppearsTransparent = false
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: root)
            window.setContentSize(NSSize(width: 760, height: 720))
            window.contentMinSize = NSSize(width: 680, height: 560)
            window.center()
            window.setFrameAutosaveName("StandbySettings")
            settingsWindow = window
        }
        photos.configure(folder: store.config.photoFolder, shuffle: store.config.photoShuffle)
        weather.refresh(config: store.config)
        if store.config.uses(.upNext) { calendar.refresh() }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func setHotKey(_ enabled: Bool) {
        hotKey?.invalidate()
        hotKey = enabled ? HotKey.standby { [weak self] in self?.controller.toggle() } : nil
    }

    /// Not visible (this is a menu bar app), but it makes Copy/Paste, Close
    /// and Quit shortcuts work in the Settings window.
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Standby", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = window
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }

    @objc private func openSettingsFromMenu() { showSettings() }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

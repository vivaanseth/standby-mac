import AppKit

let arguments = CommandLine.arguments

MainActor.assumeIsolated {
    // Developer entry points used by build.sh and for checking the design.
    if let i = arguments.firstIndex(of: "--icon"), i + 1 < arguments.count {
        Renderer.renderIcon(to: arguments[i + 1])
        exit(0)
    }
    if let i = arguments.firstIndex(of: "--render"), i + 1 < arguments.count {
        Renderer.renderScreens(to: arguments[i + 1])
        exit(0)
    }
    if let i = arguments.firstIndex(of: "--render-settings"), i + 1 < arguments.count {
        Renderer.renderSettings(to: arguments[i + 1])
        exit(0)
    }
    if arguments.contains("--open-at-login") {
        do {
            try LoginItem.set(true)
            print("Standby will open at login.")
        } catch {
            print("Couldn't register login item: \(error.localizedDescription)")
        }
        exit(0)
    }
    // Control a running instance, e.g. from Shortcuts:
    //   /Applications/Standby.app/Contents/MacOS/Standby --toggle
    for command in StandbyCommand.allCases where arguments.contains("--\(command.rawValue)") {
        command.post()
        exit(0)
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) {
        app.run()
    }
}

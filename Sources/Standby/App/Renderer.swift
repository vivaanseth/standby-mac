import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Renders StandBy screens and the app icon to PNG without opening any windows.
@MainActor
enum Renderer {
    static func renderScreens(to directory: String) {
        let dir = URL(fileURLWithPath: (directory as NSString).expandingTildeInPath)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var cal = Calendar.current
        cal.timeZone = .current
        let date = cal.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 9, minute: 41, second: 32))!

        let weather = WeatherService()
        weather.setPreview(WeatherSnapshot(temperature: 64, high: 70, low: 54, code: 2, isDay: true, placeName: "Cupertino", fetched: date))
        let calendar = CalendarService()
        calendar.setPreview([
            UpcomingEvent(id: "1", title: "Design review", start: date.addingTimeInterval(1140), end: date.addingTimeInterval(4740), isAllDay: false, color: Color(hex: 0x0A84FF)),
            UpcomingEvent(id: "2", title: "Lunch with Sam", start: date.addingTimeInterval(9000), end: date.addingTimeInterval(12600), isAllDay: false, color: Color(hex: 0x30D158)),
        ])
        let photos = PhotoRotator()
        photos.setPreview(samplePhoto())
        let power = PowerService()
        power.setPreview(BatteryInfo(hasBattery: true, level: 0.82, isCharging: true, onAC: true))
        power.setPreviewLoad(cpu: 0.23, memory: 0.61)

        var base = StandbyConfig()
        base.nightMode = .off
        base.burnInProtection = false
        base.stacks[1] = StandbyConfig.stack(enabled: [.calendarMonth, .upNext, .weather, .photo, .date])

        struct Shot { var name: String; var page: PageKind; var left = 0; var right = 0; var stacks = 2; var swipe: CGFloat = 0; var layout: WidgetLayout = .grid; var alt: Int? = nil; var clock: ClockStyle = .digital; var night = false; var size = CGSize(width: 1440, height: 900) }
        let shots: [Shot] = [
            Shot(name: "01-widgets", page: .widgets),
            Shot(name: "02-widgets", page: .widgets, left: 1, right: 1),
            Shot(name: "03-widgets", page: .widgets, left: 2, right: 2),
            Shot(name: "04-widgets", page: .widgets, left: 3, right: 3),
            Shot(name: "05-widgets", page: .widgets, left: 0, right: 4),
            Shot(name: "06-photos", page: .photos),
            Shot(name: "07-clock-digital", page: .clock, clock: .digital),
            Shot(name: "08-clock-analog", page: .clock, clock: .analog),
            Shot(name: "09-clock-world", page: .clock, clock: .world),
            Shot(name: "10-clock-solar", page: .clock, clock: .solar),
            Shot(name: "11-clock-float", page: .clock, clock: .float),
            Shot(name: "12-night", page: .widgets, night: true),
            Shot(name: "13-night-digital", page: .clock, clock: .digital, night: true),
            Shot(name: "14-digital-1280", page: .clock, clock: .digital, size: CGSize(width: 1280, height: 800)),
            Shot(name: "15-three-stacks", page: .widgets, stacks: 3),
            Shot(name: "16-four-stacks", page: .widgets, stacks: 4),
            Shot(name: "17-six-stacks", page: .widgets, stacks: 6),
            Shot(name: "18-one-stack", page: .widgets, stacks: 1),
            Shot(name: "19-stack-swipe", page: .widgets, swipe: -260),
            Shot(name: "20-hero-3", page: .widgets, stacks: 3, layout: .hero),
            Shot(name: "21-hero-5", page: .widgets, stacks: 5, layout: .hero),
            Shot(name: "22-spotlight-3", page: .widgets, stacks: 3, layout: .spotlight),
            Shot(name: "23-spotlight-5", page: .widgets, stacks: 5, layout: .spotlight),
            Shot(name: "24-strip-4", page: .widgets, stacks: 4, layout: .strip),
            Shot(name: "25-wave-5", page: .widgets, stacks: 5, layout: .wave),
            Shot(name: "26-new-a", page: .widgets, stacks: 6, layout: .grid, alt: 0),
            Shot(name: "27-new-b", page: .widgets, stacks: 6, layout: .grid, alt: 1),
        ]

        for shot in shots {
            var config = base
            config.nightMode = shot.night ? .always : .off
            config.stackCount = shot.stacks
            config.widgetLayout = shot.layout
            if let alt = shot.alt {
                // Show the new widgets: stacks 3-6 hold them by default.
                let sets: [[WidgetKind]] = alt == 0
                    ? [[.moon], [.sun], [.flipClock], [.wordClock], [.rings], [.countdown]]
                    : [[.note], [.macStats], [.moon], [.rings], [.flipClock], [.wordClock]]
                for (i, kinds) in sets.enumerated() { config.stacks[i] = StandbyConfig.stack(enabled: kinds) }
                config.noteText = "Pick up flowers on the way home 🌷"
                config.countdownTitle = "Lisbon trip"
                config.countdownDate = date.addingTimeInterval(86400 * 23)
            }
            let nav = StandbyNavigator()
            nav.apply(config)
            nav.page = config.visiblePages.firstIndex(of: shot.page) ?? 0
            nav.stackIndices[0] = shot.left
            nav.stackIndices[1] = shot.right
            if shot.swipe != 0 {
                nav.vTarget = .stack(0)
                nav.vOffset = shot.swipe
            }
            nav.clockIndex = config.enabledClockStyles.firstIndex(of: shot.clock) ?? 0
            let view = StandbyScene(date: date, config: config, nav: nav)
                .environmentObject(weather)
                .environmentObject(calendar)
                .environmentObject(photos)
                .environmentObject(power)
                .frame(width: shot.size.width, height: shot.size.height)
            write(view, scale: 1, to: dir.appendingPathComponent(shot.name + ".png"))
        }
        // External display: the Sky through a day, and the other styles.
        let skyTimes: [(String, Int, Int)] = [("dawn", 6, 50), ("morning", 9, 41), ("dusk", 18, 5), ("blue-hour", 18, 35), ("night", 23, 10)]
        for (name, hour, minute) in skyTimes {
            var cal = Calendar.current
            cal.timeZone = .current
            let when = cal.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: hour, minute: minute, second: 14))!
            var config = base
            config.external.showWidgets = false
            config.external.showPhotos = false
            config.external.showClock = false
            config.external.showSky = true
            config.external.startPage = .sky
            write(companion(when, config), scale: 1, to: dir.appendingPathComponent("ext-sky-\(name).png"))
        }
        for (page, face) in [(PageKind.clock, ClockStyle.world), (.clock, .digital), (.widgets, .world), (.photos, .world)] {
            var config = base
            config.external.startPage = page
            config.external.startClockStyle = face
            write(companion(date, config), scale: 1, to: dir.appendingPathComponent("ext-standby-\(page.rawValue)-\(face.rawValue).png"))
        }

        // A profile of its own, different from the built-in display's.
        var custom = base
        custom.external.startPage = .widgets
        custom.external.stackCount = 5
        custom.external.widgetLayout = .spotlight
        custom.external.stacks[0] = StandbyConfig.stack(enabled: [.digitalClock])
        custom.external.stacks[1] = StandbyConfig.stack(enabled: [.moon])
        custom.external.stacks[2] = StandbyConfig.stack(enabled: [.rings])
        custom.external.stacks[3] = StandbyConfig.stack(enabled: [.weather])
        custom.external.stacks[4] = StandbyConfig.stack(enabled: [.macStats])
        write(companion(date, custom), scale: 1, to: dir.appendingPathComponent("ext-custom-widgets.png"))

        // The Analog dial as a widget, and on Photos and Sky.
        var dial = base
        dial.photoClock = .analog
        dial.skyClock = .analog
        dial.showSky = true
        dial.stacks[0] = StandbyConfig.stack(enabled: [.analogFace])
        for page in [PageKind.widgets, .photos, .sky] {
            let n = StandbyNavigator()
            n.apply(dial)
            n.page = dial.visiblePages.firstIndex(of: page) ?? 0
            write(StandbyScene(date: date, config: dial, nav: n)
                .environmentObject(weather).environmentObject(calendar).environmentObject(photos).environmentObject(power)
                .frame(width: 1440, height: 900), scale: 1, to: dir.appendingPathComponent("dial-\(page.rawValue).png"))
        }

        // Widgets in a custom color.
        var themed = base
        themed.widgetTint = .teal
        themed.stackCount = 6
        themed.stacks = [[.calendarMonth], [.rings], [.analogClock], [.countdown], [.macStats], [.wordClock]].map { StandbyConfig.stack(enabled: $0) }
        let tn = StandbyNavigator()
        tn.apply(themed)
        write(StandbyScene(date: date, config: themed, nav: tn)
            .environmentObject(weather).environmentObject(calendar).environmentObject(photos).environmentObject(power)
            .frame(width: 1440, height: 900), scale: 1, to: dir.appendingPathComponent("widgets-themed.png"))

        // Sky on the built-in display.
        var builtInSky = base
        builtInSky.showSky = true
        let skyNav = StandbyNavigator()
        skyNav.apply(builtInSky)
        skyNav.page = builtInSky.visiblePages.firstIndex(of: .sky) ?? 0
        write(StandbyScene(date: date, config: builtInSky, nav: skyNav)
            .environmentObject(weather).environmentObject(calendar).environmentObject(photos).environmentObject(power)
            .frame(width: 1440, height: 900), scale: 1, to: dir.appendingPathComponent("builtin-sky.png"))

        func companion(_ when: Date, _ config: StandbyConfig) -> some View {
            let nav = StandbyNavigator()
            nav.prepareForShow(config.companionConfig)
            return CompanionScene(date: when, config: config, nav: nav)
                .environmentObject(weather)
                .environmentObject(calendar)
                .environmentObject(photos)
                .environmentObject(power)
                .frame(width: 1920, height: 1080)
        }
        print("Rendered \(shots.count) screens to \(dir.path)")
    }

    /// Snapshots each Settings tab. AppKit-backed controls don't draw through
    /// ImageRenderer, so these go through an offscreen window instead.
    static func renderSettings(to directory: String) {
        let dir = URL(fileURLWithPath: (directory as NSString).expandingTildeInPath)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        _ = NSApplication.shared
        let store = ConfigStore(preview: StandbyConfig())
        let weather = WeatherService()
        let calendar = CalendarService()
        let photos = PhotoRotator()
        let power = PowerService()
        let tabs: [(String, AnyView)] = [
            ("views", AnyView(ViewsSettings(store: store))),
            ("widgets", AnyView(WidgetsSettings(store: store))),
            ("clock", AnyView(ClockSettings(store: store))),
            ("photos", AnyView(PhotosSettings(store: store))),
            ("display", AnyView(DisplaySettings(store: store))),
            ("external", AnyView(ExternalSettings(store: store))),
        ]
        for (name, view) in tabs {
            let root = view
                .environmentObject(weather)
                .environmentObject(calendar)
                .environmentObject(photos)
                .environmentObject(power)
                .frame(width: 760, height: 1400)
            let window = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: 760, height: 1400), styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .darkAqua)
            let host = NSHostingView(rootView: root)
            window.contentView = host
            window.orderFrontRegardless()
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("settings-\(name).png"))
            window.orderOut(nil)
        }
        print("Rendered settings to \(dir.path)")
    }

    static func renderIcon(to path: String) {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 10, minute: 9, second: 30))!
        let icon = ZStack {
            RoundedRectangle(cornerRadius: 186, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.02)], startPoint: .top, endPoint: .bottom))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
            RoundedRectangle(cornerRadius: 186, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 3)
                .frame(width: 824, height: 824)
            HStack(spacing: 36) {
                AnalogDial(date: date, style: DialStyle(numeralSize: 0.25, minuteTicks: nil))
                    .frame(width: 340, height: 340)
                VStack(spacing: -24) {
                    Text("TUE")
                        .font(.system(size: 78, weight: .bold))
                        .foregroundStyle(Palette.red)
                    Text("28")
                        .font(.system(size: 230, weight: .light))
                        .foregroundStyle(.white)
                }
                .frame(width: 300)
            }
        }
        .frame(width: 1024, height: 1024)
        write(icon, scale: 1, to: URL(fileURLWithPath: path))
    }

    private static func write(_ view: some View, scale: CGFloat, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let image = renderer.cgImage,
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            print("Failed to render \(url.lastPathComponent)")
            return
        }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }

    /// A stand-in photo (a dusk sky over hills) for previews.
    private static func samplePhoto() -> CGImage? {
        let w = 1600, h = 1000
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let sky = CGGradient(colorsSpace: space, colors: [
            CGColor(red: 0.98, green: 0.62, blue: 0.38, alpha: 1),
            CGColor(red: 0.85, green: 0.42, blue: 0.52, alpha: 1),
            CGColor(red: 0.22, green: 0.22, blue: 0.45, alpha: 1),
        ] as CFArray, locations: [0, 0.45, 1])!
        ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: h), options: [])
        ctx.setFillColor(CGColor(red: 1, green: 0.93, blue: 0.8, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: 1050, y: 300, width: 160, height: 160))
        for (i, color) in [(0, CGColor(red: 0.28, green: 0.2, blue: 0.35, alpha: 1)), (1, CGColor(red: 0.16, green: 0.12, blue: 0.22, alpha: 1))] {
            ctx.setFillColor(color)
            ctx.move(to: CGPoint(x: 0, y: 0))
            for x in stride(from: 0, through: w, by: 20) {
                let y = 260 - Double(i) * 90 + sin(Double(x) / (180 + Double(i) * 70) + Double(i)) * 70
                ctx.addLine(to: CGPoint(x: Double(x), y: y))
            }
            ctx.addLine(to: CGPoint(x: w, y: 0))
            ctx.fillPath()
        }
        return ctx.makeImage()
    }
}

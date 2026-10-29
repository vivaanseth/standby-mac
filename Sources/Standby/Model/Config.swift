import Foundation
import SwiftUI

enum PageKind: String, Codable, CaseIterable, Identifiable {
    case widgets, photos, clock
    var id: String { rawValue }
    var title: String {
        switch self {
        case .widgets: "Widgets"
        case .photos: "Photos"
        case .clock: "Clock"
        }
    }
}

enum StartPage: String, Codable, CaseIterable, Identifiable {
    case lastUsed, widgets, photos, clock
    var id: String { rawValue }
    var title: String {
        switch self {
        case .lastUsed: "Last Used"
        case .widgets: "Widgets"
        case .photos: "Photos"
        case .clock: "Clock"
        }
    }
}

enum ClockStyle: String, Codable, CaseIterable, Identifiable {
    case digital, analog, world, solar, float
    var id: String { rawValue }
    var title: String {
        switch self {
        case .digital: "Digital"
        case .analog: "Analog"
        case .world: "World"
        case .solar: "Solar"
        case .float: "Float"
        }
    }
    /// World is the one face Apple doesn't let you recolor.
    var hasTint: Bool { self != .world }
}

enum WidgetKind: String, Codable, CaseIterable, Identifiable {
    case analogClock, calendarMonth, upNext, date, digitalClock, worldClock, weather, battery, photo
    case moon, sun, flipClock, wordClock, rings, countdown, note, macStats
    var id: String { rawValue }
    var title: String {
        switch self {
        case .analogClock: "Clock"
        case .calendarMonth: "Calendar"
        case .upNext: "Up Next"
        case .date: "Date"
        case .digitalClock: "Digital Clock"
        case .worldClock: "World Clock"
        case .weather: "Weather"
        case .battery: "Batteries"
        case .photo: "Photos"
        case .moon: "Moon"
        case .sun: "Sunrise & Sunset"
        case .flipClock: "Flip Clock"
        case .wordClock: "Word Clock"
        case .rings: "Time Rings"
        case .countdown: "Countdown"
        case .note: "Note"
        case .macStats: "Mac Activity"
        }
    }
    var symbol: String {
        switch self {
        case .analogClock: "clock"
        case .calendarMonth: "calendar"
        case .upNext: "list.bullet.rectangle"
        case .date: "calendar.day.timeline.left"
        case .digitalClock: "textformat.123"
        case .worldClock: "globe"
        case .weather: "cloud.sun"
        case .battery: "battery.75percent"
        case .photo: "photo"
        case .moon: "moon.stars"
        case .sun: "sunrise"
        case .flipClock: "rectangle.split.2x1"
        case .wordClock: "textformat.abc"
        case .rings: "circle.circle"
        case .countdown: "hourglass"
        case .note: "note.text"
        case .macStats: "cpu"
        }
    }
}

/// How the widget stacks are arranged on screen.
enum WidgetLayout: String, Codable, CaseIterable, Identifiable {
    case grid, hero, spotlight, strip, wave
    var id: String { rawValue }
    var title: String {
        switch self {
        case .grid: "Grid"
        case .hero: "Hero"
        case .spotlight: "Spotlight"
        case .strip: "Strip"
        case .wave: "Wave"
        }
    }
    var summary: String {
        switch self {
        case .grid: "Equal stacks in one or two rows."
        case .hero: "The first stack large, the rest beside it."
        case .spotlight: "The first stack large in the middle, the rest on either side."
        case .strip: "All stacks in a single row."
        case .wave: "A single row that zigzags up and down."
        }
    }
}

struct WidgetSlot: Codable, Equatable, Identifiable {
    var kind: WidgetKind
    var enabled: Bool
    var id: WidgetKind { kind }
}

struct ClockSlot: Codable, Equatable, Identifiable {
    var style: ClockStyle
    var enabled: Bool
    var id: ClockStyle { style }
}

enum TimeFormat: String, Codable, CaseIterable, Identifiable {
    case system, twelveHour, twentyFourHour
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "System Setting"
        case .twelveHour: "12-Hour"
        case .twentyFourHour: "24-Hour"
        }
    }
}

enum TemperatureUnit: String, Codable, CaseIterable, Identifiable {
    case system, celsius, fahrenheit
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "System Setting"
        case .celsius: "Celsius"
        case .fahrenheit: "Fahrenheit"
        }
    }
    var usesFahrenheit: Bool {
        switch self {
        case .celsius: false
        case .fahrenheit: true
        case .system: Locale.current.measurementSystem == .us
        }
    }
}

enum NightMode: String, Codable, CaseIterable, Identifiable {
    case off, scheduled, always
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: "Off"
        case .scheduled: "Scheduled"
        case .always: "Always"
        }
    }
}

enum PhotoClockPosition: String, Codable, CaseIterable, Identifiable {
    case topLeading, topTrailing, bottomLeading, bottomTrailing, hidden
    var id: String { rawValue }
    var title: String {
        switch self {
        case .topLeading: "Top Left"
        case .topTrailing: "Top Right"
        case .bottomLeading: "Bottom Left"
        case .bottomTrailing: "Bottom Right"
        case .hidden: "Hidden"
        }
    }
}

struct WeatherPlace: Codable, Equatable, Hashable, Identifiable {
    var name: String
    var region: String
    var latitude: Double
    var longitude: Double
    var id: String { "\(name)|\(latitude)|\(longitude)" }
}

struct StandbyConfig: Codable, Equatable {
    // Activation
    var enabled = true
    var dualEnabled = true
    var dualIdleDelay: Double = 120
    var wakeOnPointerDual = false
    var soloEnabled = true
    var soloIdleDelay: Double = 300
    var wakeOnPointerSolo = true
    var onlyWhenCharging = false
    var respectDisplaySleepAssertions = true
    var keepDisplayAwake = false
    var hotKeyEnabled = true
    var showMenuBarIcon = true
    var hasLaunchedBefore = false

    // Views
    var showWidgets = true
    var showPhotos = true
    var showClock = true
    var startPage: StartPage = .lastUsed
    var lastPage: PageKind = .widgets
    var timeFormat: TimeFormat = .system
    var temperatureUnit: TemperatureUnit = .system
    var weatherPlace: WeatherPlace?

    // Widgets
    /// Always `maxStacks` long; `stackCount` decides how many are on screen.
    var stacks: [[WidgetSlot]] = StandbyConfig.defaultStacks
    var stackCount = 2
    var widgetLayout: WidgetLayout = .grid
    var countdownTitle = "New Year"
    /// nil counts down to the next January 1.
    var countdownDate: Date?
    var noteText = ""
    var smartRotate = true
    var smartRotateMinutes = 10
    var showWidgetBackgrounds = false
    var worldClockZones = ["America/Los_Angeles", "America/New_York", "Europe/London", "Asia/Tokyo"]

    // Clock
    var clockStyles: [ClockSlot] = ClockStyle.allCases.map { ClockSlot(style: $0, enabled: true) }
    var lastClockStyle: ClockStyle = .digital
    var digitalTint: Tint = .red
    var analogTint: Tint = .orange
    var solarTint: Tint = .orange
    var floatTint: Tint = .pink
    var showWeatherOnClocks = true

    // Photos
    var photoFolder = "~/Pictures"
    var photoInterval: Double = 15
    var photoShuffle = true
    var photoKenBurns = true
    var photoClockPosition: PhotoClockPosition = .topTrailing

    // Display
    var brightness: Double = 1
    var nightMode: NightMode = .scheduled
    var nightStartMinutes = 22 * 60
    var nightEndMinutes = 7 * 60
    var burnInProtection = true

    static let maxStacks = 6

    static let defaultStacks: [[WidgetSlot]] = [
        stack(enabled: [.analogClock, .digitalClock, .worldClock, .battery]),
        stack(enabled: [.calendarMonth, .date, .weather, .photo]),
        stack(enabled: [.moon, .weather, .sun]),
        stack(enabled: [.rings, .battery, .macStats]),
        stack(enabled: [.flipClock, .wordClock, .digitalClock]),
        stack(enabled: [.countdown, .photo, .note]),
    ]

    static func stack(enabled: [WidgetKind]) -> [WidgetSlot] {
        let rest = WidgetKind.allCases.filter { !enabled.contains($0) }
        return enabled.map { WidgetSlot(kind: $0, enabled: true) } + rest.map { WidgetSlot(kind: $0, enabled: false) }
    }

    var visiblePages: [PageKind] {
        var pages: [PageKind] = []
        if showWidgets { pages.append(.widgets) }
        if showPhotos { pages.append(.photos) }
        if showClock { pages.append(.clock) }
        return pages.isEmpty ? [.clock] : pages
    }

    var enabledClockStyles: [ClockStyle] {
        let styles = clockStyles.filter(\.enabled).map(\.style)
        return styles.isEmpty ? [.digital] : styles
    }

    /// The enabled widgets of each stack on screen.
    var visibleStacks: [[WidgetKind]] {
        stacks.prefix(min(max(stackCount, 1), Self.maxStacks)).map { $0.filter(\.enabled).map(\.kind) }
    }

    func uses(_ kind: WidgetKind) -> Bool {
        showWidgets && visibleStacks.contains { $0.contains(kind) }
    }

    func tint(for style: ClockStyle) -> Tint {
        switch style {
        case .digital: digitalTint
        case .analog: analogTint
        case .solar: solarTint
        case .float: floatTint
        case .world: .white
        }
    }

    mutating func setTint(_ tint: Tint, for style: ClockStyle) {
        switch style {
        case .digital: digitalTint = tint
        case .analog: analogTint = tint
        case .solar: solarTint = tint
        case .float: floatTint = tint
        case .world: break
        }
    }

    func isNight(at date: Date) -> Bool {
        switch nightMode {
        case .off: return false
        case .always: return true
        case .scheduled:
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            if nightStartMinutes == nightEndMinutes { return false }
            if nightStartMinutes < nightEndMinutes { return m >= nightStartMinutes && m < nightEndMinutes }
            return m >= nightStartMinutes || m < nightEndMinutes
        }
    }

    /// Adds anything introduced after the settings were first saved.
    mutating func normalize() {
        while stacks.count < Self.maxStacks { stacks.append(Self.defaultStacks[stacks.count]) }
        stacks = Array(stacks.prefix(Self.maxStacks))
        for i in stacks.indices {
            for kind in WidgetKind.allCases where !stacks[i].contains(where: { $0.kind == kind }) {
                stacks[i].append(WidgetSlot(kind: kind, enabled: false))
            }
        }
        stackCount = min(max(stackCount, 1), Self.maxStacks)
        for style in ClockStyle.allCases where !clockStyles.contains(where: { $0.style == style }) {
            clockStyles.append(ClockSlot(style: style, enabled: true))
        }
    }
}

@MainActor
final class ConfigStore: ObservableObject {
    @Published var config: StandbyConfig {
        didSet { if config != oldValue { save() } }
    }

    private static let key = "StandbyConfig.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        config = Self.load(from: defaults)
    }

    /// Ephemeral store for previews and rendering; never touches UserDefaults.
    init(preview: StandbyConfig) {
        defaults = UserDefaults(suiteName: "Standby.preview") ?? .standard
        config = preview
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: Self.key)
    }

    /// Decodes stored settings on top of the defaults so that settings added in
    /// later versions pick up their default values instead of failing to decode.
    private static func load(from defaults: UserDefaults) -> StandbyConfig {
        let fallback = StandbyConfig()
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let baseData = try? JSONEncoder().encode(fallback),
              let base = try? JSONSerialization.jsonObject(with: baseData) as? [String: Any],
              let mergedData = try? JSONSerialization.data(withJSONObject: merge(base, migrate(stored, base: base))),
              var config = try? JSONDecoder().decode(StandbyConfig.self, from: mergedData)
        else { return fallback }
        config.normalize()
        return config
    }

    /// Settings saved before stacks were configurable had just two.
    private static func migrate(_ stored: [String: Any], base: [String: Any]) -> [String: Any] {
        var stored = stored
        if stored["stacks"] == nil, let left = stored["leftStack"], let right = stored["rightStack"],
           var stacks = base["stacks"] as? [Any], stacks.count >= 2 {
            stacks[0] = left
            stacks[1] = right
            stored["stacks"] = stacks
        }
        return stored
    }

    private static func merge(_ base: [String: Any], _ overlay: [String: Any]) -> [String: Any] {
        var out = base
        for (key, value) in overlay {
            if let a = base[key] as? [String: Any], let b = value as? [String: Any] {
                out[key] = merge(a, b)
            } else {
                out[key] = value
            }
        }
        return out
    }
}

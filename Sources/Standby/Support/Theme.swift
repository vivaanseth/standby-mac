import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// The dark-appearance system colors StandBy draws with.
enum Palette {
    static let red = Color(hex: 0xFF453A)
    static let orange = Color(hex: 0xFF9F0A)
    static let yellow = Color(hex: 0xFFD60A)
    static let green = Color(hex: 0x30D158)
    static let secondary = Color(hex: 0x8E8E93)
    static let tertiary = Color(hex: 0x48484A)
    static let widgetBackground = Color(hex: 0x1C1C1E)
    static let dialFace = Color(hex: 0x1C1C1E)
    static let nightRed = Color(red: 1, green: 0.16, blue: 0.12)
}

/// Accent colors offered for the clock faces, mirroring the StandBy swatches.
enum Tint: String, Codable, CaseIterable, Identifiable {
    case white, red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink
    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    private var hex: UInt32 {
        switch self {
        case .white: 0xF2F2F7
        case .red: 0xFF453A
        case .orange: 0xFF9F0A
        case .yellow: 0xFFD60A
        case .green: 0x30D158
        case .mint: 0x63E6E2
        case .teal: 0x40C8E0
        case .cyan: 0x64D2FF
        case .blue: 0x0A84FF
        case .indigo: 0x5E5CE6
        case .purple: 0xBF5AF2
        case .pink: 0xFF375F
        }
    }

    var base: Color { Color(hex: hex) }
    /// Lifted toward white; the top of the StandBy numeral gradients.
    var light: Color { mix(toward: 0xFFFFFF, by: self == .white ? 0 : 0.42) }
    /// Pushed toward black; the bottom of the gradients.
    var deep: Color { mix(toward: 0x000000, by: self == .white ? 0.22 : 0.28) }

    var gradient: LinearGradient {
        LinearGradient(colors: [light, base, deep], startPoint: .top, endPoint: .bottom)
    }

    func mix(toward other: UInt32, by t: Double) -> Color {
        func channel(_ v: UInt32, _ shift: UInt32) -> Double { Double((v >> shift) & 0xFF) / 255 }
        let r = channel(hex, 16) + (channel(other, 16) - channel(hex, 16)) * t
        let g = channel(hex, 8) + (channel(other, 8) - channel(hex, 8)) * t
        let b = channel(hex, 0) + (channel(other, 0) - channel(hex, 0)) * t
        return Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

/// The widgets' accent color, or nil for Apple's own colors (red calendar,
/// orange second hands, and so on).
private struct WidgetTintKey: EnvironmentKey {
    static let defaultValue: Tint? = nil
}

extension EnvironmentValues {
    var widgetTint: Tint? {
        get { self[WidgetTintKey.self] }
        set { self[WidgetTintKey.self] = newValue }
    }
}

/// StandBy's red-only night rendering, applied to the whole scene.
struct NightFilter: ViewModifier {
    var isOn: Bool
    func body(content: Content) -> some View {
        content
            .grayscale(isOn ? 1 : 0)
            .colorMultiply(isOn ? Palette.nightRed : .white)
            .animation(.easeInOut(duration: 1.5), value: isOn)
    }
}

func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
    let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
}

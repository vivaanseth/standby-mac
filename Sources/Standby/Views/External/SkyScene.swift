import SwiftUI

/// A window onto the sky where you are. The real sun and moon cross it, the
/// colors follow the sun's actual elevation (night, blue hour, golden hour,
/// day), stars come out after dark with the odd shooting star, and layered
/// hills sit along the bottom.
struct SkyScene: View {
    var date: Date
    var size: CGSize
    var location: GeoPoint
    var format: TimeFormat
    var weather: WeatherSnapshot?
    var clock: OverlayClock = .digital
    var tint: Tint = .orange

    var body: some View {
        let s = min(size.width / 1.6, size.height)
        let sky = SkyState(date: date, location: location)
        ZStack(alignment: .topLeading) {
            SkyCanvas(date: date, sky: sky)
            if let moon = sky.moonPoint(in: size) {
                MoonDisk(fraction: sky.moonPhase.fraction)
                    .frame(width: size.height * 0.11, height: size.height * 0.11)
                    .opacity(0.45 + 0.55 * sky.darkness)
                    .position(moon)
            }
            Ridges(minuteStamp: Int(date.timeIntervalSince1970 / 60), horizon: sky.horizonRGB)
                .equatable()

            // The time sits on the dark hills, so the sky stays clear for the
            // sun and moon and the text is always readable.
            VStack(alignment: .leading, spacing: s * 0.012) {
                switch clock {
                case .digital:
                    Text(TimeText.clock(date, format: format))
                        .font(.system(size: s * 0.2, weight: .thin))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(.white)
                case .analog:
                    AnalogDial(date: date, style: .analogFace(tint, face: .black.opacity(0.45)))
                        .frame(width: s * 0.3, height: s * 0.3)
                }
                footer(sky, s: s)
            }
            .shadow(color: .black.opacity(0.3), radius: s * 0.015, y: s * 0.003)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.leading, s * 0.08)
            .padding(.bottom, s * 0.055)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private func footer(_ sky: SkyState, s: CGFloat) -> some View {
        HStack(spacing: s * 0.035) {
            Text(TimeText.format(date, "EEEEMMMMd"))
                .foregroundStyle(.white.opacity(0.9))
            if let next = sky.nextSunEvent(after: date) {
                Label(TimeText.format(next.time, "jmm"), systemImage: next.isRise ? "sunrise.fill" : "sunset.fill")
            }
            Label(sky.moonPhase.name, systemImage: sky.moonPhase.symbol)
            if let weather {
                Label("\(weather.temperatureText) \(weather.condition)", systemImage: weather.symbol)
            }
            Text(location.name)
        }
        .labelStyle(SkyLabelStyle(gap: s * 0.012))
        .font(.system(size: s * 0.032, weight: .medium))
        .foregroundStyle(.white.opacity(0.78))
    }
}

private struct SkyLabelStyle: LabelStyle {
    var gap: CGFloat
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: gap) {
            configuration.icon.symbolRenderingMode(.hierarchical)
            configuration.title
        }
    }
}

/// Where the sun and moon are, and what color the sky should be.
struct SkyState {
    let elevation: Double
    let hourAngle: Double
    let moonPhase: MoonPhase
    let palette: [Color]
    let horizonRGB: (Double, Double, Double)
    /// 0 in daylight, 1 in full night.
    let darkness: Double
    let location: GeoPoint

    init(date: Date, location: GeoPoint) {
        self.location = location
        elevation = SolarMath.elevation(at: date, latitude: location.latitude, longitude: location.longitude)
        hourAngle = SolarMath.hourAngle(at: date, longitude: location.longitude)
        moonPhase = MoonPhase(date: date)
        palette = SkyPalette.colors(elevation: elevation)
        horizonRGB = SkyPalette.rgbColors(elevation: elevation)[2]
        darkness = 1 - smoothstep(-14, -3, elevation)
    }

    static func horizonY(_ size: CGSize) -> CGFloat { size.height * 0.74 }

    /// Screen position for a body at this hour angle and altitude (degrees).
    static func point(hourAngle: Double, altitude: Double, in size: CGSize) -> CGPoint {
        CGPoint(x: size.width * (0.5 + CGFloat(hourAngle / 90) * 0.38),
                y: horizonY(size) - CGFloat(altitude / 90) * size.height * 0.85)
    }

    func sunPoint(in size: CGSize) -> CGPoint {
        Self.point(hourAngle: hourAngle, altitude: elevation, in: size)
    }

    /// The moon trails the sun by its phase: opposite it when full. Its height
    /// is approximated from that hour angle, which is plenty for a picture.
    func moonPoint(in size: CGSize) -> CGPoint? {
        var ha = hourAngle - moonPhase.fraction * 360
        ha = (ha + 540).truncatingRemainder(dividingBy: 360) - 180
        guard abs(ha) < 88, moonPhase.illumination > 0.04 else { return nil }
        let altitude = cos(ha * .pi / 180) * (90 - abs(location.latitude) * 0.6)
        return Self.point(hourAngle: ha, altitude: altitude, in: size)
    }

    func nextSunEvent(after date: Date) -> (time: Date, isRise: Bool)? {
        let today = SolarMath.sunTimes(on: date, latitude: location.latitude, longitude: location.longitude)
        if let rise = today.rise, rise > date { return (rise, true) }
        if let set = today.set, set > date { return (set, false) }
        let tomorrow = date.addingTimeInterval(86400)
        return SolarMath.sunTimes(on: tomorrow, latitude: location.latitude, longitude: location.longitude).rise.map { ($0, true) }
    }
}

/// Sky colors (zenith, middle, horizon) keyed by sun elevation.
enum SkyPalette {
    private static let keys: [(Double, [UInt32])] = [
        (-18, [0x04060D, 0x070A17, 0x0C1122]),
        (-10, [0x090E27, 0x18183F, 0x3A2A58]),
        (-4, [0x182758, 0x5E4580, 0xE07A66]),
        (2, [0x2B4E9C, 0xA9809A, 0xFFA765]),
        (10, [0x2F6ECC, 0x74A8E8, 0xD6DADB]),
        (35, [0x1F64D2, 0x5B9EEB, 0xB6D4F1]),
    ]

    static func colors(elevation e: Double) -> [Color] {
        let rgb = rgbColors(elevation: e)
        return rgb.map { Color(.sRGB, red: $0.0, green: $0.1, blue: $0.2, opacity: 1) }
    }

    static func rgbColors(elevation e: Double) -> [(Double, Double, Double)] {
        let upper = keys.firstIndex { $0.0 >= e } ?? keys.count - 1
        let lower = max(upper - 1, 0)
        let (e0, c0) = keys[lower], (e1, c1) = keys[upper]
        let t = e1 == e0 ? 0 : min(max((e - e0) / (e1 - e0), 0), 1)
        return (0..<3).map { i in
            let a = rgb(c0[i]), b = rgb(c1[i])
            return (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t)
        }
    }

    private static func rgb(_ hex: UInt32) -> (Double, Double, Double) {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }
}

/// Gradient, sun, stars, and the occasional shooting star.
private struct SkyCanvas: View {
    var date: Date
    var sky: SkyState

    var body: some View {
        let t = date.timeIntervalSince1970
        Canvas { ctx, size in
            let full = Path(CGRect(origin: .zero, size: size))
            let horizon = SkyState.horizonY(size)
            ctx.fill(full, with: .linearGradient(
                Gradient(stops: [
                    .init(color: sky.palette[0], location: 0),
                    .init(color: sky.palette[1], location: 0.5),
                    .init(color: sky.palette[2], location: horizon / size.height),
                    .init(color: sky.palette[2], location: 1),
                ]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))

            // Stars: a fixed field that fades in after dusk and twinkles.
            if sky.darkness > 0.02 {
                var rng = SeededRandom(seed: 7)
                for i in 0..<240 {
                    let x = rng.next() * size.width
                    let y = rng.next() * horizon * 0.95
                    let r = (0.5 + rng.next() * rng.next() * 1.6) * size.height / 1080
                    let base = 0.35 + rng.next() * 0.65
                    let twinkle = 0.7 + 0.3 * sin(t * (0.6 + rng.next()) + Double(i))
                    let fade = smoothstep(0, 0.35, 1 - y / horizon) // dimmer near the glow of the horizon
                    let alpha = base * twinkle * sky.darkness * (0.4 + 0.6 * fade)
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                             with: .color(.white.opacity(alpha)))
                }
                // A shooting star for a moment every few minutes.
                let minute = Int(t / 60), second = Int(t) % 60
                if sky.darkness > 0.6, minute % 3 == 0, (14...15).contains(second) {
                    var m = SeededRandom(seed: UInt64(minute))
                    let start = CGPoint(x: size.width * (0.2 + m.next() * 0.6), y: horizon * (0.08 + m.next() * 0.3))
                    let length = size.width * 0.12
                    let end = CGPoint(x: start.x + length, y: start.y + length * 0.35)
                    var streak = Path()
                    streak.move(to: start)
                    streak.addLine(to: end)
                    ctx.stroke(streak, with: .linearGradient(Gradient(colors: [.clear, .white.opacity(0.85)]), startPoint: start, endPoint: end),
                               style: StrokeStyle(lineWidth: size.height / 600, lineCap: .round))
                }
            }

            // The sun's glow reaches over the horizon at dawn and dusk.
            let sun = sky.sunPoint(in: size)
            let warmth = 1 - smoothstep(-2, 25, sky.elevation)
            let glowColor = Color(.sRGB, red: 1, green: 0.96 - 0.32 * warmth, blue: 0.84 - 0.55 * warmth, opacity: 1)
            let glowStrength = smoothstep(-12, 2, sky.elevation)
            if glowStrength > 0 {
                let center = CGPoint(x: sun.x, y: min(sun.y, horizon + size.height * 0.02))
                ctx.fill(full, with: .radialGradient(
                    Gradient(colors: [glowColor.opacity(0.55 * glowStrength), glowColor.opacity(0.18 * glowStrength), .clear]),
                    center: center, startRadius: 0, endRadius: size.height * 0.55))
            }
            if sky.elevation > -1.5 {
                let r = size.height * 0.035
                ctx.fill(Path(ellipseIn: CGRect(x: sun.x - r * 2.4, y: sun.y - r * 2.4, width: r * 4.8, height: r * 4.8)),
                         with: .radialGradient(Gradient(colors: [glowColor.opacity(0.6), .clear]), center: sun, startRadius: r, endRadius: r * 2.4))
                ctx.fill(Path(ellipseIn: CGRect(x: sun.x - r, y: sun.y - r, width: r * 2, height: r * 2)),
                         with: .radialGradient(Gradient(colors: [.white, glowColor]), center: sun, startRadius: 0, endRadius: r))
            }
        }
    }
}

/// Three layers of hills, darker toward the front, tinted by the horizon.
private struct Ridges: View, Equatable {
    var minuteStamp: Int
    var horizon: (Double, Double, Double)

    static func == (a: Ridges, b: Ridges) -> Bool { a.minuteStamp == b.minuteStamp }

    /// The horizon color pulled toward near-black by `t`.
    private func shade(_ t: Double) -> Color {
        let dark = (0.02, 0.027, 0.05)
        return Color(.sRGB,
                     red: horizon.0 + (dark.0 - horizon.0) * t,
                     green: horizon.1 + (dark.1 - horizon.1) * t,
                     blue: horizon.2 + (dark.2 - horizon.2) * t,
                     opacity: 1)
    }

    var body: some View {
        Canvas { ctx, size in
            let layers: [(base: CGFloat, amplitude: CGFloat, seed: Double, shade: Double)] = [
                (0.72, 0.045, 1.3, 0.62), (0.80, 0.04, 4.1, 0.8), (0.89, 0.035, 7.7, 0.93),
            ]
            for layer in layers {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: size.height))
                for x in stride(from: 0, through: size.width + 8, by: 8) {
                    let u = Double(x / size.width)
                    let wave = sin(u * 5.1 + layer.seed) * 0.55 + sin(u * 11.3 + layer.seed * 2.1) * 0.3 + sin(u * 23.7 + layer.seed * 3.7) * 0.15
                    path.addLine(to: CGPoint(x: x, y: size.height * (layer.base - layer.amplitude * CGFloat(wave))))
                }
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.closeSubpath()
                ctx.fill(path, with: .linearGradient(
                    Gradient(colors: [shade(layer.shade), shade(min(layer.shade + 0.08, 1))]),
                    startPoint: CGPoint(x: 0, y: size.height * (layer.base - layer.amplitude)),
                    endPoint: CGPoint(x: 0, y: size.height)))
            }
        }
    }
}

/// Deterministic random numbers, so the stars stay put between frames.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
}

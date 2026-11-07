import SwiftUI

/// Sizes on every face scale from `s`: the screen height, or the height a 16:10
/// screen of the same width would have, whichever is smaller.
private func unit(_ size: CGSize) -> CGFloat { min(size.width / 1.6, size.height) }

// MARK: Digital

struct DigitalFace: View {
    var date: Date
    var size: CGSize
    var tint: Tint
    var format: TimeFormat
    var weather: WeatherSnapshot?

    var body: some View {
        let s = unit(size)
        let t = TimeText.hourMinute(date, format: format)
        ZStack {
            Text("\(t.hour):\(t.minute)")
                .font(.system(size: s * 0.6, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .kerning(-s * 0.012)
                .foregroundStyle(tint.gradient)
                .lineLimit(1)
                .minimumScaleFactor(0.3)
                .frame(maxWidth: size.width * 0.94)
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.6), value: t.minute)
                .offset(y: s * 0.05)

            VStack {
                HStack(alignment: .firstTextBaseline) {
                    Text(TimeText.format(date, "EEEd"))
                        .foregroundStyle(tint.base)
                    Spacer()
                    if let weather {
                        WeatherBadge(weather: weather, color: tint.base, size: s * 0.055)
                    }
                }
                .font(.system(size: s * 0.055, weight: .semibold, design: .rounded))
                Spacer()
            }
            .padding(.horizontal, s * 0.1)
            .padding(.top, s * 0.075)
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: Analog

struct AnalogFace: View {
    var date: Date
    var size: CGSize
    var tint: Tint
    var weather: WeatherSnapshot?

    var body: some View {
        let s = unit(size)
        let d = s * 0.86
        let style = DialStyle.analogFace(tint)
        HStack(spacing: 0) {
            AnalogDial(date: date, style: style)
                .frame(width: d, height: d)
            VStack(alignment: .leading, spacing: 0) {
                Text(TimeText.format(date, "EEEE").uppercased())
                    .font(.system(size: s * 0.06, weight: .bold, design: .rounded))
                    .foregroundStyle(tint.base)
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(size: s * 0.3, weight: .light, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.vertical, -s * 0.03)
                Text(TimeText.format(date, "MMMM"))
                    .font(.system(size: s * 0.055, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.secondary)
                if let weather {
                    WeatherBadge(weather: weather, color: .white, size: s * 0.05)
                        .padding(.top, s * 0.05)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, (size.width - d) * 0.12)
        .frame(width: size.width, height: size.height)
    }
}

// MARK: World

struct WorldFace: View {
    var date: Date
    var size: CGSize
    var format: TimeFormat
    var location: GeoPoint
    var weather: WeatherSnapshot?

    var body: some View {
        let s = unit(size)
        // As wide as the screen allows, but never up into the time and date
        // (which matters on screens wider than 16:10).
        let roomBelowText = size.height - s * 0.4
        let aspect = CGFloat(WorldMapData.columns) / CGFloat(WorldMapData.rows)
        let mapWidth = min(size.width * 0.94, roomBelowText * aspect)
        let mapHeight = mapWidth / aspect
        ZStack(alignment: .topLeading) {
            WorldMapView(minuteStamp: Int(date.timeIntervalSince1970 / 60),
                         latitude: location.latitude,
                         longitude: location.longitude)
                .equatable()
                .frame(width: mapWidth, height: mapHeight)
                .offset(x: (size.width - mapWidth) / 2, y: size.height - mapHeight - s * 0.02)

            VStack(alignment: .leading, spacing: s * 0.004) {
                Text(TimeText.clock(date, format: format))
                    .font(.system(size: s * 0.2, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                HStack(spacing: s * 0.02) {
                    Text("\(location.name) · \(TimeText.format(date, "EEEMMMd"))")
                        .foregroundStyle(Palette.secondary)
                    if let weather {
                        WeatherBadge(weather: weather, color: Palette.secondary, size: s * 0.042)
                    }
                }
                .font(.system(size: s * 0.042, weight: .semibold))
            }
            .padding(.leading, s * 0.09)
            .padding(.top, s * 0.06)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

/// The dotted world map. Daylight is computed per dot from the real sun
/// position, so the terminator sweeps across the map through the day.
struct WorldMapView: View, Equatable {
    var minuteStamp: Int
    var latitude: Double
    var longitude: Double

    var body: some View {
        Canvas { ctx, size in
            let cols = WorldMapData.columns, rows = WorldMapData.rows
            let cell = size.width / CGFloat(cols)
            let dot = cell * 0.6
            let sun = SolarMath.position(at: Date(timeIntervalSince1970: Double(minuteStamp) * 60))
            let levels = 8
            var buckets = Array(repeating: Path(), count: levels)
            for r in 0..<rows {
                let lat = WorldMapData.topLatitude - (Double(r) + 0.5) * WorldMapData.step
                for c in 0..<cols where WorldMap.land[r][c] {
                    let lon = -180 + (Double(c) + 0.5) * WorldMapData.step
                    let light = smoothstep(-9, 3, SolarMath.elevation(sun, latitude: lat, longitude: lon))
                    let b = min(levels - 1, Int(light * Double(levels)))
                    buckets[b].addEllipse(in: CGRect(x: CGFloat(c) * cell + (cell - dot) / 2,
                                                     y: CGFloat(r) * cell + (cell - dot) / 2,
                                                     width: dot, height: dot))
                }
            }
            for (i, path) in buckets.enumerated() {
                let t = Double(i) / Double(levels - 1)
                ctx.fill(path, with: .color(Color(white: 0.2 + 0.72 * t)))
            }

            let x = CGFloat((longitude + 180) / 360) * size.width
            let y = CGFloat((WorldMapData.topLatitude - latitude) / WorldMapData.step) * cell
            for (radius, alpha) in [(cell * 3.2, 0.12), (cell * 2.1, 0.22)] {
                ctx.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                         with: .color(Palette.yellow.opacity(alpha)))
            }
            let r = cell * 0.95
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(Palette.yellow))
        }
    }
}

enum WorldMap {
    static let land: [[Bool]] = WorldMapData.land.map { $0.map { $0 == "1" } }
}

// MARK: Solar

struct SolarFace: View {
    var date: Date
    var size: CGSize
    var tint: Tint
    var format: TimeFormat
    var location: GeoPoint
    var weather: WeatherSnapshot?

    var body: some View {
        let s = unit(size)
        let minute = Int(date.timeIntervalSince1970 / 60)
        ZStack(alignment: .topLeading) {
            SunView(minuteStamp: minute, latitude: location.latitude, longitude: location.longitude, tint: tint)
                .equatable()
            VStack(alignment: .leading, spacing: 0) {
                Text(TimeText.clock(date, format: format))
                    .font(.system(size: s * 0.23, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                HStack(spacing: s * 0.025) {
                    Text(TimeText.format(date, "EEEEMMMMd"))
                    if let weather {
                        WeatherBadge(weather: weather, color: tint.light, size: s * 0.045)
                    }
                }
                .font(.system(size: s * 0.045, weight: .semibold))
                .foregroundStyle(tint.light)
                .padding(.top, -s * 0.01)
            }
            .padding(.leading, s * 0.09)
            .padding(.top, s * 0.07)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

/// The sun rides an arc over a horizon according to its real elevation, with
/// a flare whose strength follows dawn, day, and dusk.
struct SunView: View, Equatable {
    var minuteStamp: Int
    var latitude: Double
    var longitude: Double
    var tint: Tint

    var body: some View {
        Canvas { ctx, size in
            let date = Date(timeIntervalSince1970: Double(minuteStamp) * 60)
            let elevation = SolarMath.elevation(at: date, latitude: latitude, longitude: longitude)
            let hourAngle = SolarMath.hourAngle(at: date, longitude: longitude)
            let horizon = size.height * 0.8
            // The sun crosses the right side of the screen, sunrise to sunset,
            // leaving the left for the time.
            let x = size.width * (0.7 + CGFloat(hourAngle / 90) * 0.22)
            let y = horizon - CGFloat(max(elevation, -20) / 90) * size.height * 1.05
            let sun = CGPoint(x: x, y: y)
            let radius = size.height * 0.085
            let daylight = smoothstep(-16, 8, elevation)

            ctx.drawLayer { sky in
                sky.clip(to: Path(CGRect(x: 0, y: 0, width: size.width, height: horizon)))
                sky.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
                    Gradient(stops: [
                        .init(color: tint.light.opacity(0.7 * daylight), location: 0),
                        .init(color: tint.base.opacity(0.38 * daylight), location: 0.16),
                        .init(color: tint.deep.opacity(0.14 * daylight), location: 0.42),
                        .init(color: .clear, location: 1),
                    ]),
                    center: sun, startRadius: radius * 0.6, endRadius: size.height * 0.95))
                for (scale, alpha) in [(1.9, 0.08), (3.0, 0.045), (4.6, 0.025)] {
                    let r = radius * scale
                    sky.stroke(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                               with: .color(tint.light.opacity(alpha * (0.4 + daylight))),
                               lineWidth: radius * 0.05)
                }
                sky.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                         with: .radialGradient(Gradient(colors: [.white, tint.light, tint.base]),
                                               center: sun, startRadius: 0, endRadius: radius))
            }

            // Horizon: brightest beneath the sun.
            let line = Path(CGRect(x: 0, y: horizon, width: size.width, height: max(1, size.height * 0.002)))
            ctx.fill(line, with: .linearGradient(
                Gradient(stops: [
                    .init(color: .white.opacity(0.12), location: 0),
                    .init(color: tint.light.opacity(0.35 + 0.5 * daylight), location: min(max(x / size.width, 0), 1)),
                    .init(color: .white.opacity(0.12), location: 1),
                ]),
                startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: size.width, y: horizon)))
            // A faint reflection under the horizon.
            ctx.fill(Path(CGRect(x: 0, y: horizon + 1, width: size.width, height: size.height - horizon - 1)),
                     with: .radialGradient(Gradient(colors: [tint.base.opacity(0.16 * daylight), .clear]),
                                           center: CGPoint(x: x, y: horizon), startRadius: 0, endRadius: size.height * 0.5))
        }
    }
}

// MARK: Float

struct FloatFace: View {
    var date: Date
    var size: CGSize
    var tint: Tint
    var format: TimeFormat

    var body: some View {
        let t = TimeText.hourMinute(date, format: format)
        let digits = Array(t.hour + t.minute)
        let n = CGFloat(digits.count)
        let overlap: CGFloat = 0.1
        let fontSize = min(size.height * 1.05, size.width * 0.95 / (n * 0.56 - (n - 1) * overlap))
        let second = Double(Calendar.current.component(.second, from: date))
        HStack(spacing: -fontSize * overlap) {
            ForEach(Array(digits.enumerated()), id: \.offset) { i, ch in
                Text(String(ch))
                    .font(StandbyFonts.compactRounded(size: fontSize, weight: 1000))
                    .foregroundStyle(LinearGradient(colors: shades(i), startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.55), radius: fontSize * 0.035, x: -fontSize * 0.025, y: 0)
                    .offset(y: CGFloat(sin(second * 0.35 + Double(i) * 1.7)) * size.height * 0.012)
                    .zIndex(Double(i))
                    .contentTransition(.numericText())
            }
        }
        .animation(.easeInOut(duration: 1), value: second)
        .frame(width: size.width, height: size.height)
    }

    private func shades(_ i: Int) -> [Color] {
        // Alternate the hour and minute pairs between a lighter and deeper tone.
        let lift = i % 2 == 0 ? 0.32 : 0.12
        return [tint.mix(toward: 0xFFFFFF, by: lift + 0.15), tint.mix(toward: 0xFFFFFF, by: lift * 0.4), tint.deep]
    }
}

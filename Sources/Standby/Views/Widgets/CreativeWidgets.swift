import SwiftUI

// MARK: Moon

struct MoonPhase {
    /// 0 new, 0.25 first quarter, 0.5 full, 0.75 last quarter.
    var fraction: Double

    static let synodicMonth = 29.530588853

    init(date: Date) {
        // A known new moon: 2000-01-06 18:14 UTC.
        let days = (date.timeIntervalSince1970 - 947_182_440) / 86400
        let f = (days / Self.synodicMonth).truncatingRemainder(dividingBy: 1)
        fraction = f < 0 ? f + 1 : f
    }

    var illumination: Double { Self.illumination(fraction) }

    static func illumination(_ fraction: Double) -> Double { (1 - cos(2 * .pi * fraction)) / 2 }

    var name: String {
        switch fraction {
        case ..<0.034: "New Moon"
        case ..<0.216: "Waxing Crescent"
        case ..<0.284: "First Quarter"
        case ..<0.466: "Waxing Gibbous"
        case ..<0.534: "Full Moon"
        case ..<0.716: "Waning Gibbous"
        case ..<0.784: "Last Quarter"
        case ..<0.966: "Waning Crescent"
        default: "New Moon"
        }
    }

    var symbol: String {
        switch name {
        case "Waxing Crescent": "moonphase.waxing.crescent"
        case "First Quarter": "moonphase.first.quarter"
        case "Waxing Gibbous": "moonphase.waxing.gibbous"
        case "Full Moon": "moonphase.full.moon"
        case "Waning Gibbous": "moonphase.waning.gibbous"
        case "Last Quarter": "moonphase.last.quarter"
        case "Waning Crescent": "moonphase.waning.crescent"
        default: "moonphase.new.moon"
        }
    }

    var daysToFull: Double { (fraction < 0.5 ? 0.5 - fraction : 1.5 - fraction) * Self.synodicMonth }
}

struct MoonWidget: View {
    var date: Date
    var u: CGFloat

    var body: some View {
        let phase = MoonPhase(date: date)
        let days = Int(phase.daysToFull.rounded())
        VStack(spacing: 4 * u) {
            MoonDisk(fraction: phase.fraction)
                .frame(width: 112 * u, height: 112 * u)
                .padding(.bottom, -2 * u)
            Text(phase.name)
                .font(.system(size: 15 * u, weight: .semibold))
                .foregroundStyle(.white)
            Text("\(Int((phase.illumination * 100).rounded()))% illuminated")
                .font(.system(size: 11 * u, weight: .medium))
                .foregroundStyle(Palette.secondary)
            Text(days == 0 ? "Full moon tonight" : "Full moon in \(days) day\(days == 1 ? "" : "s")")
                .font(.system(size: 11 * u, weight: .medium))
                .foregroundStyle(Palette.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The moon with its lit portion and a few soft maria.
struct MoonDisk: View {
    var fraction: Double

    var body: some View {
        Canvas { ctx, size in
            // The glow stays inside the canvas so it never shows a square edge.
            let outer = min(size.width, size.height) / 2
            let r = outer * 0.8
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let disk = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))

            let glow = 0.04 + 0.12 * MoonPhase.illumination(fraction)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - outer, y: c.y - outer, width: outer * 2, height: outer * 2)),
                     with: .radialGradient(Gradient(colors: [Color.white.opacity(glow), .clear]),
                                           center: c, startRadius: r * 0.95, endRadius: outer))
            ctx.fill(disk, with: .color(Color(white: 0.12)))

            // Lit side: the limb on one side, closed by the terminator ellipse.
            let side: CGFloat = fraction < 0.5 ? 1 : -1
            let e = CGFloat(cos(2 * .pi * fraction))
            var lit = Path()
            let steps = 48
            for i in 0...steps {
                let t = -Double.pi / 2 + Double.pi * Double(i) / Double(steps)
                let p = CGPoint(x: c.x + side * r * CGFloat(cos(t)), y: c.y + r * CGFloat(sin(t)))
                i == 0 ? lit.move(to: p) : lit.addLine(to: p)
            }
            for i in 0...steps {
                let t = Double.pi / 2 - Double.pi * Double(i) / Double(steps)
                lit.addLine(to: CGPoint(x: c.x + side * e * r * CGFloat(cos(t)), y: c.y + r * CGFloat(sin(t))))
            }
            lit.closeSubpath()
            ctx.fill(lit, with: .radialGradient(Gradient(colors: [Color(hex: 0xF4F1E8), Color(hex: 0xC9C4B6)]),
                                                center: CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.3), startRadius: 0, endRadius: r * 1.6))
            ctx.drawLayer { layer in
                layer.clip(to: lit)
                let maria: [(CGFloat, CGFloat, CGFloat)] = [(-0.25, -0.3, 0.22), (0.2, -0.15, 0.17), (-0.05, 0.25, 0.26), (0.35, 0.35, 0.12), (-0.45, 0.15, 0.1)]
                for (x, y, size) in maria {
                    let rr = r * size
                    layer.fill(Path(ellipseIn: CGRect(x: c.x + r * x - rr, y: c.y + r * y - rr, width: rr * 2, height: rr * 2)),
                               with: .color(Color.black.opacity(0.09)))
                }
            }
        }
    }
}

// MARK: Sunrise & Sunset

struct SunWidget: View {
    var date: Date
    var u: CGFloat
    var location: GeoPoint

    var body: some View {
        let times = SolarMath.sunTimes(on: date, latitude: location.latitude, longitude: location.longitude)
        let progress: Double? = {
            guard let rise = times.rise, let set = times.set, set > rise else { return nil }
            return (date.timeIntervalSince(rise)) / set.timeIntervalSince(rise)
        }()
        VStack(alignment: .leading, spacing: 0) {
            Text(headline(times))
                .font(.system(size: 13 * u, weight: .semibold))
                .foregroundStyle(.white)
            Text(subline(times))
                .font(.system(size: 11 * u, weight: .medium))
                .foregroundStyle(Palette.secondary)
            SunArc(progress: progress)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 4 * u)
            HStack {
                label("sunrise.fill", times.rise)
                Spacer()
                label("sunset.fill", times.set)
            }
        }
        .padding(15 * u)
    }

    private func headline(_ t: (rise: Date?, set: Date?)) -> String {
        if let rise = t.rise, date < rise { return "Sunrise in \(Self.span(rise.timeIntervalSince(date)))" }
        if let set = t.set, date < set { return "Sunset in \(Self.span(set.timeIntervalSince(date)))" }
        return "Sun has set"
    }

    private func subline(_ t: (rise: Date?, set: Date?)) -> String {
        guard let rise = t.rise, let set = t.set else { return location.name }
        return "\(Self.span(set.timeIntervalSince(rise))) of daylight"
    }

    private func label(_ symbol: String, _ time: Date?) -> some View {
        HStack(spacing: 4 * u) {
            Image(systemName: symbol).symbolRenderingMode(.multicolor)
            Text(time.map { TimeText.format($0, "jmm") } ?? "—")
                .foregroundStyle(.white)
        }
        .font(.system(size: 11.5 * u, weight: .semibold))
    }

    static func span(_ seconds: TimeInterval) -> String {
        let m = max(Int(seconds / 60), 0)
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }
}

/// The sun's path over the horizon, traced in gold up to where it is now.
struct SunArc: View {
    var progress: Double?

    var body: some View {
        Canvas { ctx, size in
            let horizon = size.height * 0.78
            let left = size.width * 0.04, right = size.width * 0.96
            let peak = size.height * 0.08
            func point(_ t: Double) -> CGPoint {
                let x = left + (right - left) * CGFloat(t)
                let y = horizon - (horizon - peak) * CGFloat(sin(.pi * t))
                return CGPoint(x: x, y: y)
            }
            var arc = Path()
            for i in 0...60 { i == 0 ? arc.move(to: point(Double(i) / 60)) : arc.addLine(to: point(Double(i) / 60)) }
            let w = max(size.height * 0.035, 1.5)
            ctx.stroke(arc, with: .color(Color.white.opacity(0.22)), style: StrokeStyle(lineWidth: w * 0.6, lineCap: .round, dash: [w * 0.6, w * 1.6]))

            var line = Path()
            line.move(to: CGPoint(x: 0, y: horizon))
            line.addLine(to: CGPoint(x: size.width, y: horizon))
            ctx.stroke(line, with: .color(Color.white.opacity(0.3)), lineWidth: max(1, w * 0.35))

            guard let progress, progress > 0, progress < 1 else { return }
            var done = Path()
            let steps = max(Int(progress * 60), 1)
            for i in 0...steps {
                let p = point(progress * Double(i) / Double(steps))
                i == 0 ? done.move(to: p) : done.addLine(to: p)
            }
            ctx.stroke(done, with: .linearGradient(Gradient(colors: [Palette.orange, Palette.yellow]),
                                                   startPoint: CGPoint(x: left, y: horizon), endPoint: point(progress)),
                       style: StrokeStyle(lineWidth: w, lineCap: .round))
            let sun = point(progress)
            let r = w * 2.4
            ctx.fill(Path(ellipseIn: CGRect(x: sun.x - r * 2.2, y: sun.y - r * 2.2, width: r * 4.4, height: r * 4.4)),
                     with: .radialGradient(Gradient(colors: [Palette.yellow.opacity(0.45), .clear]), center: sun, startRadius: 0, endRadius: r * 2.2))
            ctx.fill(Path(ellipseIn: CGRect(x: sun.x - r, y: sun.y - r, width: r * 2, height: r * 2)), with: .color(Palette.yellow))
        }
    }
}

// MARK: Flip Clock

struct FlipClockWidget: View {
    var date: Date
    var u: CGFloat
    var format: TimeFormat

    var body: some View {
        let t = TimeText.hourMinute(date, format: format)
        let hour = Calendar.current.component(.hour, from: date)
        VStack(spacing: 10 * u) {
            HStack(spacing: 7 * u) {
                card(t.hour.count == 1 ? " " + t.hour : t.hour,
                     corner: TimeText.uses24Hour(format) ? nil : (hour < 12 ? "AM" : "PM"))
                card(t.minute, corner: nil)
            }
            Text(TimeText.format(date, "EEEd").uppercased())
                .font(.system(size: 11 * u, weight: .bold))
                .foregroundStyle(Palette.secondary)
                .kerning(1 * u)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func card(_ digits: String, corner: String?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10 * u, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x3A3A3C), Color(hex: 0x2C2C2E), Color(hex: 0x1C1C1E)],
                                     startPoint: .top, endPoint: .bottom))
            Text(digits.trimmingCharacters(in: .whitespaces))
                .font(.system(size: 54 * u, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color(white: 0.94))
                .contentTransition(.numericText())
            // The split between the two flaps, with its hinge pins.
            Rectangle().fill(Color.black.opacity(0.85)).frame(height: 1.6 * u)
            HStack {
                Capsule().fill(Color.black).frame(width: 3 * u, height: 9 * u)
                Spacer()
                Capsule().fill(Color.black).frame(width: 3 * u, height: 9 * u)
            }
            .padding(.horizontal, -1 * u)
            if let corner {
                Text(corner)
                    .font(.system(size: 8 * u, weight: .heavy))
                    .foregroundStyle(Palette.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(6 * u)
            }
        }
        .frame(width: 70 * u, height: 92 * u)
        .shadow(color: .black.opacity(0.6), radius: 4 * u, y: 3 * u)
        .animation(.smooth(duration: 0.5), value: digits)
    }
}

// MARK: Word Clock

struct WordClockWidget: View {
    var date: Date
    var u: CGFloat
    @Environment(\.widgetTint) private var tint

    private static let grid = [
        "ITLISASAMPM", "ACQUARTERDC", "TWENTYFIVEX", "HALFSTENFTO", "PASTERUNINE",
        "ONESIXTHREE", "FOURFIVETWO", "EIGHTELEVEN", "SEVENTWELVE", "TENSEOCLOCK",
    ].map(Array.init)

    /// (row, first column, length) for each word.
    private static let words: [String: (Int, Int, Int)] = [
        "IT": (0, 0, 2), "IS": (0, 3, 2), "A": (1, 0, 1), "QUARTER": (1, 2, 7),
        "TWENTY": (2, 0, 6), "FIVE_M": (2, 6, 4), "HALF": (3, 0, 4), "TEN_M": (3, 5, 3),
        "TO": (3, 9, 2), "PAST": (4, 0, 4), "OCLOCK": (9, 5, 6),
        "1": (5, 0, 3), "2": (6, 8, 3), "3": (5, 6, 5), "4": (6, 0, 4), "5": (6, 4, 4), "6": (5, 3, 3),
        "7": (8, 0, 5), "8": (7, 0, 5), "9": (4, 7, 4), "10": (9, 0, 3), "11": (7, 5, 6), "12": (8, 5, 6),
    ]

    var body: some View {
        let lit = Self.litCells(for: date)
        let extra = Calendar.current.component(.minute, from: date) % 5
        ZStack {
            VStack(spacing: 2.2 * u) {
                ForEach(0..<Self.grid.count, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(0..<Self.grid[r].count, id: \.self) { c in
                            let on = lit.contains(r * 100 + c)
                            Text(String(Self.grid[r][c]))
                                .font(.system(size: 11.5 * u, weight: on ? .heavy : .medium, design: .rounded))
                                .foregroundStyle(on ? (tint?.light ?? Color.white) : Color(white: 0.2))
                                .shadow(color: on ? .white.opacity(0.5) : .clear, radius: 3 * u)
                                .frame(width: 12.2 * u)
                        }
                    }
                }
            }
            // One dot per minute past the five-minute mark, in the corners.
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .fill(i < extra ? Color.white : Color(white: 0.2))
                    .frame(width: 4 * u, height: 4 * u)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: [.topLeading, .topTrailing, .bottomTrailing, .bottomLeading][i])
            }
            .padding(8 * u)
        }
        .animation(.easeInOut(duration: 0.8), value: lit)
    }

    private static func litCells(for date: Date) -> Set<Int> {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minute = (c.minute ?? 0) / 5 * 5
        var hour = (c.hour ?? 0) % 12
        var names = ["IT", "IS"]
        switch minute {
        case 0: names.append("OCLOCK")
        case 5: names += ["FIVE_M", "PAST"]
        case 10: names += ["TEN_M", "PAST"]
        case 15: names += ["A", "QUARTER", "PAST"]
        case 20: names += ["TWENTY", "PAST"]
        case 25: names += ["TWENTY", "FIVE_M", "PAST"]
        case 30: names += ["HALF", "PAST"]
        case 35: names += ["TWENTY", "FIVE_M", "TO"]
        case 40: names += ["TWENTY", "TO"]
        case 45: names += ["A", "QUARTER", "TO"]
        case 50: names += ["TEN_M", "TO"]
        default: names += ["FIVE_M", "TO"]
        }
        if minute >= 35 { hour = (hour + 1) % 12 }
        names.append(String(hour == 0 ? 12 : hour))
        var cells = Set<Int>()
        for name in names {
            guard let (row, col, len) = words[name] else { continue }
            for i in 0..<len { cells.insert(row * 100 + col + i) }
        }
        return cells
    }
}

// MARK: Time Rings

struct TimeRingsWidget: View {
    var date: Date
    var u: CGFloat
    @Environment(\.widgetTint) private var tint

    /// Activity colors, or three shades of the widget color.
    private var colors: [Color] { tint.map { [$0.light, $0.base, $0.deep] } ?? Self.colors }

    private static let colors = [Color(hex: 0xFA114F), Color(hex: 0xA6FF00), Color(hex: 0x00E5F0)]

    var body: some View {
        let values = Self.progress(at: date)
        let labels = ["DAY", "MONTH", "YEAR"]
        VStack(spacing: 10 * u) {
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    let inset = CGFloat(i) * 16 * u
                    ActivityRing(progress: values[i], color: colors[i], width: 13 * u)
                        .padding(inset)
                }
            }
            .frame(width: 100 * u, height: 100 * u)
            HStack(spacing: 10 * u) {
                ForEach(0..<3, id: \.self) { i in
                    VStack(spacing: 1 * u) {
                        Text(labels[i])
                            .font(.system(size: 8.5 * u, weight: .heavy))
                            .foregroundStyle(colors[i])
                        Text("\(Int(values[i] * 100))%")
                            .font(.system(size: 13 * u, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    static func progress(at date: Date) -> [Double] {
        let cal = Calendar.current
        func fraction(_ unit: Calendar.Component) -> Double {
            guard let interval = cal.dateInterval(of: unit, for: date) else { return 0 }
            return date.timeIntervalSince(interval.start) / interval.duration
        }
        return [fraction(.day), fraction(.month), fraction(.year)]
    }
}

struct ActivityRing: View {
    var progress: Double
    var color: Color
    var width: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.2), lineWidth: width)
            Circle()
                .trim(from: 0, to: max(progress, 0.005))
                .stroke(LinearGradient(colors: [color.opacity(0.75), color], startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(width / 2)
    }
}

// MARK: Countdown

struct CountdownWidget: View {
    @Environment(\.widgetTint) private var tint
    var date: Date
    var u: CGFloat
    var title: String
    var target: Date?

    var body: some View {
        let cal = Calendar.current
        let goal = target ?? cal.date(from: DateComponents(year: cal.component(.year, from: date) + 1, month: 1, day: 1)) ?? date
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: goal)).day ?? 0
        let remaining = goal.timeIntervalSince(date)
        VStack(spacing: 0) {
            Text(title.isEmpty ? "Countdown" : title)
                .font(.system(size: 14 * u, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Group {
                if days > 0 {
                    Text("\(days)")
                } else if remaining > 0 {
                    Text(SunWidget.span(remaining))
                } else {
                    Text(days == 0 ? "Today" : "\(-days)")
                }
            }
            .font(.system(size: (days > 0 || days < 0 ? 70 : 40) * u, weight: .heavy, design: .rounded))
            .foregroundStyle(LinearGradient(colors: tint.map { [$0.light, $0.base] } ?? [Color(hex: 0xFFB340), Color(hex: 0xFF375F)],
                                            startPoint: .top, endPoint: .bottom))
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .contentTransition(.numericText())
            Text(days > 1 ? "DAYS TO GO" : days == 1 ? "DAY TO GO" : days == 0 ? (remaining > 0 ? "TO GO" : "IT'S HERE") : "DAYS AGO")
                .font(.system(size: 10 * u, weight: .heavy))
                .kerning(1 * u)
                .foregroundStyle(Palette.secondary)
            Text(TimeText.format(goal, "EEEMMMdy"))
                .font(.system(size: 11 * u, weight: .medium))
                .foregroundStyle(Palette.secondary)
                .padding(.top, 6 * u)
        }
        .padding(12 * u)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: Note

struct NoteWidget: View {
    @Environment(\.widgetTint) private var tint
    var u: CGFloat
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8 * u) {
            Label("Note", systemImage: "note.text")
                .font(.system(size: 12 * u, weight: .bold))
                .foregroundStyle(tint?.base ?? Palette.yellow)
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Write a note in Standby Settings → Widgets.")
                    .font(.system(size: 13 * u, weight: .medium))
                    .foregroundStyle(Palette.secondary)
            } else {
                Text(text)
                    .font(.system(size: 17 * u, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(7)
                    .minimumScaleFactor(0.5)
            }
            Spacer(minLength: 0)
        }
        .padding(15 * u)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: Mac Activity

struct MacStatsWidget: View {
    @Environment(\.widgetTint) private var tint
    var u: CGFloat
    @EnvironmentObject private var power: PowerService

    var body: some View {
        VStack(spacing: 12 * u) {
            HStack(spacing: 14 * u) {
                gauge("CPU", power.cpu, tint.map { [$0.light, $0.base] } ?? [Color(hex: 0x64D2FF), Color(hex: 0x0A84FF)])
                gauge("MEMORY", power.memory, tint.map { [$0.base, $0.deep] } ?? [Color(hex: 0xDA8FFF), Color(hex: 0xBF5AF2)])
            }
            Text("Up \(Self.uptime(ProcessInfo.processInfo.systemUptime))")
                .font(.system(size: 11 * u, weight: .semibold))
                .foregroundStyle(Palette.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func gauge(_ title: String, _ value: Double, _ colors: [Color]) -> some View {
        VStack(spacing: 6 * u) {
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 8 * u, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Circle()
                    .trim(from: 0, to: 0.75 * min(max(value, 0.01), 1))
                    .stroke(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom),
                            style: StrokeStyle(lineWidth: 8 * u, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Text("\(Int((value * 100).rounded()))%")
                    .font(.system(size: 16 * u, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
            .frame(width: 62 * u, height: 62 * u)
            .animation(.smooth(duration: 0.8), value: value)
            Text(title)
                .font(.system(size: 9 * u, weight: .heavy))
                .kerning(0.8 * u)
                .foregroundStyle(colors[1])
        }
    }

    static func uptime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        let d = minutes / 1440, h = minutes / 60 % 24, m = minutes % 60
        if d > 0 { return "\(d)d \(h)h" }
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

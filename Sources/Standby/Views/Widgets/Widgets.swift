import SwiftUI

/// One widget at StandBy size. Every widget is laid out on a 170pt grid (the
/// small widget size) and scaled by `u`, so text is re-rendered rather than
/// magnified.
struct WidgetView: View {
    var kind: WidgetKind
    var date: Date
    var side: CGFloat
    var config: StandbyConfig

    var body: some View {
        let u = side / 170
        ZStack {
            if config.showWidgetBackgrounds && kind != .photo {
                RoundedRectangle(cornerRadius: 26 * u, style: .continuous).fill(Palette.widgetBackground)
            }
            content(u)
        }
        .frame(width: side, height: side)
    }

    @ViewBuilder
    private func content(_ u: CGFloat) -> some View {
        switch kind {
        case .analogClock: AnalogClockWidget(date: date, u: u)
        case .calendarMonth: CalendarMonthWidget(date: date, u: u)
        case .upNext: UpNextWidget(date: date, u: u)
        case .date: DateWidget(date: date, u: u)
        case .digitalClock: DigitalClockWidget(date: date, u: u, format: config.timeFormat)
        case .worldClock: WorldClockWidget(date: date, u: u, zones: config.worldClockZones)
        case .weather: WeatherWidget(u: u, hasPlace: config.weatherPlace != nil)
        case .battery: BatteryWidget(u: u)
        case .photo: PhotoWidget(u: u)
        case .moon: MoonWidget(date: date, u: u)
        case .sun: SunWidget(date: date, u: u, location: ZoneInfo.current(for: config))
        case .flipClock: FlipClockWidget(date: date, u: u, format: config.timeFormat)
        case .wordClock: WordClockWidget(date: date, u: u)
        case .rings: TimeRingsWidget(date: date, u: u)
        case .countdown: CountdownWidget(date: date, u: u, title: config.countdownTitle, target: config.countdownDate)
        case .note: NoteWidget(u: u, text: config.noteText)
        case .macStats: MacStatsWidget(u: u)
        }
    }
}

struct AnalogClockWidget: View {
    var date: Date
    var u: CGFloat

    var body: some View {
        var style = DialStyle.widget
        style.label = ZoneInfo.abbreviation(for: TimeZone.current.identifier)
        return AnalogDial(date: date, style: style)
            .padding(4 * u)
    }
}

struct CalendarMonthWidget: View {
    var date: Date
    var u: CGFloat

    var body: some View {
        let cal = Calendar.current
        let today = cal.component(.day, from: date)
        let weeks = Self.weeks(for: date, calendar: cal)
        let firstWeekday = cal.firstWeekday
        let symbols = (0..<7).map { cal.veryShortStandaloneWeekdaySymbols[($0 + firstWeekday - 1) % 7] }
        let weekendColumns = Set((0..<7).filter { [1, 7].contains(($0 + firstWeekday - 1) % 7 + 1) })
        // Five-week months get roomier rows so the grid fills the widget.
        let row = weeks.count > 5 ? 18.5 * u : 21.5 * u

        VStack(alignment: .leading, spacing: 5 * u) {
            Text(TimeText.format(date, "MMMM").uppercased())
                .font(.system(size: 12 * u, weight: .bold))
                .foregroundStyle(Palette.red)
                .padding(.leading, 3 * u)
            Grid(horizontalSpacing: 0, verticalSpacing: 2 * u) {
                GridRow {
                    ForEach(0..<7, id: \.self) { i in
                        Text(symbols[i])
                            .font(.system(size: 9.5 * u, weight: .bold))
                            .foregroundStyle(weekendColumns.contains(i) ? Palette.secondary.opacity(0.7) : Palette.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(weeks.indices, id: \.self) { w in
                    GridRow {
                        ForEach(0..<7, id: \.self) { i in
                            if let day = weeks[w][i] {
                                ZStack {
                                    if day == today {
                                        Circle().fill(Palette.red).frame(width: 19 * u, height: 19 * u)
                                    }
                                    Text("\(day)")
                                        .font(.system(size: 11 * u, weight: day == today ? .bold : .semibold))
                                        .foregroundStyle(day == today || !weekendColumns.contains(i) ? Color.white : Palette.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: row)
                            } else {
                                Color.clear.frame(maxWidth: .infinity).frame(height: row)
                            }
                        }
                    }
                }
            }
        }
        .padding(13 * u)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    static func weeks(for date: Date, calendar cal: Calendar) -> [[Int?]] {
        guard let interval = cal.dateInterval(of: .month, for: date),
              let days = cal.range(of: .day, in: .month, for: date) else { return [] }
        let leading = (cal.component(.weekday, from: interval.start) - cal.firstWeekday + 7) % 7
        var cells: [Int?] = Array(repeating: nil, count: leading) + days.map { Optional($0) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }
}

struct UpNextWidget: View {
    var date: Date
    var u: CGFloat
    @EnvironmentObject private var calendar: CalendarService

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(TimeText.format(date, "EEEE").uppercased())
                .font(.system(size: 11 * u, weight: .bold))
                .foregroundStyle(Palette.red)
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.system(size: 40 * u, weight: .regular))
                .foregroundStyle(.white)
                .padding(.top, -2 * u)
            Spacer(minLength: 4 * u)
            if !calendar.hasAccess {
                Text("Allow Calendar access in Standby Settings")
                    .font(.system(size: 11 * u, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
            } else if calendar.events.isEmpty {
                Text("No more events today")
                    .font(.system(size: 12 * u, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6 * u) {
                    ForEach(calendar.events.prefix(2)) { event in
                        HStack(spacing: 6 * u) {
                            RoundedRectangle(cornerRadius: 1.5 * u).fill(event.color).frame(width: 3.5 * u)
                            VStack(alignment: .leading, spacing: 1 * u) {
                                Text(event.title)
                                    .font(.system(size: 12 * u, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text(TimeText.eventTime(event))
                                    .font(.system(size: 10.5 * u, weight: .medium))
                                    .foregroundStyle(Palette.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(height: 30 * u)
                    }
                }
            }
        }
        .padding(15 * u)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct DateWidget: View {
    var date: Date
    var u: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Text(TimeText.format(date, "EEEE").uppercased())
                .font(.system(size: 15 * u, weight: .bold))
                .foregroundStyle(Palette.red)
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.system(size: 92 * u, weight: .light))
                .foregroundStyle(.white)
                .padding(.vertical, -8 * u)
            Text(TimeText.format(date, "MMMMy"))
                .font(.system(size: 13 * u, weight: .semibold))
                .foregroundStyle(Palette.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DigitalClockWidget: View {
    var date: Date
    var u: CGFloat
    var format: TimeFormat

    var body: some View {
        let t = TimeText.hourMinute(date, format: format)
        VStack(spacing: 4 * u) {
            Text("\(t.hour):\(t.minute)")
                .font(.system(size: 62 * u, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
                .animation(.smooth, value: t.minute)
            Text(TimeText.format(date, "EEEEMMMd"))
                .font(.system(size: 13 * u, weight: .semibold))
                .foregroundStyle(Palette.secondary)
        }
        .padding(10 * u)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WorldClockWidget: View {
    var date: Date
    var u: CGFloat
    var zones: [String]

    var body: some View {
        let shown = Array(zones.compactMap { TimeZone(identifier: $0) }.prefix(4))
        Grid(horizontalSpacing: 12 * u, verticalSpacing: 10 * u) {
            ForEach(Array(stride(from: 0, to: shown.count, by: 2)), id: \.self) { row in
                GridRow {
                    ForEach(row..<min(row + 2, shown.count), id: \.self) { i in
                        cell(shown[i])
                    }
                }
            }
        }
        .padding(10 * u)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func cell(_ zone: TimeZone) -> some View {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let hour = cal.component(.hour, from: date)
        let isDay = (6..<18).contains(hour)
        return VStack(spacing: 3 * u) {
            AnalogDial(date: date, timeZone: zone, style: .worldClock(isDay: isDay))
                .frame(width: 50 * u, height: 50 * u)
            Text(ZoneInfo.cityName(for: zone.identifier))
                .font(.system(size: 10.5 * u, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(TimeText.relativeOffset(for: zone, at: date))
                .font(.system(size: 8.5 * u, weight: .semibold))
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 66 * u)
    }
}

struct WeatherWidget: View {
    var u: CGFloat
    var hasPlace: Bool
    @EnvironmentObject private var weather: WeatherService

    var body: some View {
        Group {
            if let w = weather.snapshot {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 3 * u) {
                        Text(w.placeName)
                            .font(.system(size: 14 * u, weight: .semibold))
                            .lineLimit(1)
                        Image(systemName: "location.fill").font(.system(size: 8 * u, weight: .semibold))
                    }
                    Text(w.temperatureText)
                        .font(.system(size: 44 * u, weight: .light))
                        .padding(.top, -2 * u)
                    Spacer(minLength: 0)
                    Image(systemName: w.symbol)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 17 * u))
                        .padding(.bottom, 3 * u)
                    Text(w.condition).font(.system(size: 12 * u, weight: .semibold))
                    Text(w.rangeText).font(.system(size: 12 * u, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack(spacing: 8 * u) {
                    Image(systemName: "cloud.sun.fill")
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 40 * u))
                    Text("Weather").font(.system(size: 14 * u, weight: .semibold)).foregroundStyle(.white)
                    Text(hasPlace ? "Loading…" : "Choose a city in Standby Settings")
                        .font(.system(size: 11 * u, weight: .medium))
                        .foregroundStyle(Palette.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(15 * u)
    }
}

struct BatteryWidget: View {
    var u: CGFloat
    @EnvironmentObject private var power: PowerService

    var body: some View {
        let b = power.battery
        let color: Color = b.isCharging || b.level > 0.2 ? Palette.green : (b.level > 0.1 ? Palette.yellow : Palette.red)
        VStack(spacing: 12 * u) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.16), lineWidth: 10 * u)
                Circle()
                    .trim(from: 0, to: b.hasBattery ? b.level : 1)
                    .stroke(color, style: StrokeStyle(lineWidth: 10 * u, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 34 * u, weight: .regular))
                    .foregroundStyle(.white)
                if b.isCharging || (!b.hasBattery && b.onAC) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 13 * u, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(4 * u)
                        .background(Circle().fill(Color.black))
                        .offset(y: -50 * u)
                }
            }
            .frame(width: 96 * u, height: 96 * u)
            Text(b.hasBattery ? "\(Int((b.level * 100).rounded()))%" : "Power Adapter")
                .font(.system(size: b.hasBattery ? 28 * u : 15 * u, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PhotoWidget: View {
    var u: CGFloat
    @EnvironmentObject private var photos: PhotoRotator

    var body: some View {
        ZStack {
            if let image = photos.current {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .id(photos.generation)
                    .transition(.opacity)
            } else {
                Palette.widgetBackground
                VStack(spacing: 8 * u) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 36 * u))
                        .foregroundStyle(Palette.secondary)
                    Text("No Photos")
                        .font(.system(size: 13 * u, weight: .semibold))
                        .foregroundStyle(Palette.secondary)
                }
            }
        }
        .frame(width: 170 * u, height: 170 * u)
        .clipShape(RoundedRectangle(cornerRadius: 26 * u, style: .continuous))
        .animation(.easeInOut(duration: 1), value: photos.generation)
    }
}

import SwiftUI

struct WidgetsPage: View {
    var date: Date
    var size: CGSize
    var config: StandbyConfig
    @ObservedObject var nav: StandbyNavigator

    var body: some View {
        let stacks = config.visibleStacks
        let frames = WidgetGrid.frames(count: stacks.count, layout: config.widgetLayout, in: size)
        let showDots = date.timeIntervalSince(nav.lastInteraction) < 2.5
        let neighbors = nav.showsNeighbors(at: date)
        ZStack {
            ForEach(Array(frames.enumerated()), id: \.offset) { i, frame in
                stack(stacks[i], position: nav.stackIndices[i], target: .stack(i), side: frame.width,
                      showDots: showDots, neighbors: neighbors)
                    .position(x: frame.midX, y: frame.midY)
            }
        }
        .frame(width: size.width, height: size.height)
        .animation(.spring(response: 0.55, dampingFraction: 0.85), value: config.widgetLayout)
        .animation(.spring(response: 0.55, dampingFraction: 0.85), value: config.stackCount)
    }

    private func stack(_ kinds: [WidgetKind], position: Int, target: StandbyNavigator.VerticalTarget,
                       side: CGFloat, showDots: Bool, neighbors: Bool) -> some View {
        let u = side / 170
        let count = kinds.count
        let current = count > 0 ? ((position % count) + count) % count : 0
        return ZStack {
            if kinds.isEmpty {
                Color.clear
            } else {
                WidgetStackPager(count: count, position: position,
                                 offset: nav.vTarget == target ? nav.vOffset : 0,
                                 neighbors: neighbors && count > 1) { i in
                    WidgetView(kind: kinds[i], date: date, side: side, config: config)
                }
                .clipShape(RoundedRectangle(cornerRadius: 26 * u, style: .continuous))
            }
        }
        .frame(width: side, height: side)
        .overlay(alignment: .trailing) {
            if count > 1 {
                StackIndicator(count: count, index: current, dot: 5 * u)
                    .offset(x: 12 * u)
                    .opacity(showDots && nav.vTarget == target ? 1 : 0)
                    .animation(.easeOut(duration: 0.3), value: showDots)
            }
        }
    }
}

/// A Smart Stack: widgets loop vertically, and the ones sliding in or out
/// shrink and dim slightly, like stacks on iPhone.
///
/// `position` counts up and down without wrapping (the widget shown is
/// `position` modulo `count`), so each slide animates in the right direction.
struct WidgetStackPager<Content: View>: View {
    var count: Int
    var position: Int
    var offset: CGFloat
    var neighbors: Bool
    @ViewBuilder var content: (Int) -> Content

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            // A single widget only gives a little under your finger.
            let drag = count > 1 ? offset : offset * 0.25
            let slots = neighbors ? Array((position - 1)...(position + 1)) : [position]
            ZStack {
                ForEach(slots, id: \.self) { slot in
                    let p = CGFloat(slot - position) + drag / h
                    let d = min(abs(p), 1)
                    content(((slot % count) + count) % count)
                        .frame(width: geo.size.width, height: h)
                        .scaleEffect(1 - 0.12 * d)
                        .opacity(1 - 0.55 * Double(d))
                        .offset(y: p * h)
                }
            }
            .frame(width: geo.size.width, height: h)
        }
    }
}

struct PhotosPage: View {
    var date: Date
    var size: CGSize
    var config: StandbyConfig
    @EnvironmentObject private var photos: PhotoRotator

    var body: some View {
        let s = min(size.width / 1.6, size.height)
        ZStack {
            Color.black
            if let image = photos.current {
                KenBurnsImage(image: image,
                              seed: photos.generation,
                              enabled: config.photoKenBurns,
                              duration: config.photoInterval + 2)
                    .frame(width: size.width, height: size.height)
                    .id(photos.generation)
                    .transition(.opacity)
            } else {
                LinearGradient(colors: [Color(hex: 0x1C1C1E), .black], startPoint: .top, endPoint: .bottom)
                VStack(spacing: s * 0.025) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: s * 0.11, weight: .light))
                    Text(photos.isScanning ? "Looking for photos…" : "No Photos")
                        .font(.system(size: s * 0.04, weight: .semibold))
                    if !photos.isScanning {
                        Text("Choose a folder of pictures in Standby Settings.")
                            .font(.system(size: s * 0.026, weight: .medium))
                    }
                }
                .foregroundStyle(Palette.secondary)
            }
            if config.photoClockPosition != .hidden {
                clock(s: s)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .animation(.easeInOut(duration: 1.2), value: photos.generation)
    }

    private func clock(s: CGFloat) -> some View {
        let pos = config.photoClockPosition
        let leading = pos == .topLeading || pos == .bottomLeading
        let top = pos == .topLeading || pos == .topTrailing
        let alignment: Alignment = top ? (leading ? .topLeading : .topTrailing) : (leading ? .bottomLeading : .bottomTrailing)
        return VStack(alignment: leading ? .leading : .trailing, spacing: -s * 0.01) {
            Text(TimeText.format(date, "EEEEMMMMd"))
                .font(.system(size: s * 0.042, weight: .semibold))
            switch config.photoClock {
            case .digital:
                Text(TimeText.clock(date, format: config.timeFormat))
                    .font(.system(size: s * 0.19, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            case .analog:
                AnalogDial(date: date, style: .analogFace(config.analogTint, face: .black.opacity(0.45)))
                    .frame(width: s * 0.34, height: s * 0.34)
                    .padding(.top, s * 0.025)
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.35), radius: s * 0.02, y: s * 0.004)
        .padding(.horizontal, s * 0.075)
        .padding(.vertical, s * 0.06)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}

/// A photo that slowly drifts and zooms while it's on screen.
struct KenBurnsImage: View {
    var image: CGImage
    var seed: Int
    var enabled: Bool
    var duration: Double
    @State private var progressed = false

    var body: some View {
        let anchors: [UnitPoint] = [.topLeading, .bottomTrailing, .topTrailing, .bottomLeading, .center, .top, .bottom]
        let anchor = anchors[abs(seed) % anchors.count]
        GeometryReader { geo in
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .scaleEffect(enabled && progressed ? 1.12 : 1.0, anchor: anchor)
                .clipped()
        }
        .onAppear {
            guard enabled else { return }
            withAnimation(.linear(duration: duration)) { progressed = true }
        }
    }
}

struct ClockPage: View {
    var date: Date
    var size: CGSize
    var config: StandbyConfig
    @ObservedObject var nav: StandbyNavigator

    var body: some View {
        let styles = config.enabledClockStyles
        VerticalPager(count: styles.count,
                      index: min(nav.clockIndex, styles.count - 1),
                      offset: nav.vTarget == .clock ? nav.vOffset : 0,
                      neighbors: nav.showsNeighbors(at: date)) { i in
            ClockFace(style: styles[i], date: date, size: size, config: config)
        }
        .frame(width: size.width, height: size.height)
    }
}

struct ClockFace: View {
    var style: ClockStyle
    var date: Date
    var size: CGSize
    var config: StandbyConfig
    @EnvironmentObject private var weather: WeatherService

    var body: some View {
        let w = config.showWeatherOnClocks ? weather.snapshot : nil
        let tint = config.tint(for: style)
        switch style {
        case .digital: DigitalFace(date: date, size: size, tint: tint, format: config.timeFormat, weather: w)
        case .analog: AnalogFace(date: date, size: size, tint: tint, weather: w)
        case .world: WorldFace(date: date, size: size, format: config.timeFormat, location: ZoneInfo.current(for: config), weather: w)
        case .solar: SolarFace(date: date, size: size, tint: tint, format: config.timeFormat, location: ZoneInfo.current(for: config), weather: w)
        case .float: FloatFace(date: date, size: size, tint: tint, format: config.timeFormat)
        }
    }
}

/// "☀︎ 72°" used in the corners of the clock faces.
struct WeatherBadge: View {
    var weather: WeatherSnapshot
    var color: Color
    var size: CGFloat

    var body: some View {
        HStack(spacing: size * 0.3) {
            Image(systemName: weather.symbol)
                .symbolRenderingMode(.multicolor)
            Text(weather.temperatureText)
                .foregroundStyle(color)
        }
        .font(.system(size: size, weight: .semibold, design: .rounded))
    }
}

import SwiftUI

/// The whole StandBy screen at a given moment: the three horizontally paged
/// views, plus night mode, dimming, and burn-in shift.
struct StandbyScene: View {
    var date: Date
    var config: StandbyConfig
    @ObservedObject var nav: StandbyNavigator

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let pages = config.visiblePages
            let current = min(nav.page, pages.count - 1)
            let neighbors = nav.showsNeighbors(at: date)
            ZStack {
                Color.black
                ForEach(Array(pages.enumerated()), id: \.element) { i, kind in
                    if i == current || (neighbors && abs(i - current) == 1) {
                        page(kind, size: size)
                            .frame(width: size.width, height: size.height)
                            .offset(x: CGFloat(i - current) * size.width + nav.hOffset)
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .offset(burnInShift)
            .animation(.easeInOut(duration: 2), value: burnInShift)
            .clipped()
            .compositingGroup()
            .modifier(NightFilter(isOn: config.isNight(at: date)))
            .overlay(Color.black.opacity(1 - min(max(config.brightness, 0.1), 1)).allowsHitTesting(false))
        }
        .background(Color.black)
    }

    @ViewBuilder
    private func page(_ kind: PageKind, size: CGSize) -> some View {
        switch kind {
        case .widgets: WidgetsPage(date: date, size: size, config: config, nav: nav)
        case .photos: PhotosPage(date: date, size: size, config: config)
        case .clock: ClockPage(date: date, size: size, config: config, nav: nav)
        }
    }

    /// A few points of drift each minute so static elements never sit on the
    /// same pixels for long.
    private var burnInShift: CGSize {
        guard config.burnInProtection else { return .zero }
        let pattern: [(CGFloat, CGFloat)] = [(0, 0), (2, 1), (3, -1), (1, -3), (-1, -2), (-3, -1), (-2, 2), (0, 3)]
        let p = pattern[Int(date.timeIntervalSince1970 / 60) % pattern.count]
        return CGSize(width: p.0, height: p.1)
    }
}

/// The live, interactive StandBy used in the overlay window.
struct OverlayRootView: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var nav: StandbyNavigator
    var onWake: () -> Void

    var body: some View {
        GeometryReader { geo in
            Group {
                if nav.isActive {
                    // Anchored to a whole second so minute changes land on time.
                    TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: 1)) { timeline in
                        StandbyScene(date: timeline.date, config: store.config, nav: nav)
                    }
                } else {
                    Color.black
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { v in nav.dragChanged(translation: v.translation, start: v.startLocation, size: geo.size) }
                    .onEnded { v in nav.dragEnded(translation: v.translation, predicted: v.predictedEndTranslation, size: geo.size) }
                    .exclusively(before: TapGesture().onEnded { onWake() })
            )
        }
        .ignoresSafeArea()
    }
}

import SwiftUI

@MainActor
final class CompanionState: ObservableObject {
    /// Only true while a window is up, so nothing ticks in the background.
    @Published var isActive = false
}

extension StandbyConfig {
    /// The settings the external display draws with: one page, and for Clock
    /// the chosen face.
    var companionConfig: StandbyConfig {
        var c = self
        c.showWidgets = externalStyle == .widgets
        c.showPhotos = externalStyle == .photos
        c.showClock = externalStyle == .clock
        c.clockStyles = [ClockSlot(style: externalClockStyle, enabled: true)]
        return c
    }
}

/// What an external display shows: the Sky, or one StandBy page.
struct CompanionScene: View {
    var date: Date
    var config: StandbyConfig
    @ObservedObject var nav: StandbyNavigator
    @EnvironmentObject private var weather: WeatherService

    var body: some View {
        GeometryReader { geo in
            switch config.externalStyle {
            case .sky:
                SkyScene(date: date, size: geo.size, location: ZoneInfo.current(for: config),
                         format: config.timeFormat, weather: config.showWeatherOnClocks ? weather.snapshot : nil)
                    .offset(burnInShift)
                    .animation(.easeInOut(duration: 2), value: burnInShift)
                    .compositingGroup()
                    .modifier(NightFilter(isOn: config.isNight(at: date)))
                    .overlay(Color.black.opacity(1 - min(max(config.brightness, 0.1), 1)))
            case .black:
                Color.black
            case .clock, .photos, .widgets:
                StandbyScene(date: date, config: config.companionConfig, nav: nav)
            }
        }
        .background(Color.black)
    }

    private var burnInShift: CGSize {
        guard config.burnInProtection else { return .zero }
        let pattern: [(CGFloat, CGFloat)] = [(0, 0), (2, 1), (3, -1), (1, -3), (-1, -2), (-3, -1), (-2, 2), (0, 3)]
        let p = pattern[Int(date.timeIntervalSince1970 / 60) % pattern.count]
        return CGSize(width: p.0, height: p.1)
    }
}

struct CompanionRootView: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var state: CompanionState
    @ObservedObject var nav: StandbyNavigator

    var body: some View {
        Group {
            if state.isActive {
                TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: 1)) { timeline in
                    CompanionScene(date: timeline.date, config: store.config, nav: nav)
                }
            } else {
                Color.black
            }
        }
        .ignoresSafeArea()
    }
}

import SwiftUI

@MainActor
final class CompanionState: ObservableObject {
    /// Only true while a window is up, so nothing ticks in the background.
    @Published var isActive = false
}

extension StandbyConfig {
    /// These settings with the external display's profile in place of the
    /// built-in display's. Everything else (night mode, weather, the photo
    /// folder, world clock cities, and so on) is shared.
    var companionConfig: StandbyConfig {
        var c = self
        let p = external
        c.showWidgets = p.showWidgets
        c.showPhotos = p.showPhotos
        c.showClock = p.showClock
        c.showSky = p.showSky
        c.showBlank = p.showBlank
        c.stacks = p.stacks
        c.stackCount = p.stackCount
        c.widgetLayout = p.widgetLayout
        c.showWidgetBackgrounds = p.showWidgetBackgrounds
        c.clockStyles = p.clockStyles
        c.digitalTint = p.digitalTint
        c.analogTint = p.analogTint
        c.solarTint = p.solarTint
        c.floatTint = p.floatTint
        c.brightness = p.brightness
        switch p.startPage {
        case .widgets: c.startPage = .widgets
        case .photos: c.startPage = .photos
        case .clock: c.startPage = .clock
        case .sky: c.startPage = .sky
        case .blank: c.startPage = .blank
        }
        c.lastClockStyle = p.startClockStyle
        return c
    }

    var companionWantsPhotos: Bool {
        external.showPhotos || (external.showWidgets
            && external.stacks.prefix(external.stackCount).contains { $0.contains { $0.kind == .photo && $0.enabled } })
    }
}

/// What an external display shows: Standby, drawn with its own profile.
struct CompanionScene: View {
    var date: Date
    var config: StandbyConfig
    @ObservedObject var nav: StandbyNavigator

    var body: some View {
        StandbyScene(date: date, config: config.companionConfig, nav: nav)
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

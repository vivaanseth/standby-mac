import AppKit
import SwiftUI

/// The ambient screens on external displays, shown once neither the built-in
/// display nor the external ones are being used (or, with the lid closed, as a
/// screen saver). Any input at all takes them down.
@MainActor
final class CompanionController {
    let state = CompanionState()
    let nav = StandbyNavigator()
    private(set) var isVisible = false
    private(set) var displayIDs: [CGDirectDisplayID] = []

    private var windows: [CGDirectDisplayID: TransitionWindow] = [:]
    private let makeContent: () -> AnyView

    init(store: ConfigStore, environment: @escaping (CompanionRootView) -> AnyView) {
        let state = state, nav = nav
        makeContent = { environment(CompanionRootView(store: store, state: state, nav: nav)) }
    }

    /// Shows on exactly these displays, adding and removing windows as needed.
    func show(on ids: [CGDirectDisplayID], config: StandbyConfig) {
        if !isVisible {
            nav.prepareForShow(config.companionConfig)
        }
        isVisible = true
        state.isActive = true
        displayIDs = ids
        for id in ids {
            guard let screen = DisplayLocator.screen(for: id) else { continue }
            window(for: id).present(on: screen.frame)
        }
        for (id, window) in windows where !ids.contains(id) {
            window.dismiss()
        }
    }

    func hide(animated: Bool = true) {
        guard isVisible else { return }
        isVisible = false
        displayIDs = []
        for window in windows.values { window.dismiss(animated: animated) }
    }

    private func window(for id: CGDirectDisplayID) -> TransitionWindow {
        if let existing = windows[id] { return existing }
        let window = TransitionWindow(content: makeContent())
        window.onHidden = { [weak self] in
            guard let self, !self.windows.values.contains(where: \.isVisible) else { return }
            self.state.isActive = false
        }
        windows[id] = window
        return window
    }
}

import AppKit
import EventKit
import SwiftUI

struct UpcomingEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
}

@MainActor
final class CalendarService: ObservableObject {
    @Published private(set) var events: [UpcomingEvent] = []
    @Published private(set) var status = EKEventStore.authorizationStatus(for: .event)

    private let store = EKEventStore()
    private var observer: NSObjectProtocol?

    var hasAccess: Bool { status == .fullAccess }

    init() {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        status = EKEventStore.authorizationStatus(for: .event)
        guard hasAccess else {
            events = []
            return
        }
        let now = Date()
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: 2, to: cal.startOfDay(for: now)) ?? now.addingTimeInterval(172_800)
        let predicate = store.predicateForEvents(withStart: cal.startOfDay(for: now), end: end, calendars: nil)
        events = store.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
            .prefix(6)
            .map { e in
                UpcomingEvent(id: e.eventIdentifier ?? UUID().uuidString,
                              title: e.title ?? "Event",
                              start: e.startDate,
                              end: e.endDate,
                              isAllDay: e.isAllDay,
                              color: Color(nsColor: e.calendar?.color ?? .systemRed))
            }
    }

    func setPreview(_ sample: [UpcomingEvent]) {
        status = .fullAccess
        events = sample
    }
}

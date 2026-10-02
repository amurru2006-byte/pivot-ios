import EventKit
import SwiftUI
import UIKit

struct CalendarChoice: Identifiable, Equatable {
    var id: String
    var title: String
    var colorHex: String
    var holiday: Bool
}

@MainActor
final class CalendarService: ObservableObject {
    @Published private(set) var events: [CalendarItem] = []
    @Published private(set) var choices: [CalendarChoice] = []
    @Published private(set) var hasAccess = false
    @Published private(set) var isRefreshing = false
    @Published var error: String?
    @Published private(set) var lastRefresh: Date?
    private let worker = CalendarWorker()
    private var inFlight: Task<CalendarSnapshot, Never>?
    private var lastFilter: CalendarFilter?

    func requestAccess() async {
        do { hasAccess = try await worker.requestAccess() }
        catch { self.error = error.localizedDescription }
    }
    #if DEBUG && targetEnvironment(simulator)
    func loadPreview(_ items: [CalendarItem]) {
        events = items; hasAccess = true
        choices = [.init(id: "preview", title: "Esempio", colorHex: "7EE6CD", holiday: false)]
    }
    #endif
    func refresh(settings: Settings) async {
        guard !PreviewMode.enabled else { return }
        let filter = CalendarFilter(settings)
        while let active = inFlight {
            _ = await active.value
            // Another waiter can resume before the publisher; yield so it can finish.
            await Task.yield()
            if inFlight == nil && lastFilter == filter { return }
        }
        isRefreshing = true
        let task = Task { await worker.snapshot(settings: settings) }
        inFlight = task
        let snapshot = await task.value
        hasAccess = snapshot.hasAccess
        if choices != snapshot.choices { choices = snapshot.choices }
        if events != snapshot.events { events = snapshot.events }
        lastFilter = filter
        lastRefresh = Date()
        inFlight = nil
        isRefreshing = false
    }
    func apply(_ move: PlanMove) async throws { try await worker.apply(move) }
}

private struct CalendarFilter: Equatable {
    var ids: Set<String>
    var titles: Set<String>
    var holidays: Bool
    init(_ settings: Settings) {
        ids = Set(settings.excludedCalendarIDs); titles = Set(settings.excludedCalendarTitles); holidays = settings.excludeHolidays
    }
}
private struct CalendarSnapshot {
    var hasAccess: Bool
    var choices: [CalendarChoice]
    var events: [CalendarItem]
}

private actor CalendarWorker {
    private let eventStore = EKEventStore()
    func requestAccess() async throws -> Bool { try await eventStore.requestFullAccessToEvents() }
    func snapshot(settings: Settings) -> CalendarSnapshot {
        assert(!Thread.isMainThread, "Calendar reads must not block touch handling")
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--interaction-test") { return interactionSnapshot() }
        #endif
        let hasAccess = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        guard hasAccess else { return CalendarSnapshot(hasAccess: false, choices: [], events: []) }
        let calendars = eventStore.calendars(for: .event)
        let choices = calendars.map { c in CalendarChoice(id: c.calendarIdentifier, title: c.title, colorHex: Self.hex(c.cgColor), holiday: Self.isHoliday(c.title)) }
        let selected = calendars.filter { c in
            !settings.excludedCalendarIDs.contains(c.calendarIdentifier) && !settings.excludedCalendarTitles.contains(c.title) && !(settings.excludeHolidays && Self.isHoliday(c.title))
        }
        guard !selected.isEmpty else { return CalendarSnapshot(hasAccess: true, choices: choices, events: []) }
        let from = PivotDate.calendar.date(byAdding: .day, value: -7, to: PivotDate.calendar.startOfDay(for: Date()))!
        let to = PivotDate.calendar.date(byAdding: .month, value: 2, to: PivotDate.calendar.startOfDay(for: Date()))!
        let predicate = eventStore.predicateForEvents(withStart: from, end: to, calendars: selected)
        let events = eventStore.events(matching: predicate).map { event in
            let external = event.calendarItemExternalIdentifier
            let eventID = event.eventIdentifier ?? event.calendarItemIdentifier
            // Include the calendar to separate copies imported into distinct calendars.
            let recurring = event.hasRecurrenceRules
            let anchor = recurring ? event.occurrenceDate : nil
            let suffix = recurring ? "|\(Int((anchor ?? event.startDate).timeIntervalSince1970))" : ""
            let key = "\(event.calendar.calendarIdentifier)|\(external ?? eventID)\(suffix)"
            return CalendarItem(id: key, eventIdentifier: eventID, externalIdentifier: external,
                calendarIdentifier: event.calendar.calendarIdentifier, calendarTitle: event.calendar.title,
                title: event.title ?? "Evento", start: event.startDate, end: event.endDate,
                location: event.location ?? "", notes: CalendarNoteText.plain(event.notes ?? ""),
                colorHex: Self.hex(event.calendar.cgColor), isAllDay: event.isAllDay,
                writable: event.calendar.allowsContentModifications, kind: .classify(title: event.title ?? "", calendar: event.calendar.title),
                sourceIdentifier: event.calendar.source.sourceIdentifier, sourceTitle: event.calendar.source.title, calendarModifiedAt: event.lastModifiedDate, recurring: recurring, occurrenceAnchor: anchor)
        }.sorted { $0.start < $1.start }
        return CalendarSnapshot(hasAccess: true, choices: choices, events: events)
    }
    func apply(_ move: PlanMove) throws {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { throw CalendarFailure.noAccess }
        // Re-fetch before writing and reject moved, deleted, or read-only occurrences.
        let predicate = eventStore.predicateForEvents(withStart: move.source.start.addingTimeInterval(-1), end: move.source.end.addingTimeInterval(1), calendars: nil)
        let matching = eventStore.events(matching: predicate).first { event in
            let sameID = event.eventIdentifier == move.source.eventIdentifier || (move.source.externalIdentifier != nil && event.calendarItemExternalIdentifier == move.source.externalIdentifier)
            return sameID && abs(event.startDate.timeIntervalSince(move.source.start)) < 1 && abs(event.endDate.timeIntervalSince(move.source.end)) < 1
                && event.title == move.source.title && event.calendar.calendarIdentifier == move.source.calendarIdentifier
        }
        guard let event = matching, event.calendar.allowsContentModifications else { throw CalendarFailure.changed }
        event.startDate = move.proposedStart
        event.endDate = move.proposedEnd
        try eventStore.save(event, span: .thisEvent, commit: true)
    }
    #if DEBUG && targetEnvironment(simulator)
    private func interactionSnapshot() -> CalendarSnapshot {
        // Exercise the production refresh path with a slow import, not PreviewMode.
        Thread.sleep(forTimeInterval: 4)
        let day = PivotDate.calendar.startOfDay(for: Date())
        let html = "<p>Programma d&#x27;oggi</p><p>Prima parte<br>Seconda parte</p><img src='https://invalid.example/image.png'>"
        let events = (0..<700).map { i -> CalendarItem in
            let start = day.addingTimeInterval(Double(i / 10) * 86400 + Double(8 + i % 10) * 3600)
            let key = "touch-test-\(i)"
            return CalendarItem(id: key, eventIdentifier: key, calendarIdentifier: "interaction", calendarTitle: "Test", title: "Studio \(i)", start: start, end: start.addingTimeInterval(1800), location: "", notes: CalendarNoteText.plain(html), colorHex: "#7EE6CD", isAllDay: false, writable: false, kind: .study)
        }
        return CalendarSnapshot(hasAccess: true, choices: [.init(id: "interaction", title: "Test", colorHex: "#7EE6CD", holiday: false)], events: events)
    }
    #endif
    static func isHoliday(_ title: String) -> Bool {
        let t = title.lowercased()
        return ["festivit", "holiday", "giorni festivi"].contains(where: t.contains)
    }
    static func hex(_ color: CGColor) -> String {
        let exact = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil) ?? color
        let ui = UIColor(cgColor: exact)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}
enum CalendarFailure: LocalizedError {
    case noAccess, changed
    var errorDescription: String? {
        switch self {
        case .noAccess: return "Consenti l'accesso completo ai calendari nelle impostazioni di iOS."
        case .changed: return "L'evento è cambiato, non esiste più o non è modificabile. Aggiorna il calendario e prepara una nuova proposta."
        }
    }
}

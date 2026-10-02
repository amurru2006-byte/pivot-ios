import EventKit
import SwiftUI
import UIKit

struct CalendarChoice: Identifiable {
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
    @Published var error: String?
    @Published private(set) var lastRefresh: Date?
    private let eventStore = EKEventStore()

    func requestAccess() async {
        do { hasAccess = try await eventStore.requestFullAccessToEvents() }
        catch { self.error = error.localizedDescription }
    }
    #if DEBUG && targetEnvironment(simulator)
    func loadPreview(_ items: [CalendarItem]) {
        events = items; hasAccess = true
        choices = [.init(id: "preview", title: "Esempio", colorHex: "7EE6CD", holiday: false)]
    }
    #endif
    func refresh(settings: Settings) {
        if PreviewMode.enabled { return }
        hasAccess = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        guard hasAccess else { events = []; choices = []; return }
        eventStore.refreshSourcesIfNecessary()
        let calendars = eventStore.calendars(for: .event)
        choices = calendars.map { c in .init(id: c.calendarIdentifier, title: c.title, colorHex: Self.hex(c.cgColor), holiday: Self.isHoliday(c.title)) }
        let selected = calendars.filter { c in
            !settings.excludedCalendarIDs.contains(c.calendarIdentifier) && !settings.excludedCalendarTitles.contains(c.title) && !(settings.excludeHolidays && Self.isHoliday(c.title))
        }
        guard !selected.isEmpty else { events = []; return }
        let from = PivotDate.calendar.date(byAdding: .day, value: -7, to: PivotDate.calendar.startOfDay(for: Date()))!
        let to = PivotDate.calendar.date(byAdding: .month, value: 2, to: PivotDate.calendar.startOfDay(for: Date()))!
        let predicate = eventStore.predicateForEvents(withStart: from, end: to, calendars: selected)
        events = eventStore.events(matching: predicate).map { event in
            let external = event.calendarItemExternalIdentifier
            let eventID = event.eventIdentifier ?? event.calendarItemIdentifier
            // Include the calendar to separate copies imported into distinct calendars.
            let key = "\(event.calendar.calendarIdentifier)|\(external ?? eventID)|\(PivotDate.key(event.startDate))"
            return CalendarItem(id: key, eventIdentifier: eventID, externalIdentifier: external,
                calendarIdentifier: event.calendar.calendarIdentifier, calendarTitle: event.calendar.title,
                title: event.title ?? "Evento", start: event.startDate, end: event.endDate,
                location: event.location ?? "", notes: Self.plainText(event.notes ?? ""),
                colorHex: Self.hex(event.calendar.cgColor), isAllDay: event.isAllDay,
                writable: event.calendar.allowsContentModifications, kind: .classify(title: event.title ?? "", calendar: event.calendar.title),
                sourceIdentifier: event.calendar.source.sourceIdentifier, sourceTitle: event.calendar.source.title, calendarModifiedAt: event.lastModifiedDate)
        }.sorted { $0.start < $1.start }
        lastRefresh = Date()
    }
    func apply(_ move: PlanMove) throws {
        guard hasAccess else { throw CalendarFailure.noAccess }
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
    static func isHoliday(_ title: String) -> Bool {
        let t = title.lowercased()
        return ["festivit", "holiday", "giorni festivi"].contains(where: t.contains)
    }
    static func plainText(_ value: String) -> String {
        guard value.contains("<") || value.contains("&#") else { return value }
        guard let bytes = value.data(using: .utf8), let text = try? NSAttributedString(data: bytes, options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil) else { return value }
        return text.string
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

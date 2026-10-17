import EventKit
import SwiftUI
import UIKit

struct CalendarChoice: Identifiable, Equatable {
    var id: String
    var title: String
    var colorHex: String
    var holiday: Bool
    var writable: Bool = false
    var sourceTitle: String = ""
    var sourceIdentifier: String = ""
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
    private var invalidation: UInt64 = 0
    private var snapshotRevision: UInt64 = 0

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
    func invalidateSnapshot() { invalidation &+= 1 }
    func refresh(settings: Settings, force: Bool = true) async {
        guard !PreviewMode.enabled else { return }
        let filter = CalendarFilter(settings)
        if !force, inFlight == nil, lastFilter == filter, snapshotRevision == invalidation,
           let lastRefresh, Date().timeIntervalSince(lastRefresh) < 15 { return }
        while let active = inFlight {
            _ = await active.value
            // Another waiter can resume before the publisher; yield so it can finish.
            await Task.yield()
            if inFlight == nil && lastFilter == filter && snapshotRevision == invalidation { return }
        }
        isRefreshing = true
        let revision = invalidation
        let task = Task { await worker.snapshot(settings: settings) }
        inFlight = task
        let snapshot = await task.value
        hasAccess = snapshot.hasAccess
        if choices != snapshot.choices { choices = snapshot.choices }
        if events != snapshot.events { events = snapshot.events }
        lastFilter = filter
        snapshotRevision = revision
        lastRefresh = Date()
        inFlight = nil
        isRefreshing = false
    }
    func apply(_ move: PlanMove, data: AppData) async throws { try await worker.apply(move, data: data) }
    func reviewCreation(_ draft: CoachCalendarDraft, calendarID: String, settings: Settings) async throws -> [CalendarItem] {
        try await worker.reviewCreation(draft, calendarID: calendarID, settings: settings)
    }
    func create(_ draft: CoachCalendarDraft, calendarID: String, expectedConflicts: [CalendarItem], settings: Settings) async throws -> (item: CalendarItem, existing: Bool) {
        let result = try await worker.create(draft, calendarID: calendarID, expectedConflicts: expectedConflicts, settings: settings)
        invalidateSnapshot(); await refresh(settings: settings, force: true)
        return result
    }
    // An explicit history query must not replace or enlarge the home agenda window.
    func incomeHistory(year: Int, calendarIDs: Set<String>, settings: Settings) async throws -> [CalendarItem] {
        let items = try await worker.incomeHistory(year: year, calendarIDs: calendarIDs, settings: settings)
        try Task.checkCancellation()
        return items
    }
    func applyActualWorkout(_ draft: ActualWorkoutDraft, data: AppData) async throws { try await worker.applyActualWorkout(draft, data: data) }
    func applyActualTimes(for record: EventRecord, event: CalendarItem, data: AppData) async throws -> CalendarItem? {
        guard let timing = CalendarSynchronization.actualTiming(for: record, event: event),
              CalendarSynchronization.needsCalendarUpdate(timing, event: event) else { return nil }
        let updated = try await worker.applyActualTimes(timing, source: event)
        invalidateSnapshot()
        await refresh(settings: data.settings, force: true)
        return updated
    }
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
    private lazy var eventStore = EKEventStore()
    #if DEBUG && targetEnvironment(simulator)
    private var creationFixture: Bool { ProcessInfo.processInfo.arguments.contains("--coach-calendar-create-test") }
    private var createdFixtureItems: [CalendarItem] = []
    #endif
    func reviewCreation(_ draft: CoachCalendarDraft, calendarID: String, settings: Settings) throws -> [CalendarItem] {
        #if DEBUG && targetEnvironment(simulator)
        if creationFixture {
            guard calendarID == "create-fixture", draft.problem(now: Date(), calendarID: calendarID) == nil else { throw CalendarFailure.notWritable }
            return createdFixtureItems.filter { $0.start < draft.end! && $0.end > draft.start! }.sorted { $0.id < $1.id }
        }
        #endif
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { throw CalendarFailure.noAccess }
        guard draft.problem(now: Date(), calendarID: calendarID) == nil,
              let calendar = eventStore.calendar(withIdentifier: calendarID), calendar.allowsContentModifications,
              let start = draft.start, let end = draft.end else { throw CalendarFailure.notWritable }
        let calendars = eventStore.calendars(for: .event).filter {
            !settings.excludedCalendarIDs.contains($0.calendarIdentifier) && !settings.excludedCalendarTitles.contains($0.title)
                && !(settings.excludeHolidays && Self.isHoliday($0.title))
        }
        guard !calendars.isEmpty else { return [] }
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return eventStore.events(matching: predicate).filter { $0.startDate < end && $0.endDate > start }
            .map(Self.item).sorted { $0.id < $1.id }
    }
    func create(_ draft: CoachCalendarDraft, calendarID: String, expectedConflicts: [CalendarItem], settings: Settings) throws -> (item: CalendarItem, existing: Bool) {
        let fresh = try reviewCreation(draft, calendarID: calendarID, settings: settings)
        #if DEBUG && targetEnvironment(simulator)
        if creationFixture {
            if let existing = createdFixtureItems.first(where: { $0.title == draft.title && $0.start == draft.start && $0.end == draft.end }) {
                try draft.checkExistingNotes(existing.notes); return (existing, true)
            }
            guard fresh == expectedConflicts else { throw CalendarFailure.changed }
            let item = CalendarItem(id: draft.id.uuidString, eventIdentifier: draft.id.uuidString, calendarIdentifier: calendarID,
                                    calendarTitle: "Personale test", title: draft.title, start: draft.start!, end: draft.end!,
                                    location: "", notes: draft.notes, colorHex: "7EE6CD", isAllDay: false, writable: true, kind: .other)
            createdFixtureItems.append(item); return (item, false)
        }
        #endif
        guard let target = eventStore.calendar(withIdentifier: calendarID), target.allowsContentModifications,
              let start = draft.start, let end = draft.end else { throw CalendarFailure.notWritable }
        let marker = URL(string: "pivot://created/" + draft.id.uuidString)!
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: [target])
        // A retry after save succeeded must not create another copy, even if the
        // previous UI acknowledgement or local conversation write failed.
        if let existing = eventStore.events(matching: predicate).first(where: {
            $0.url == marker || ($0.startDate == start && $0.endDate == end &&
                EventCoalescer.normalized($0.title ?? "") == EventCoalescer.normalized(draft.title))
        }) {
            let item = Self.item(existing)
            try draft.checkExistingNotes(item.notes)
            return (item, true)
        }
        guard fresh == expectedConflicts else { throw CalendarFailure.changed }
        try Task.checkCancellation()
        let event = EKEvent(eventStore: eventStore)
        event.calendar = target; event.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        event.startDate = start; event.endDate = end; event.timeZone = PivotDate.calendar.timeZone
        event.notes = draft.notes; event.url = marker
        try eventStore.save(event, span: .thisEvent, commit: true)
        return (Self.item(event), false)
    }
    func requestAccess() async throws -> Bool { try await eventStore.requestFullAccessToEvents() }
    func incomeHistory(year: Int, calendarIDs: Set<String>, settings: Settings) throws -> [CalendarItem] {
        assert(!Thread.isMainThread, "Calendar history must not block touch handling")
        let now = Date()
        guard (2026...PivotDate.calendar.component(.year, from: now)).contains(year), !calendarIDs.isEmpty,
              let start = PivotDate.calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let yearEnd = PivotDate.calendar.date(byAdding: .year, value: 1, to: start) else { throw CalendarFailure.changed }
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--interaction-test"), ProcessInfo.processInfo.arguments.contains("--history-test") {
            return (0..<2).map { index in
                let date = start.addingTimeInterval(Double(3 + index) * 86400 + 10 * 3600)
                let id = "history-fixture-\(index)"
                return CalendarItem(id: id, eventIdentifier: id, calendarIdentifier: "history-fixture", calendarTitle: "Lavoro",
                    title: "Lezione Contatto \(index == 0 ? "A" : "B") Test", start: date, end: date.addingTimeInterval(3600),
                    location: "", notes: "", colorHex: "7EE6CD", isAllDay: false, writable: false, kind: .tutoring)
            }.filter { calendarIDs.contains($0.calendarIdentifier) }
        }
        #endif
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { throw CalendarFailure.noAccess }
        let selected = eventStore.calendars(for: .event).filter { calendar in
            calendarIDs.contains(calendar.calendarIdentifier) && !settings.excludedCalendarIDs.contains(calendar.calendarIdentifier)
                && !settings.excludedCalendarTitles.contains(calendar.title) && !(settings.excludeHolidays && Self.isHoliday(calendar.title))
        }
        guard !selected.isEmpty else { throw CalendarFailure.changed }
        let predicate = eventStore.predicateForEvents(withStart: start, end: min(now, yearEnd), calendars: selected)
        return eventStore.events(matching: predicate).map(Self.item).filter { HistoricalIncome.isEligible($0, year: year, now: now) }
            .sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }
    func snapshot(settings: Settings) -> CalendarSnapshot {
        assert(!Thread.isMainThread, "Calendar reads must not block touch handling")
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--interaction-test") { return interactionSnapshot() }
        #endif
        let hasAccess = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        guard hasAccess else { return CalendarSnapshot(hasAccess: false, choices: [], events: []) }
        let calendars = eventStore.calendars(for: .event)
        let choices = calendars.map { c in CalendarChoice(id: c.calendarIdentifier, title: c.title, colorHex: Self.hex(c.cgColor), holiday: Self.isHoliday(c.title), writable: c.allowsContentModifications, sourceTitle: c.source.title, sourceIdentifier: c.source.sourceIdentifier) }
        let selected = calendars.filter { c in
            !settings.excludedCalendarIDs.contains(c.calendarIdentifier) && !settings.excludedCalendarTitles.contains(c.title) && !(settings.excludeHolidays && Self.isHoliday(c.title))
        }
        guard !selected.isEmpty else { return CalendarSnapshot(hasAccess: true, choices: choices, events: []) }
        let from = PivotDate.calendar.date(byAdding: .day, value: -7, to: PivotDate.calendar.startOfDay(for: Date()))!
        let to = PivotDate.calendar.date(byAdding: .month, value: 2, to: PivotDate.calendar.startOfDay(for: Date()))!
        let predicate = eventStore.predicateForEvents(withStart: from, end: to, calendars: selected)
        let events = eventStore.events(matching: predicate).map(Self.item).sorted { $0.start < $1.start }
        return CalendarSnapshot(hasAccess: true, choices: choices, events: events)
    }
    func applyActualTimes(_ timing: CalendarSynchronization.ActualTiming, source: CalendarItem) throws -> CalendarItem {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { throw CalendarFailure.noAccess }
        guard source.writable, !source.isAllDay, timing.end > timing.start else { throw CalendarFailure.notWritable }
        let padding: TimeInterval = 36 * 3600
        let predicate = eventStore.predicateForEvents(withStart: source.start.addingTimeInterval(-padding), end: source.end.addingTimeInterval(padding), calendars: nil)
        let matching = eventStore.events(matching: predicate).first { event in
            let sameID = event.eventIdentifier == source.eventIdentifier
                || (source.externalIdentifier != nil && event.calendarItemExternalIdentifier == source.externalIdentifier)
            let sameOccurrence = source.recurring != true
                || (source.occurrenceAnchor != nil && event.occurrenceDate == source.occurrenceAnchor)
                || (abs(event.startDate.timeIntervalSince(source.start)) < 1 && abs(event.endDate.timeIntervalSince(source.end)) < 1)
            return sameID && sameOccurrence && event.calendar.calendarIdentifier == source.calendarIdentifier
        }
        guard let event = matching, event.calendar.allowsContentModifications else { throw CalendarFailure.changed }
        // The view is a snapshot. Refuse the write if another app changed this
        // occurrence after Pivot displayed it.
        guard event.title == source.title,
              abs(event.startDate.timeIntervalSince(source.start)) < 1,
              abs(event.endDate.timeIntervalSince(source.end)) < 1,
              CoachPlanner.modificationDateMatches(source.calendarModifiedAt, event.lastModifiedDate),
              (event.location ?? "") == source.location,
              CalendarNoteText.plain(event.notes ?? "") == source.notes,
              event.isAllDay == source.isAllDay else { throw CalendarFailure.changed }
        event.startDate = timing.start
        event.endDate = timing.end
        try eventStore.save(event, span: .thisEvent, commit: true)
        return Self.item(event)
    }
    func applyActualWorkout(_ draft: ActualWorkoutDraft, data: AppData) throws {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { throw CalendarFailure.noAccess }
        let fresh = snapshot(settings: data.settings)
        let current = EventCoalescer.unique(fresh.events, data: data)
        if let problem = WorkoutContext.validate(draft, events: current, now: Date()) {
            throw NSError(domain: "PivotCalendar", code: 2, userInfo: [NSLocalizedDescriptionKey: problem])
        }
        let moves = WorkoutContext.moves(draft, events: current)
        // Preflight every occurrence, then commit the complete, explicitly confirmed batch.
        var updates: [(EKEvent, PlanMove)] = []
        for move in moves {
            let predicate = eventStore.predicateForEvents(withStart: move.source.start.addingTimeInterval(-1), end: move.source.end.addingTimeInterval(1), calendars: nil)
            guard let event = eventStore.events(matching: predicate).first(where: {
                $0.eventIdentifier == move.source.eventIdentifier && $0.calendar.calendarIdentifier == move.source.calendarIdentifier &&
                abs($0.startDate.timeIntervalSince(move.source.start)) < 1 && abs($0.endDate.timeIntervalSince(move.source.end)) < 1
            }), event.calendar.allowsContentModifications,
               CoachPlanner.modificationDateMatches(move.source.calendarModifiedAt, event.lastModifiedDate) else { throw CalendarFailure.changed }
            updates.append((event, move))
        }
        do {
            for (event, move) in updates { event.startDate = move.proposedStart; event.endDate = move.proposedEnd; try eventStore.save(event, span: .thisEvent, commit: false) }
            try eventStore.commit()
        } catch { eventStore.reset(); throw error }
    }
    func apply(_ move: PlanMove, data: AppData) throws {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { throw CalendarFailure.noAccess }
        // Validate on a new snapshot inside the same worker job that performs the write.
        let fresh = snapshot(settings: data.settings)
        let option = CoachOption(title: "Conferma Calendario", explanation: "", consequences: "", moves: [move])
        if let problem = CoachPlanner.validate(option, events: fresh.events, data: data, now: Date()) {
            throw NSError(domain: "PivotCalendar", code: 1, userInfo: [NSLocalizedDescriptionKey: problem])
        }
        // Re-fetch before writing and reject moved, deleted, or read-only occurrences.
        let predicate = eventStore.predicateForEvents(withStart: move.source.start.addingTimeInterval(-1), end: move.source.end.addingTimeInterval(1), calendars: nil)
        let matching = eventStore.events(matching: predicate).first { event in
            let sameID = event.eventIdentifier == move.source.eventIdentifier || (move.source.externalIdentifier != nil && event.calendarItemExternalIdentifier == move.source.externalIdentifier)
            return sameID && abs(event.startDate.timeIntervalSince(move.source.start)) < 1 && abs(event.endDate.timeIntervalSince(move.source.end)) < 1
                && event.title == move.source.title && event.calendar.calendarIdentifier == move.source.calendarIdentifier
        }
        guard let event = matching, event.calendar.allowsContentModifications else { throw CalendarFailure.changed }
        guard CoachPlanner.modificationDateMatches(move.source.calendarModifiedAt, event.lastModifiedDate),
              (event.location ?? "") == move.source.location,
              CalendarNoteText.plain(event.notes ?? "") == move.source.notes,
              event.isAllDay == move.source.isAllDay else { throw CalendarFailure.changed }
        guard move.proposedEnd > move.proposedStart else { throw CalendarFailure.changed }
        event.startDate = move.proposedStart
        event.endDate = move.proposedEnd
        try eventStore.save(event, span: .thisEvent, commit: true)
    }
    #if DEBUG && targetEnvironment(simulator)
    private func interactionSnapshot() -> CalendarSnapshot {
        if creationFixture {
            return .init(hasAccess: true, choices: [.init(id: "create-fixture", title: "Personale test", colorHex: "7EE6CD", holiday: false, writable: true, sourceTitle: "Account test", sourceIdentifier: "source-fixture")], events: createdFixtureItems)
        }
        if ProcessInfo.processInfo.arguments.contains("--history-test") {
            return CalendarSnapshot(hasAccess: true, choices: [.init(id: "history-fixture", title: "Lavoro", colorHex: "7EE6CD", holiday: false)], events: [])
        }
        // Exercise the production refresh path with a slow import, not PreviewMode.
        Thread.sleep(forTimeInterval: 4)
        let day = PivotDate.calendar.startOfDay(for: Date())
        if ProcessInfo.processInfo.arguments.contains("--payment-schedule-test") {
            let monday = StudentPayments.week(containing: Date()).start
            let items = [0, 2, 4].map { offset -> CalendarItem in
                let start = PivotDate.calendar.date(byAdding: .day, value: offset, to: monday)!.addingTimeInterval(16 * 3600)
                let key = "payment-test-\(offset)"
                return CalendarItem(id: key, eventIdentifier: key, calendarIdentifier: "interaction", calendarTitle: "Lavoro", title: "Ripetizioni con Giulia Rossi", start: start, end: start.addingTimeInterval(3600), location: "", notes: "", colorHex: "#7EE6CD", isAllDay: false, writable: false, kind: .tutoring)
            }
            return CalendarSnapshot(hasAccess: true, choices: [.init(id: "interaction", title: "Lavoro", colorHex: "#7EE6CD", holiday: false)], events: items)
        }
        if ProcessInfo.processInfo.arguments.contains("--student-recognition-test") {
            let start = day.addingTimeInterval(10 * 3600)
            let event = CalendarItem(id: "student-test", eventIdentifier: "student-test", calendarIdentifier: "interaction", calendarTitle: "Lavoro", title: "Ripetizioni con Giulia Rossi", start: start, end: start.addingTimeInterval(3600), location: "", notes: "", colorHex: "#7EE6CD", isAllDay: false, writable: false, kind: .tutoring)
            return CalendarSnapshot(hasAccess: true, choices: [.init(id: "interaction", title: "Lavoro", colorHex: "#7EE6CD", holiday: false)], events: [event])
        }
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
    static func item(_ event: EKEvent) -> CalendarItem {
        let external = event.calendarItemExternalIdentifier
        let eventID = event.eventIdentifier ?? event.calendarItemIdentifier
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
            sourceIdentifier: event.calendar.source.sourceIdentifier, sourceTitle: event.calendar.source.title,
            calendarModifiedAt: event.lastModifiedDate, recurring: recurring, occurrenceAnchor: anchor,
            calendarRGB: Self.rgb(event.calendar.cgColor), calendarCreatedAt: event.creationDate)
    }
    static func hex(_ color: CGColor) -> String {
        let rgb = rgb(color)
        return String(format: "#%02X%02X%02X", Int((rgb.red * 255).rounded()), Int((rgb.green * 255).rounded()), Int((rgb.blue * 255).rounded()))
    }
    static func rgb(_ color: CGColor) -> CalendarRGB {
        let exact = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil) ?? color
        let ui = UIColor(cgColor: exact)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return CalendarRGB(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
    }
}
enum CalendarFailure: LocalizedError {
    case noAccess, changed, notWritable
    var errorDescription: String? {
        switch self {
        case .noAccess: return "Consenti l'accesso completo ai calendari nelle impostazioni di iOS."
        case .changed: return "L'evento è cambiato, non esiste più o non è modificabile. Aggiorna la giornata e riprova."
        case .notWritable: return "Questo evento non può essere modificato nel Calendario."
        }
    }
}

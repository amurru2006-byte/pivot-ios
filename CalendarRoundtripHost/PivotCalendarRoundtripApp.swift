#if !targetEnvironment(simulator)
#error("This synthetic host must never be built or installed on a physical device")
#endif
import SwiftUI
import EventKit

@main
struct PivotCalendarRoundtripApp: App {
    var body: some Scene { WindowGroup { RoundtripScreen() } }
}

private struct RoundtripScreen: View {
    @State private var busy = false
    @State private var attempt = 0
    @State private var status = "Idle: synthetic simulator host"
    private var authorizedRunner: Bool {
        ProcessInfo.processInfo.arguments.contains("--pivot-isolated-eventkit-ci")
            && UUID(uuidString: ProcessInfo.processInfo.environment["PIVOT_ROUNDTRIP_QA_ID"] ?? "") != nil
    }
    var body: some View {
        VStack(spacing: 24) {
            Text("Pivot Calendar QA").font(.title)
            Text("Only a new, owned calendar in the isolated CI simulator is used. No accounts or files are imported.")
            Button("Run synthetic roundtrip") {
                busy = true; attempt += 1; let number = attempt
                status = "Running \(number)"
                Task { @MainActor in
                    defer { busy = false }
                    do {
                        try await CalendarRoundtrip.run()
                        status = "PASS \(number): spring23 autumn25 timed45 cleanupOK"
                    } catch { status = "FAIL \(number): \(error.localizedDescription)" }
                }
            }.disabled(busy || !authorizedRunner).accessibilityIdentifier("calendar-native-run")
            Text(status).accessibilityIdentifier("calendar-native-result")
        }.padding()
    }
}

private enum CalendarRoundtrip {
    struct Failure: LocalizedError {
        let reason: String
        var errorDescription: String? { reason }
    }
    private static func require(_ condition: Bool, _ reason: String) throws {
        guard condition else { throw Failure(reason: reason) }
    }
    @MainActor static func run() async throws {
        guard ProcessInfo.processInfo.arguments.contains("--pivot-isolated-eventkit-ci"),
              let namespace = UUID(uuidString: ProcessInfo.processInfo.environment["PIVOT_ROUNDTRIP_QA_ID"] ?? "") else {
            throw Failure(reason: "Isolated runner guard missing")
        }
        let store = EKEventStore()
        guard try await store.requestFullAccessToEvents(), EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            throw Failure(reason: "Full access was not granted through the synthetic host prompt")
        }
        guard let local = store.sources.first(where: { $0.sourceType == .local }) else {
            throw Failure(reason: "No local calendar source exists in this isolated simulator")
        }
        let title = "Pivot-CI-" + namespace.uuidString + "-" + UUID().uuidString
        let owned = EKCalendar(for: .event, eventStore: store)
        owned.title = title; owned.source = local
        try store.saveCalendar(owned, commit: true)
        let calendarID = owned.calendarIdentifier
        func cleanup() throws {
            guard let current = store.calendar(withIdentifier: calendarID), current.title == title,
                  current.source?.sourceType == .local else { throw Failure(reason: "Owned-calendar identity could not be verified for cleanup") }
            try store.removeCalendar(current, commit: true)
            store.reset()
            try require(store.calendar(withIdentifier: calendarID) == nil, "Owned calendar still exists after committed removal")
        }
        do {
            let zone = TimeZone.current
            for (day, hours) in [("2026-03-29", 23), ("2026-10-25", 25)] {
                let allDay = CalendarCreationAllDay(day: day, nativeTimeZoneIdentifier: zone.identifier)
                guard let canonical = allDay.canonicalInterval else { throw Failure(reason: "Invalid synthetic civil day") }
                var options = CalendarCreationOptions(); options.allDay = allDay
                let draft = CoachCalendarDraft(title: "Owned all-day " + day, start: canonical.start, end: canonical.end,
                    calendarHint: nil, notes: "Synthetic source only", endEstimated: false)
                guard let part = options.parts(draft: draft, creationID: UUID()).first else { throw Failure(reason: "No synthetic all-day part") }
                let id = try save(part, options: options, calendar: owned, store: store, zone: zone)
                try read(id: id, part: part, options: options, calendarID: calendarID, zone: zone, expectedHours: hours)
            }
            let start = Date(timeIntervalSince1970: 1_900_000_000), end = start.addingTimeInterval(45 * 60)
            let options = CalendarCreationOptions()
            let draft = CoachCalendarDraft(title: "Owned timed QA", start: start, end: end,
                calendarHint: nil, notes: "Synthetic timed source", endEstimated: false)
            guard let part = options.parts(draft: draft, creationID: UUID()).first else { throw Failure(reason: "No synthetic timed part") }
            let id = try save(part, options: options, calendar: owned, store: store, zone: zone)
            try read(id: id, part: part, options: options, calendarID: calendarID, zone: zone, expectedHours: nil)
        } catch {
            do { try cleanup() }
            catch { throw Failure(reason: "Roundtrip failed and cleanup could not be verified") }
            throw error
        }
        try cleanup()
        withExtendedLifetime(store) {}
    }
    private static func save(_ part: CalendarCreationPart, options: CalendarCreationOptions,
                             calendar: EKCalendar, store: EKEventStore, zone: TimeZone) throws -> String {
        try require(TimeZone.current.identifier == zone.identifier, "Default zone changed before synthetic commit")
        let event = EKEvent(eventStore: store); event.calendar = calendar
        event.title = part.title; event.notes = part.notes; event.url = URL(string: part.marker)
        try CalendarCreationNative.assign(part, options: options, to: event, nativeTimeZone: zone)
        try store.save(event, span: .thisEvent, commit: true)
        if part.isAllDay {
            let external = EKEvent(eventStore: store); external.calendar = calendar
            external.title = "Unmarked external all-day QA"; external.isAllDay = true; external.timeZone = nil
            let floating = try CalendarCreationNative.query(parts: [part], options: options, nativeTimeZone: zone, readOnly: true)
            external.startDate = floating.start; external.endDate = floating.end.addingTimeInterval(-1)
            try store.save(external, span: .thisEvent, commit: true)
        }
        guard let id = event.eventIdentifier, !id.isEmpty else { throw Failure(reason: "Committed event has no identifier") }
        return id
    }
    private static func read(id: String, part: CalendarCreationPart, options: CalendarCreationOptions,
                             calendarID: String, zone: TimeZone, expectedHours: Int?) throws {
        let reader = EKEventStore()
        defer { withExtendedLifetime(reader) {} }
        guard let event = reader.event(withIdentifier: id), let calendar = reader.calendar(withIdentifier: calendarID),
              let eventCalendar = event.calendar else {
            throw Failure(reason: "Fresh EventStore cannot reload the committed owned event")
        }
        try require(TimeZone.current.identifier == zone.identifier, "Default zone changed during synthetic reread")
        try require(eventCalendar.calendarIdentifier == calendarID && event.url?.absoluteString == part.marker,
                    "Calendar identity or creation marker changed after save")
        try require(event.isAllDay == part.isAllDay, "All-day flag changed after save")
        try require(event.title == part.title && (event.notes ?? "") == part.notes, "Saved title or notes changed")
        let normalized = try CalendarCreationNative.interval(event, nativeTimeZone: zone, normalizeFloating: part.isAllDay)
        try require(normalized.start == part.start && normalized.end == part.end, "Committed native dates do not match canonical dates")
        if let expectedHours {
            try require(normalized.duration == Double(expectedHours * 3600), "Civil DST duration was not preserved")
        } else { try require(normalized.duration == 45 * 60, "Timed absolute duration changed") }
        let query = try CalendarCreationNative.query(parts: [part], options: options, nativeTimeZone: zone, readOnly: true)
        let predicate = reader.predicateForEvents(withStart: query.start, end: query.end, calendars: [calendar])
        let queried = reader.events(matching: predicate)
        let matches = queried.filter { $0.url?.absoluteString == part.marker }
        try require(matches.count == 1 && matches[0].eventIdentifier == id, "Native query cannot uniquely reconcile the owned marker")
        if part.isAllDay {
            let external = queried.filter { $0.url == nil && $0.title == "Unmarked external all-day QA" }
            try require(external.count == 1, "Native query lost the unmarked external all-day conflict")
            let conflict = try CalendarCreationNative.interval(external[0], nativeTimeZone: zone, normalizeFloating: true)
            try require(conflict.intersects(normalized), "External floating all-day conflict no longer overlaps the civil proposal")
        }
    }
}

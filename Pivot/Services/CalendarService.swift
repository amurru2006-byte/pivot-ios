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
    @Published private(set) var mutationInProgress = false
    @Published private(set) var contactActivity: ClientCalendarActivity?
    @Published private(set) var contactActivityProblem: String?
    @Published private(set) var checkingContactActivity = false
    private var nextContactAppointments: [UUID: CalendarItem] = [:]
    private var contactFilter: CalendarFilter?
    private var contactRevision: UInt64 = 0
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
    func toggleExternalMutationFixture() async {
        guard await worker.toggleExternalMutationFixture() else { return }
        invalidateSnapshot(); await refresh(settings: Settings())
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
    func apply(_ move: PlanMove, data: AppData) async throws {
        guard !CalendarActivityLinks.requiresPairedReview(move.source, data: data) else { throw CalendarActivityLinks.Failure.selection }
        try await worker.apply(move, data: data)
    }
    func reviewCreation(_ draft: CoachCalendarDraft, calendarID: String, settings: Settings,
                        options: CalendarCreationOptions = .init(), creationID: UUID? = nil) async throws -> [CalendarItem] {
        try await worker.reviewCreation(draft, calendarID: calendarID, settings: settings, options: options,
            creationID: creationID ?? draft.id, mapsConsent: AppleMapsService.shared.consentGranted)
    }
    func create(_ draft: CoachCalendarDraft, calendarID: String, expectedConflicts: [CalendarItem], settings: Settings,
                options: CalendarCreationOptions = .init(), creationID: UUID? = nil, verifyOnly: Bool = false) async throws -> (receipt: CalendarCreationReceipt, existing: Bool) {
        guard !mutationInProgress else { throw CalendarFailure.changed }
        mutationInProgress = true; defer { mutationInProgress = false }
        let result = try await worker.create(draft, calendarID: calendarID, expectedConflicts: expectedConflicts, settings: settings,
            options: options, creationID: creationID ?? draft.id, mapsConsent: AppleMapsService.shared.consentGranted, verifyOnly: verifyOnly)
        invalidateSnapshot(); await refresh(settings: settings, force: true)
        return result
    }
    // An explicit history query must not replace or enlarge the home agenda window.
    func incomeHistory(year: Int, calendarIDs: Set<String>, settings: Settings) async throws -> [CalendarItem] {
        let items = try await worker.incomeHistory(year: year, calendarIDs: calendarIDs, settings: settings)
        try Task.checkCancellation()
        return items
    }
    /// Contact visibility has its own bounded history/future scan. Never extend
    /// the home agenda, start cloud requests or write Calendar events for this.
    @discardableResult func refreshContactActivity(store: PivotStore, force: Bool = false) async -> Bool {
        guard !store.isLoading, !store.isRestoring, !store.locked, !checkingContactActivity else { return false }
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--interaction-test"),
           !ProcessInfo.processInfo.arguments.contains("--contact-activity-test") { return false }
        #endif
        let filter = CalendarFilter(store.data.settings)
        let checkedRevision = invalidation
        let cached = !force && contactFilter == filter && contactRevision == invalidation
            && contactActivity.map { Date().timeIntervalSince($0.observedAt) < 300 } == true
        checkingContactActivity = true
        defer { checkingContactActivity = false }
        do {
            let scan: ClientCalendarActivity
            if cached, let contactActivity { scan = contactActivity }
            else { scan = try await worker.contactActivity(settings: store.data.settings) }
            try Task.checkCancellation()
            guard !store.isRestoring, !store.locked, checkedRevision == invalidation,
                  filter == CalendarFilter(store.data.settings) else { return false }
            let data = store.data, version = data.updatedAt
            let now = Date()
            let result = await Task.detached(priority: .utility) {
                (ClientActivity.refreshed(data: data, scan: scan, now: now),
                 ClientActivity.nextAppointments(data: data, scan: scan, now: now))
            }.value
            guard !store.isRestoring, !store.locked, checkedRevision == invalidation,
                  version == store.data.updatedAt else { return false }
            contactActivity = scan; contactFilter = filter; contactRevision = checkedRevision
            nextContactAppointments = result.1
            contactActivityProblem = scan.complete ? nil : "Lettura del calendario incompleta: nessuna disattivazione automatica."
            if result.0 != store.data.clients { guard store.change({ $0.clients = result.0 }) else { return false } }
            return scan.complete
        } catch is CancellationError {
            // Navigating away can cancel the list's refresh while a contact's
            // explicit verification is waiting. Cancellation is not revocation
            // or evidence that previously observed appointments disappeared.
            // Retain the bounded last observation for the explanatory warning;
            // false still forbids deactivation without a completed fresh scan.
            return false
        } catch {
            contactActivity = nil
            nextContactAppointments = [:]
            contactActivityProblem = "Non riesco a verificare gli appuntamenti futuri. Il contatto resta invariato."
            return false
        }
    }
    func nextContactAppointment(_ clientID: UUID) -> CalendarItem? {
        guard contactActivity?.isCurrent(at: Date()) == true,
              let item = nextContactAppointments[clientID], item.end > Date() else { return nil }
        return item
    }
    func reviewMutations(batchID: UUID, actions: [CoachCalendarMutation], settings: Settings) async throws -> CalendarMutationReview {
        try await worker.reviewMutations(batchID: batchID, actions: actions, settings: settings)
    }
    /// The durable original precedes the EventKit write. An interrupted/failed
    /// acknowledgement stays review-required and must never cause a blind retry.
    func commitMutations(_ review: CalendarMutationReview, store: PivotStore) async throws {
        guard !mutationInProgress, !store.locked, !store.isRestoring,
              let batchID = review.entries.first?.batchID,
              let batch = store.data.coachState.calendarBatches?.first(where: { $0.id == batchID }), batch.status == .pending,
              review.entries.allSatisfy({ entry in batch.actions.contains { $0.id == entry.actionID && CalendarSnapshotMatch.revision($0.source, entry.original.snapshot) && $0.kind == entry.kind && $0.after == entry.after }
                  && store.data.records[entry.original.snapshot.id]?.status != .running
                  && !store.data.moves.contains(where: { !$0.syncedToCalendar && $0.source.id == entry.original.snapshot.id }) }),
              !(store.data.calendarActionArchive ?? []).contains(where: { $0.batchID == batchID }),
              store.beginCalendarMutation() else { throw CalendarFailure.changed }
        mutationInProgress = true; defer { mutationInProgress = false; store.endCalendarMutation() }
        let proposed = review.entries.map { CoachCalendarMutation(id: $0.actionID, kind: $0.kind, source: $0.original.snapshot, after: $0.after) }
        let linked = try CalendarActivityLinks.expanded(proposed, data: store.data, choices: batch.linkedTravelChoices ?? [:],
            now: Date(), mapsConsent: AppleMapsService.shared.consentGranted)
        guard linked == proposed else { throw CalendarActivityLinks.Failure.selection }
        let archivedReview = CalendarMutationReview(entries: CalendarActivityLinks.archiving(review.entries, data: store.data,
            choices: batch.linkedTravelChoices ?? [:]), conflicts: review.conflicts)
        guard store.change({ data in
            var archive = data.calendarActionArchive ?? []; archive.append(contentsOf: archivedReview.entries); data.calendarActionArchive = archive
            if let index = data.coachState.calendarBatches?.firstIndex(where: { $0.id == batchID }) { data.coachState.calendarBatches?[index].status = .reviewRequired }
        }), await store.flushPendingWrites() else { throw CalendarFailure.archiveNotSaved }
        do {
            try Task.checkCancellation()
            guard !store.locked, !store.isRestoring else { throw CalendarFailure.archiveNotSaved }
            let completed = try await worker.commitMutations(archivedReview, settings: store.data.settings)
            var acknowledged = store.data
            try CalendarActivityLinks.record(completed, choices: batch.linkedTravelChoices ?? [:], data: &acknowledged)
            guard store.change({ data in
                data.calendarActivityLinks = acknowledged.calendarActivityLinks
                for item in completed {
                    if let index = data.calendarActionArchive?.firstIndex(where: { $0.id == item.id }) { data.calendarActionArchive?[index] = item }
                }
                if let index = data.coachState.calendarBatches?.firstIndex(where: { $0.id == batchID }) { data.coachState.calendarBatches?[index].status = .applied }
            }), await store.flushPendingWrites() else { throw CalendarFailure.acknowledgementNotSaved }
            invalidateSnapshot(); await refresh(settings: store.data.settings)
        } catch {
            store.change { data in
                for entry in review.entries {
                    if let index = data.calendarActionArchive?.firstIndex(where: { $0.id == entry.id }), data.calendarActionArchive?[index].status == .prepared {
                        data.calendarActionArchive?[index].status = .uncertain
                    }
                }
            }
            _ = await store.flushPendingWrites()
            throw error
        }
    }
    func restoreMutation(_ id: UUID, store: PivotStore) async throws -> String {
        guard !mutationInProgress, !store.locked, !store.isRestoring,
              var entry = store.data.calendarActionArchive?.first(where: { $0.id == id }),
              [.committed, .restorationPrepared].contains(entry.status), store.beginCalendarMutation() else { throw CalendarFailure.changed }
        mutationInProgress = true; defer { mutationInProgress = false; store.endCalendarMutation() }
        let previousStatus = entry.status
        entry.status = .restorationPrepared
        guard store.change({ data in
            if let index = data.calendarActionArchive?.firstIndex(where: { $0.id == id }) { data.calendarActionArchive?[index] = entry }
        }), await store.flushPendingWrites() else { throw CalendarFailure.archiveNotSaved }
        let result: CalendarRestoreResult
        do {
            try Task.checkCancellation()
            guard !store.locked, !store.isRestoring else { throw CalendarFailure.archiveNotSaved }
            result = try await worker.restoreMutation(entry, settings: store.data.settings)
        } catch {
            let stoppedBeforeWrite = error is CancellationError || (error as? CalendarFailure)?.stoppedBeforeCalendarWrite == true
            if CalendarArchive.failedRestorationStatus(previous: previousStatus, stoppedBeforeWrite: stoppedBeforeWrite) == .committed {
                guard store.change({ data in
                    if let index = data.calendarActionArchive?.firstIndex(where: { $0.id == id && $0.status == .restorationPrepared }) {
                        data.calendarActionArchive?[index].status = .committed
                    }
                }), await store.flushPendingWrites() else { throw CalendarFailure.acknowledgementNotSaved }
            }
            throw error
        }
        entry.status = result.originalPresent ? .failed : .restored
        if !result.originalPresent { entry.restoredAt = Date(); entry.restoredEvent = result.item }
        guard store.change({ data in
            if let index = data.calendarActionArchive?.firstIndex(where: { $0.id == id }) { data.calendarActionArchive?[index] = entry }
            if entry.kind == .delete, !result.originalPresent {
                var links = data.calendarRestorations ?? []
                links.removeAll { $0.archiveID == id }
                links.append(.init(archiveID: id, original: entry.original.snapshot, restored: result.item)); data.calendarRestorations = links
            }
            CalendarActivityLinks.reconcileRestorations(data: &data)
        }), await store.flushPendingWrites() else { throw CalendarFailure.acknowledgementNotSaved }
        invalidateSnapshot(); await refresh(settings: store.data.settings)
        return result.originalPresent ? "L’originale era già presente: nessuna copia aggiunta." : "Modifica annullata. Incassi e registrazioni in Pivot sono rimasti invariati."
    }
    func reconcileMutation(_ id: UUID, store: PivotStore) async throws -> String {
        guard !mutationInProgress, !store.locked, !store.isRestoring,
              var entry = store.data.calendarActionArchive?.first(where: { $0.id == id }), [.prepared, .uncertain].contains(entry.status),
              store.beginCalendarMutation() else { throw CalendarFailure.changed }
        mutationInProgress = true; defer { mutationInProgress = false; store.endCalendarMutation() }
        let applied = try await worker.reconcileMutation(entry)
        if let after = applied.after { entry.after = after.snapshot; entry.afterBackup = after }
        entry.status = applied.performed ? .committed : .failed
        entry.committedAt = applied.performed ? Date() : nil
        guard store.change({ data in
            if let index = data.calendarActionArchive?.firstIndex(where: { $0.id == id }) { data.calendarActionArchive?[index] = entry }
            CalendarActivityLinks.reconcileAcknowledgements(data: &data)
        }), await store.flushPendingWrites() else { throw CalendarFailure.archiveNotSaved }
        return applied.performed ? "Esito verificato nel Calendario. Ora puoi chiedere il ripristino della copia originale." : "L’evento originale è presente e invariato. Non ho applicato altre modifiche."
    }
    func applyActualWorkout(_ draft: ActualWorkoutDraft, data: AppData) async throws {
        guard !WorkoutContext.moves(draft, events: []).contains(where: { CalendarActivityLinks.requiresPairedReview($0.source, data: data) })
            else { throw CalendarActivityLinks.Failure.selection }
        try await worker.applyActualWorkout(draft, data: data)
    }
    func applyActualTimes(for record: EventRecord, event: CalendarItem, data: AppData) async throws -> CalendarItem? {
        guard let timing = CalendarSynchronization.actualTiming(for: record, event: event),
              CalendarSynchronization.needsCalendarUpdate(timing, event: event) else { return nil }
        return try await applyConfirmedTiming(timing, source: event, data: data)
    }
    func applyConfirmedTiming(_ timing: CalendarSynchronization.ActualTiming, source: CalendarItem, data: AppData) async throws -> CalendarItem {
        guard !CalendarActivityLinks.requiresPairedReview(source, data: data) else { throw CalendarActivityLinks.Failure.selection }
        guard !mutationInProgress else { throw CalendarFailure.changed }
        mutationInProgress = true; defer { mutationInProgress = false }
        let updated = try await worker.applyActualTimes(timing, source: source)
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

struct CalendarMutationReview {
    let entries: [ArchivedCalendarMutation]
    let conflicts: [CalendarItem]
}
private struct CalendarRestoreResult { let item: CalendarItem; let originalPresent: Bool }

private actor CalendarWorker {
    private lazy var eventStore = EKEventStore()
    #if DEBUG && targetEnvironment(simulator)
    private var creationFixture: Bool { ProcessInfo.processInfo.arguments.contains("--coach-calendar-create-test") }
    private var createdFixtureItems: [CalendarItem] = []
    private var recoveryForecastFixture: CalendarItem?
    private var mutationFixtureCache: [CalendarItem]?
    private var mutationFixtureKey: String? {
        guard creationFixture, ProcessInfo.processInfo.arguments.contains("--interaction-test"),
              ProcessInfo.processInfo.arguments.contains("--calendar-mutations-test"),
              let text = ProcessInfo.processInfo.environment["PIVOT_QA_COACH_ACTION_ID"], let id = UUID(uuidString: text) else { return nil }
        return "pivot-calendar-mutations-qa-" + id.uuidString
    }
    private func mutationFixtureItems() -> [CalendarItem] {
        guard let key = mutationFixtureKey else { return [] }
        if let mutationFixtureCache { return mutationFixtureCache }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        if let bytes = UserDefaults.standard.data(forKey: key), let saved = try? decoder.decode([CalendarItem].self, from: bytes) {
            mutationFixtureCache = saved; return saved
        }
        let start = PivotDate.calendar.startOfDay(for: Date())
        var initial = (1...2).map { index in
            CalendarItem(id: "mutation-qa-\(index)", eventIdentifier: "mutation-qa-\(index)", calendarIdentifier: "create-fixture",
                calendarTitle: "Personale test", title: "Impegno QA \(index)", start: start.addingTimeInterval(Double(8 + index) * 3600),
                end: start.addingTimeInterval(Double(9 + index) * 3600), location: "", notes: "Nota QA", colorHex: "7EE6CD", isAllDay: false,
                writable: true, kind: .other, sourceIdentifier: "source-fixture", sourceTitle: "Account test",
                calendarModifiedAt: start.addingTimeInterval(3600.375), recurring: false, calendarCreatedAt: start.addingTimeInterval(1800.625))
        }
        if ProcessInfo.processInfo.arguments.contains("--linked-travel-test") {
            initial[0].location = "Destinazione QA"
            initial[1].title = "Spostamento"; initial[1].location = "Destinazione QA"
            initial[1].start = initial[0].start.addingTimeInterval(-1200); initial[1].end = initial[0].start
        }
        saveMutationFixture(initial); return initial
    }
    private func saveMutationFixture(_ items: [CalendarItem]) {
        guard let key = mutationFixtureKey else { return }
        mutationFixtureCache = items
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
        if let bytes = try? encoder.encode(items) { UserDefaults.standard.set(bytes, forKey: key) }
    }
    func toggleExternalMutationFixture() -> Bool {
        guard mutationFixtureKey != nil else { return false }
        var items = mutationFixtureItems()
        guard let index = items.firstIndex(where: { $0.eventIdentifier == "mutation-qa-1" }) else { return false }
        items[index].location = items[index].location.isEmpty ? "Luogo esterno QA" : ""
        items[index].calendarModifiedAt = Date()
        saveMutationFixture(items)
        return true
    }
    private func fixtureBackup(_ item: CalendarItem) -> CalendarEventBackup {
        .init(snapshot: item, originalNotes: item.notes, url: nil, timeZoneIdentifier: "Europe/Rome", availabilityRawValue: 0, alarms: [])
    }
    private func fixtureConflicts(_ entries: [ArchivedCalendarMutation]) -> [CalendarItem] {
        let sources = Set(entries.map { $0.original.snapshot.eventIdentifier })
        return mutationFixtureItems().filter { item in
            !sources.contains(item.eventIdentifier) && entries.contains { entry in
                entry.after.map { $0.start < item.end && $0.end > item.start } ?? false
            }
        }.sorted { $0.id < $1.id }
    }
    #endif
    func reviewCreation(_ draft: CoachCalendarDraft, calendarID: String, settings: Settings,
                        options: CalendarCreationOptions, creationID: UUID, mapsConsent: Bool) throws -> [CalendarItem] {
        guard draft.problem(now: Date(), calendarID: calendarID) == nil else { throw CalendarFailure.notWritable }
        if let message = options.problem(draft: draft, now: Date(), mapsConsent: mapsConsent) { throw CalendarFailure.invalidCreationOptions(message) }
        let parts = options.parts(draft: draft, creationID: creationID)
        guard let start = parts.first?.start, let end = parts.last?.end else { throw CalendarFailure.notWritable }
        #if DEBUG && targetEnvironment(simulator)
        if creationFixture {
            guard calendarID == "create-fixture" else { throw CalendarFailure.notWritable }
            return CalendarCreationBundle.conflicts(parts: parts, events: createdFixtureItems)
        }
        #endif
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { throw CalendarFailure.noAccess }
        guard draft.problem(now: Date(), calendarID: calendarID) == nil,
              let calendar = eventStore.calendar(withIdentifier: calendarID), calendar.allowsContentModifications,
              !parts.isEmpty else { throw CalendarFailure.notWritable }
        let calendars = eventStore.calendars(for: .event).filter {
            !settings.excludedCalendarIDs.contains($0.calendarIdentifier) && !settings.excludedCalendarTitles.contains($0.title)
                && !(settings.excludeHolidays && Self.isHoliday($0.title))
        }
        guard !calendars.isEmpty else { return [] }
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return eventStore.events(matching: predicate).filter { $0.startDate < end && $0.endDate > start && $0.availability != .free && $0.status != .canceled }
            .map(Self.item).sorted { $0.id < $1.id }
    }
    func create(_ draft: CoachCalendarDraft, calendarID: String, expectedConflicts: [CalendarItem], settings: Settings,
                options: CalendarCreationOptions, creationID: UUID, mapsConsent: Bool, verifyOnly: Bool) throws -> (receipt: CalendarCreationReceipt, existing: Bool) {
        guard options.isValid, draft.problem(now: Date(), calendarID: calendarID) == nil else { throw CalendarFailure.notWritable }
        // Reconciliation is a read, not a new use of an expired route or permission.
        let fresh: [CalendarItem]
        if verifyOnly { fresh = [] }
        else { fresh = try reviewCreation(draft, calendarID: calendarID, settings: settings, options: options, creationID: creationID, mapsConsent: mapsConsent) }
        let parts = options.parts(draft: draft, creationID: creationID)
        guard let main = parts.last else { throw CalendarFailure.notWritable }
        #if DEBUG && targetEnvironment(simulator)
        if creationFixture {
            let matches = parts.compactMap { part in createdFixtureItems.first { $0.eventIdentifier == part.marker } }
            if !matches.isEmpty {
                guard CalendarCreationBundle.existing(parts: parts, items: matches), let existing = matches.last else { throw CalendarFailure.uncertainOccurrence }
                return (.init(activity: existing, travel: matches.count == 2 ? matches.first : nil), true)
            }
            guard !verifyOnly else { throw CalendarFailure.uncertainOccurrence }
            guard fresh == expectedConflicts else { throw CalendarFailure.changed }
            let added = parts.map { part in CalendarItem(id: part.marker, eventIdentifier: part.marker, calendarIdentifier: calendarID,
                calendarTitle: "Personale test", title: part.title, start: part.start, end: part.end,
                location: part.location, notes: part.notes, colorHex: "7EE6CD", isAllDay: false, writable: true, kind: .other) }
            createdFixtureItems.append(contentsOf: added)
            return (.init(activity: added.last!, travel: added.count == 2 ? added.first : nil), false)
        }
        #endif
        guard let target = eventStore.calendar(withIdentifier: calendarID), target.allowsContentModifications,
              let start = parts.first?.start else { throw CalendarFailure.notWritable }
        let predicate = eventStore.predicateForEvents(withStart: start, end: main.end, calendars: [target])
        let candidates = eventStore.events(matching: predicate)
        // A retry after save succeeded must not create another copy, even if the
        // previous UI acknowledgement or local conversation write failed.
        let matches = parts.map { part in candidates.filter { $0.url?.absoluteString == part.marker } }
        if matches.contains(where: { !$0.isEmpty }) {
            guard matches.allSatisfy({ $0.count == 1 }) else { throw CalendarFailure.uncertainOccurrence }
            let existing = matches.compactMap(\.first)
            guard CalendarCreationBundle.existing(parts: parts, items: existing.map(Self.item)),
                  zip(parts, existing).allSatisfy({ part, event in
                      event.availability.rawValue == part.availability && !event.isAllDay
                          && (event.alarms ?? []).count == (part.alertMinutes == nil ? 0 : 1)
                          && (part.alertMinutes.map { minutes in event.alarms?.first?.relativeOffset == -Double(minutes) * 60 } ?? true)
                  }) else { throw CalendarFailure.uncertainOccurrence }
            return (.init(activity: Self.item(existing.last!), travel: existing.count == 2 ? Self.item(existing[0]) : nil), true)
        }
        if let duplicate = candidates.first(where: { $0.startDate == main.start && $0.endDate == main.end &&
            EventCoalescer.normalized($0.title ?? "") == EventCoalescer.normalized(main.title) }) {
            guard parts.count == 1, (duplicate.location ?? "") == main.location,
                  duplicate.availability.rawValue == main.availability,
                  (duplicate.alarms ?? []).count == (main.alertMinutes == nil ? 0 : 1),
                  main.alertMinutes.map({ duplicate.alarms?.first?.relativeOffset == -Double($0) * 60 }) ?? true else { throw CalendarFailure.uncertainOccurrence }
            try draft.checkExistingNotes(Self.item(duplicate).notes)
            return (.init(activity: Self.item(duplicate), travel: nil), true)
        }
        guard !verifyOnly else { throw CalendarFailure.uncertainOccurrence }
        guard fresh == expectedConflicts else { throw CalendarFailure.changed }
        try Task.checkCancellation()
        var staged: [EKEvent] = []
        do {
            for part in parts {
                let event = EKEvent(eventStore: eventStore)
                event.calendar = target; event.title = part.title; event.startDate = part.start; event.endDate = part.end
                event.timeZone = PivotDate.calendar.timeZone; event.location = part.location; event.notes = part.notes
                event.url = URL(string: part.marker); event.availability = EKEventAvailability(rawValue: part.availability) ?? .busy
                if let minutes = part.alertMinutes { event.addAlarm(EKAlarm(relativeOffset: -Double(minutes) * 60)) }
                try eventStore.save(event, span: .thisEvent, commit: false); staged.append(event)
            }
        } catch {
            eventStore.reset()
            throw CalendarFailure.invalidCreationOptions("Non riesco a preparare attività e spostamento. Nessun evento è stato salvato: controlla calendario, luogo e avviso.")
        }
        do {
            // Stage both before the one commit. A failed commit is not evidence
            // that nothing reached the calendar: reconcile before another write.
            try eventStore.commit()
            return (.init(activity: Self.item(staged.last!), travel: staged.count == 2 ? Self.item(staged[0]) : nil), false)
        } catch {
            eventStore.reset()
            throw CalendarFailure.creationOptions("Salvataggio non confermato. Controlla attività e spostamento nel Calendario prima di riprovare: non aggiungere copie manualmente.")
        }
    }
    func requestAccess() async throws -> Bool { try await eventStore.requestFullAccessToEvents() }
    private func enabled(_ calendar: EKCalendar, settings: Settings) -> Bool {
        calendar.allowsContentModifications && !settings.excludedCalendarIDs.contains(calendar.calendarIdentifier)
            && !settings.excludedCalendarTitles.contains(calendar.title) && !(settings.excludeHolidays && Self.isHoliday(calendar.title))
    }
    private func occurrenceCandidates(_ source: CalendarItem) throws -> [EKEvent] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { throw CalendarFailure.noAccess }
        guard let target = eventStore.calendar(withIdentifier: source.calendarIdentifier) else { throw CalendarFailure.changed }
        let predicate = eventStore.predicateForEvents(withStart: source.start.addingTimeInterval(-1), end: source.end.addingTimeInterval(1), calendars: [target])
        return eventStore.events(matching: predicate).filter { event in
            CalendarSnapshotMatch.identity(source, Self.item(event)) && CalendarSnapshotMatch.instant(event.startDate, source.start)
                && CalendarSnapshotMatch.instant(event.endDate, source.end)
                && (source.occurrenceAnchor == nil || CoachPlanner.modificationDateMatches(source.occurrenceAnchor, event.occurrenceDate))
        }
    }
    private func singleIdentityEvent(_ source: CalendarItem) throws -> EKEvent? {
        guard source.recurring == false else { return nil }
        if let direct = eventStore.event(withIdentifier: source.eventIdentifier) {
            guard CalendarSnapshotMatch.identity(source, Self.item(direct)) else { throw CalendarFailure.changed }
            return direct
        }
        guard let external = source.externalIdentifier else { return nil }
        let matches = eventStore.calendarItems(withExternalIdentifier: external).compactMap { $0 as? EKEvent }.filter {
            CalendarSnapshotMatch.identity(source, Self.item($0))
        }
        guard matches.count <= 1 else { throw CalendarFailure.changed }
        return matches.first
    }
    private func originalEvent(_ source: CalendarItem, requireModificationDate: Bool = true) throws -> EKEvent {
        let candidates = try occurrenceCandidates(source)
        guard candidates.count == 1, let event = candidates.first else { throw CalendarFailure.changed }
        guard CalendarSnapshotMatch.revision(source, Self.item(event), requireModificationDate: requireModificationDate) else { throw CalendarFailure.changed }
        return event
    }
    private func backup(_ event: EKEvent, logicalID: String) throws -> CalendarEventBackup {
        // Invitees/external organizers and geofences cannot be reconstructed faithfully
        // by this first undo format. Refuse the whole selected batch, not a
        // partially restorable deletion or an attendee cancellation email.
        guard event.calendar.allowsContentModifications, !event.isAllDay,
              event.attendees?.isEmpty != false, (event.organizer?.isCurrentUser ?? true), event.structuredLocation == nil,
              (event.alarms ?? []).allSatisfy({ $0.structuredLocation == nil && $0.proximity == .none }) else { throw CalendarFailure.unsupportedMetadata }
        var snapshot = Self.item(event); snapshot.id = logicalID
        let alarms = (event.alarms ?? []).map { alarm in
            CalendarAlarmBackup(absoluteDate: alarm.absoluteDate, relativeSeconds: alarm.absoluteDate == nil ? alarm.relativeOffset : nil)
        }
        let result = CalendarEventBackup(snapshot: snapshot, originalNotes: event.notes, url: event.url?.absoluteString,
            timeZoneIdentifier: event.timeZone?.identifier, availabilityRawValue: event.availability.rawValue, alarms: alarms)
        guard result.isValid else { throw CalendarFailure.unsupportedMetadata }
        return result
    }
    private func mutationConflicts(_ entries: [ArchivedCalendarMutation], settings: Settings) throws -> [CalendarItem] {
        var result: [CalendarItem] = []
        for entry in entries where entry.kind == .update {
            guard let after = entry.after else { throw CalendarFailure.changed }
            let draft = CoachCalendarDraft(title: "Verifica sovrapposizioni", start: after.start, end: after.end, calendarHint: nil, notes: "", endEstimated: false)
            let overlaps = try reviewCreation(draft, calendarID: after.calendarIdentifier, settings: settings,
                options: .init(), creationID: draft.id, mapsConsent: false)
            result += overlaps.filter { overlap in
                !entries.contains { $0.original.snapshot.calendarIdentifier == overlap.calendarIdentifier
                    && $0.original.snapshot.eventIdentifier == overlap.eventIdentifier
                    && $0.original.snapshot.start == overlap.start }
            }
        }
        let proposed = entries.compactMap(\.after)
        for (index, item) in proposed.enumerated() {
            if proposed.enumerated().contains(where: { $0.offset != index && $0.element.start < item.end && $0.element.end > item.start }) { result.append(item) }
        }
        return Dictionary(result.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values.sorted { $0.id < $1.id }
    }
    func reviewMutations(batchID: UUID, actions: [CoachCalendarMutation], settings: Settings) throws -> CalendarMutationReview {
        guard (1...10).contains(actions.count), Set(actions.map(\.id)).count == actions.count,
              Set(actions.map { $0.source.id }).count == actions.count, actions.allSatisfy(\.isValid) else { throw CalendarFailure.changed }
        try Task.checkCancellation()
        #if DEBUG && targetEnvironment(simulator)
        if mutationFixtureKey != nil {
            let items = mutationFixtureItems()
            let entries = try actions.map { action -> ArchivedCalendarMutation in
                guard var fresh = items.first(where: { $0.eventIdentifier == action.source.eventIdentifier }) else { throw CalendarFailure.changed }
                fresh.id = action.source.id
                guard CalendarSnapshotMatch.revision(action.source, fresh) else { throw CalendarFailure.changed }
                return .init(batchID: batchID, actionID: action.id, kind: action.kind, original: fixtureBackup(fresh), after: action.after, preparedAt: Date())
            }
            return .init(entries: entries, conflicts: fixtureConflicts(entries))
        }
        #endif
        let entries: [ArchivedCalendarMutation] = try actions.map { action in
            let event = try originalEvent(action.source)
            guard enabled(event.calendar, settings: settings) else { throw CalendarFailure.notWritable }
            return ArchivedCalendarMutation(batchID: batchID, actionID: action.id, kind: action.kind,
                original: try backup(event, logicalID: action.source.id), after: action.after, preparedAt: Date())
        }
        return .init(entries: entries, conflicts: try mutationConflicts(entries, settings: settings))
    }
    func commitMutations(_ review: CalendarMutationReview, settings: Settings) throws -> [ArchivedCalendarMutation] {
        let entries = review.entries
        guard (1...10).contains(entries.count), entries.allSatisfy({ $0.isValid && $0.status == .prepared }),
              Set(entries.map(\.actionID)).count == entries.count else { throw CalendarFailure.changed }
        #if DEBUG && targetEnvironment(simulator)
        if mutationFixtureKey != nil {
            var items = mutationFixtureItems()
            guard fixtureConflicts(entries) == review.conflicts else { throw CalendarFailure.changed }
            for entry in entries {
                guard var current = items.first(where: { $0.eventIdentifier == entry.original.snapshot.eventIdentifier }) else { throw CalendarFailure.changed }
                current.id = entry.original.snapshot.id
                guard CalendarSnapshotMatch.backup(entry.original, fixtureBackup(current)) else { throw CalendarFailure.changed }
            }
            try Task.checkCancellation()
            var result = entries
            for index in result.indices {
                let entry = result[index]
                items.removeAll { $0.eventIdentifier == entry.original.snapshot.eventIdentifier }
                if let after = entry.after { items.append(after); result[index].afterBackup = fixtureBackup(after) }
                result[index].status = .committed; result[index].committedAt = Date()
            }
            saveMutationFixture(items); return result
        }
        #endif
        var targets: [EKEvent] = []
        for entry in entries {
            let event = try originalEvent(entry.original.snapshot)
            guard enabled(event.calendar, settings: settings), try CalendarSnapshotMatch.backup(entry.original, backup(event, logicalID: entry.original.snapshot.id)) else { throw CalendarFailure.changed }
            targets.append(event)
        }
        guard try mutationConflicts(entries, settings: settings) == review.conflicts else { throw CalendarFailure.changed }
        try Task.checkCancellation()
        do {
            for (entry, event) in zip(entries, targets) {
                if entry.kind == .delete { try eventStore.remove(event, span: .thisEvent, commit: false) }
                else {
                    guard let after = entry.after else { throw CalendarFailure.changed }
                    event.title = after.title; event.startDate = after.start; event.endDate = after.end
                    if after.notes != entry.original.snapshot.notes { event.notes = after.notes }
                    try eventStore.save(event, span: .thisEvent, commit: false)
                }
            }
            try eventStore.commit()
        } catch { eventStore.reset(); throw error }
        return try zip(entries, targets).map { entry, event in
            var completed = entry; completed.status = .committed; completed.committedAt = Date()
            if entry.kind == .update {
                let after = try backup(event, logicalID: entry.original.snapshot.id)
                completed.after = after.snapshot; completed.afterBackup = after
            }
            return completed
        }
    }
    private func applyOriginal(_ original: CalendarEventBackup, to event: EKEvent, marker: URL? = nil) throws {
        guard original.isValid, let availability = EKEventAvailability(rawValue: original.availabilityRawValue) else { throw CalendarFailure.unsupportedMetadata }
        event.title = original.snapshot.title; event.startDate = original.snapshot.start; event.endDate = original.snapshot.end
        event.isAllDay = false; event.location = original.snapshot.location; event.notes = original.originalNotes
        event.timeZone = original.timeZoneIdentifier.flatMap { TimeZone(identifier: $0) }
        event.url = original.url.flatMap { URL(string: $0) } ?? marker; event.availability = availability
        event.alarms = original.alarms.map { alarm in
            if let date = alarm.absoluteDate { return EKAlarm(absoluteDate: date) }
            return EKAlarm(relativeOffset: alarm.relativeSeconds!)
        }
    }
    private func payloadMatches(_ event: EKEvent, original: CalendarEventBackup, expected: CalendarItem, marker: URL? = nil) -> Bool {
        guard let current = try? backup(event, logicalID: expected.id) else { return false }
        return current.snapshot.title == expected.title && CalendarSnapshotMatch.instant(current.snapshot.start, expected.start) && CalendarSnapshotMatch.instant(current.snapshot.end, expected.end)
            && current.snapshot.location == expected.location && current.snapshot.notes == CalendarNoteText.plain(expected.notes)
            && current.originalNotes == (expected.notes == original.snapshot.notes ? original.originalNotes : expected.notes)
            && current.timeZoneIdentifier == original.timeZoneIdentifier && current.availabilityRawValue == original.availabilityRawValue
            && current.alarms.count == original.alarms.count && zip(current.alarms, original.alarms).allSatisfy({ CalendarSnapshotMatch.alarm($0.0, $0.1) })
            && (current.url == original.url || (original.url == nil && current.url == marker?.absoluteString))
    }
    func restoreMutation(_ entry: ArchivedCalendarMutation, settings: Settings) throws -> CalendarRestoreResult {
        #if DEBUG && targetEnvironment(simulator)
        if mutationFixtureKey != nil, entry.isValid, entry.status == .restorationPrepared {
            var items = mutationFixtureItems()
            if entry.kind == .update {
                guard let after = entry.after, let index = items.firstIndex(where: { $0.eventIdentifier == after.eventIdentifier }) else { throw CalendarFailure.changed }
                if CalendarSnapshotMatch.revision(entry.original.snapshot, items[index]) { return .init(item: items[index], originalPresent: false) }
                guard let afterBackup = entry.afterBackup, CalendarSnapshotMatch.backup(afterBackup, fixtureBackup(items[index]), requireModificationDate: false) else { throw CalendarFailure.changed }
                items[index] = entry.original.snapshot; saveMutationFixture(items)
                return .init(item: items[index], originalPresent: false)
            }
            if let existing = items.first(where: { $0.eventIdentifier == entry.original.snapshot.eventIdentifier }) {
                guard CalendarSnapshotMatch.revision(entry.original.snapshot, existing) else { throw CalendarFailure.changed }
                return .init(item: existing, originalPresent: true)
            }
            if let existing = items.first(where: { $0.title == entry.original.snapshot.title && CalendarSnapshotMatch.instant($0.start, entry.original.snapshot.start) && $0.notes == entry.original.snapshot.notes }) {
                return .init(item: existing, originalPresent: false)
            }
            var restored = entry.original.snapshot
            restored.id = "restored-" + entry.id.uuidString; restored.eventIdentifier = restored.id; restored.recurring = false; restored.occurrenceAnchor = nil
            items.append(restored); saveMutationFixture(items)
            return .init(item: restored, originalPresent: false)
        }
        #endif
        guard entry.isValid, entry.status == .restorationPrepared,
              EKEventStore.authorizationStatus(for: .event) == .fullAccess else { throw CalendarFailure.noAccess }
        let original = entry.original, source = original.snapshot
        guard let target = eventStore.calendar(withIdentifier: source.calendarIdentifier), enabled(target, settings: settings) else { throw CalendarFailure.notWritable }
        if entry.kind == .update {
            guard let after = entry.after, let afterBackup = entry.afterBackup else { throw CalendarFailure.changed }
            // Retry after an interrupted undo must not overwrite another app's
            // edit. If our original values are already back, adopt that result.
            let originals = try occurrenceCandidates(source).filter { payloadMatches($0, original: original, expected: source) }
            guard originals.count <= 1 else { throw CalendarFailure.changed }
            if let current = originals.first {
                var item = Self.item(current); item.id = source.id
                return .init(item: item, originalPresent: false)
            }
            // A server can advance only its synchronization timestamp. An undo
            // still requires every restorable payload field to equal our saved
            // after-image; a timestamp alone is not permission to overwrite it.
            let event = try originalEvent(after, requireModificationDate: false)
            guard try CalendarSnapshotMatch.backup(afterBackup, backup(event, logicalID: source.id), requireModificationDate: false) else { throw CalendarFailure.changed }
            try applyOriginal(original, to: event)
            try Task.checkCancellation(); try eventStore.save(event, span: .thisEvent, commit: true)
            var item = Self.item(event); item.id = source.id
            return .init(item: item, originalPresent: false)
        }
        let marker = URL(string: "pivot://restored/" + entry.id.uuidString)!
        if let current = try singleIdentityEvent(source) {
            guard payloadMatches(current, original: original, expected: source) else { throw CalendarFailure.changed }
            return .init(item: Self.item(current), originalPresent: true)
        }
        let predicate = eventStore.predicateForEvents(withStart: source.start.addingTimeInterval(-1), end: source.end.addingTimeInterval(1), calendars: [target])
        let matches = eventStore.events(matching: predicate).filter { payloadMatches($0, original: original, expected: source, marker: marker) }
        guard matches.count <= 1 else { throw CalendarFailure.changed }
        if let existing = matches.first {
            var item = Self.item(existing); item.recurring = false
            guard existing.hasRecurrenceRules == false else { throw CalendarFailure.changed }
            return .init(item: item, originalPresent: item.eventIdentifier == source.eventIdentifier)
        }
        let event = EKEvent(eventStore: eventStore); event.calendar = target
        try applyOriginal(original, to: event, marker: marker)
        try Task.checkCancellation(); try eventStore.save(event, span: .thisEvent, commit: true)
        return .init(item: Self.item(event), originalPresent: false)
    }
    func reconcileMutation(_ entry: ArchivedCalendarMutation) throws -> (performed: Bool, after: CalendarEventBackup?) {
        #if DEBUG && targetEnvironment(simulator)
        if mutationFixtureKey != nil {
            let current = mutationFixtureItems().first { $0.eventIdentifier == entry.original.snapshot.eventIdentifier }
            if let current, CalendarSnapshotMatch.backup(entry.original, fixtureBackup(current)) { return (false, nil) }
            if entry.kind == .delete, current == nil { return (true, nil) }
            if let after = entry.after, let current, CalendarSnapshotMatch.revision(after, current) { return (true, fixtureBackup(current)) }
            throw CalendarFailure.uncertainOccurrence
        }
        #endif
        guard entry.isValid, [.prepared, .uncertain].contains(entry.status),
              EKEventStore.authorizationStatus(for: .event) == .fullAccess else { throw CalendarFailure.noAccess }
        let source = entry.original.snapshot
        if let original = try? originalEvent(source), try CalendarSnapshotMatch.backup(entry.original, backup(original, logicalID: source.id)) { return (false, nil) }
        if entry.kind == .update, let after = entry.after,
           let event = eventStore.event(withIdentifier: after.eventIdentifier), event.calendar.calendarIdentifier == source.calendarIdentifier,
           payloadMatches(event, original: entry.original, expected: after) {
            return (true, try backup(event, logicalID: source.id))
        }
        // A missing occurrence from a series cannot prove whether a remote
        // writer moved it. Do not recreate or change that series speculatively.
        if entry.kind == .delete, source.recurring == false,
           try singleIdentityEvent(source) == nil { return (true, nil) }
        throw CalendarFailure.uncertainOccurrence
    }
    func incomeHistory(year: Int, calendarIDs: Set<String>, settings: Settings) throws -> [CalendarItem] {
        assert(!Thread.isMainThread, "Calendar history must not block touch handling")
        let now = Date()
        guard HistoricalIncome.validYear(year, now: now), !calendarIDs.isEmpty,
              let start = PivotDate.calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let yearEnd = PivotDate.calendar.date(byAdding: .year, value: 1, to: start) else { throw CalendarFailure.changed }
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--interaction-test"), ProcessInfo.processInfo.arguments.contains("--history-test") {
            return (0..<2).map { index in
                let date = start.addingTimeInterval(Double(3 + index) * 86400 + 10 * 3600)
                let id = "history-fixture-\(year)-\(index)"
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
    func contactActivity(settings: Settings) throws -> ClientCalendarActivity {
        assert(!Thread.isMainThread, "Contact history must not block touch handling")
        let now = Date(), calendar = PivotDate.calendar
        guard let from = calendar.date(byAdding: .day, value: -91, to: now),
              let through = calendar.date(byAdding: .year, value: 4, to: calendar.startOfDay(for: now)),
              let limit = calendar.date(byAdding: .day, value: 2, to: through) else { throw CalendarFailure.changed }
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--contact-activity-test") {
            var items = interactionSnapshot().events
            let date = calendar.date(byAdding: .day, value: 7, to: now)!
            let id = "contact-activity-future-qa"
            items.append(CalendarItem(id: id, eventIdentifier: id, calendarIdentifier: "interaction", calendarTitle: "Lavoro",
                title: "Lezione Contatto Attivo QA", start: date, end: date.addingTimeInterval(3600), location: "", notes: "",
                colorHex: "7EE6CD", isAllDay: false, writable: true, kind: .tutoring))
            return .init(observedAt: Date(), from: from, through: limit, complete: true, items: items)
        }
        #endif
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { throw CalendarFailure.noAccess }
        let selected = contactCalendars(settings: settings)
        guard !selected.isEmpty else { throw CalendarFailure.changed }
        let selectedIDs = Set(selected.map(\.calendarIdentifier))
        var items: [String: CalendarItem] = [:], cursor = from
        // EventKit predicates have a finite range. Year-sized chunks avoid
        // silent truncation of this four-year future + 90-day history scan.
        while cursor < limit {
            try Task.checkCancellation()
            let end = min(calendar.date(byAdding: .year, value: 1, to: cursor)!, limit)
            let predicate = eventStore.predicateForEvents(withStart: cursor, end: end, calendars: selected)
            let found = eventStore.events(matching: predicate)
            guard found.count <= 20_000, items.count + found.count <= 100_000 else {
                return .init(observedAt: Date(), from: from, through: cursor, complete: false, items: Array(items.values))
            }
            for event in found where event.status != .canceled { let item = Self.item(event); items[item.id] = item }
            cursor = end
        }
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess,
              Set(contactCalendars(settings: settings).map(\.calendarIdentifier)) == selectedIDs
        else { throw CalendarFailure.changed }
        return .init(observedAt: Date(), from: from, through: limit, complete: true,
                     items: items.values.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start })
    }
    private func contactCalendars(settings: Settings) -> [EKCalendar] {
        // A read-only shared lesson still prevents deactivation. Mutation
        // eligibility (`enabled`) is deliberately NOT the read filter here.
        eventStore.calendars(for: .event).filter {
            !settings.excludedCalendarIDs.contains($0.calendarIdentifier)
                && !settings.excludedCalendarTitles.contains($0.title)
                && !(settings.excludeHolidays && Self.isHoliday($0.title))
        }
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
        #if DEBUG && targetEnvironment(simulator)
        if creationFixture, mutationFixtureKey != nil, ProcessInfo.processInfo.arguments.contains("--actual-time-sync-test") {
            var items = mutationFixtureItems()
            guard let index = items.firstIndex(where: { CalendarSnapshotMatch.revision(source, $0) }),
                  timing.start.timeIntervalSinceReferenceDate.isFinite, timing.end.timeIntervalSinceReferenceDate.isFinite,
                  timing.end > timing.start else { throw CalendarFailure.changed }
            items[index].start = timing.start; items[index].end = timing.end; items[index].calendarModifiedAt = Date()
            saveMutationFixture(items)
            return items[index]
        }
        #endif
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { throw CalendarFailure.noAccess }
        guard source.writable, !source.isAllDay, timing.start.timeIntervalSinceReferenceDate.isFinite,
              timing.end.timeIntervalSinceReferenceDate.isFinite, timing.end > timing.start else { throw CalendarFailure.notWritable }
        let padding: TimeInterval = 36 * 3600
        let predicate = eventStore.predicateForEvents(withStart: source.start.addingTimeInterval(-padding), end: source.end.addingTimeInterval(padding), calendars: nil)
        let matching = eventStore.events(matching: predicate).filter { CalendarSnapshotMatch.identity(source, Self.item($0)) }
        guard matching.count == 1, let event = matching.first, event.calendar.allowsContentModifications else { throw CalendarFailure.changed }
        // The view is a snapshot. Refuse the write if another app changed this
        // occurrence after Pivot displayed it.
        guard CalendarSnapshotMatch.revision(source, Self.item(event)) else { throw CalendarFailure.changed }
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
        if ProcessInfo.processInfo.arguments.contains("--coach-scope-test") {
            // Isolate scope consent from the unrelated 700-event stress fixture.
            // Both days are real native UI inputs; the busy variant tests refusal.
            let busy = ProcessInfo.processInfo.arguments.contains("--coach-scope-busy-test")
            let today = PivotDate.calendar.startOfDay(for: Date())
            let items = (0..<(busy ? 50 : 2)).map { index -> CalendarItem in
                let offset = index == 0 ? 0 : (busy ? 1 + (index - 1) % 6 : 1)
                let day = PivotDate.calendar.date(byAdding: .day, value: offset, to: today)!
                let start = day.addingTimeInterval(9 * 3600 + Double(index) * 60)
                let id = "scope-qa-\(index)"
                return CalendarItem(id: id, eventIdentifier: id, calendarIdentifier: "scope-qa", calendarTitle: "QA",
                    title: "Impegno QA \(index)", start: start, end: start.addingTimeInterval(1800),
                    location: "", notes: "", colorHex: "7EE6CD", isAllDay: false, writable: true, kind: .other)
            }
            return .init(hasAccess: true, choices: [.init(id: "scope-qa", title: "QA", colorHex: "7EE6CD", holiday: false, writable: true)], events: items)
        }
        if ProcessInfo.processInfo.arguments.contains("--recovery-forecast-test") {
            if recoveryForecastFixture == nil {
                let start = Date().addingTimeInterval(-3 * 3600)
                recoveryForecastFixture = .init(id: "recovery-qa", eventIdentifier: "recovery-qa", calendarIdentifier: "recovery-qa",
                    calendarTitle: "QA", title: "Allenamento QA da recuperare", start: start, end: start.addingTimeInterval(3600),
                    location: "", notes: "", colorHex: "7EE6CD", isAllDay: false, writable: true, kind: .workout)
            }
            return .init(hasAccess: true, choices: [.init(id: "recovery-qa", title: "QA", colorHex: "7EE6CD", holiday: false, writable: true)],
                         events: recoveryForecastFixture.map { [$0] } ?? [])
        }
        if creationFixture {
            return .init(hasAccess: true, choices: [.init(id: "create-fixture", title: "Personale test", colorHex: "7EE6CD", holiday: false, writable: true, sourceTitle: "Account test", sourceIdentifier: "source-fixture")], events: mutationFixtureKey != nil ? mutationFixtureItems() : createdFixtureItems)
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
            writable: event.calendar.allowsContentModifications,
            kind: Self.isTravelMarker(event.url) ? .other : .classify(title: event.title ?? "", calendar: event.calendar.title),
            sourceIdentifier: event.calendar.source.sourceIdentifier, sourceTitle: event.calendar.source.title,
            calendarModifiedAt: event.lastModifiedDate, recurring: recurring, occurrenceAnchor: anchor,
            calendarRGB: Self.rgb(event.calendar.cgColor), calendarCreatedAt: event.creationDate)
    }
    private static func isTravelMarker(_ url: URL?) -> Bool {
        guard let url, url.scheme == "pivot", url.host == "travel" else { return false }
        return UUID(uuidString: String(url.path.dropFirst())) != nil
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
    case noAccess, changed, notWritable, unsupportedMetadata, archiveNotSaved, acknowledgementNotSaved, uncertainOccurrence
    case creationOptions(String), invalidCreationOptions(String)
    var stoppedBeforeCalendarWrite: Bool {
        switch self {
        case .noAccess, .changed, .notWritable, .unsupportedMetadata, .invalidCreationOptions: true
        default: false
        }
    }
    var errorDescription: String? {
        switch self {
        case .noAccess: return "Consenti l'accesso completo ai calendari nelle impostazioni di iOS."
        case .changed: return "L'evento è cambiato, non esiste più o non è modificabile. Aggiorna la giornata e riprova."
        case .notWritable: return "Questo evento non può essere modificato nel Calendario."
        case .unsupportedMetadata: return "Questa selezione comprende inviti, luoghi strutturati o avvisi che Pivot non può ancora ripristinare fedelmente. Nessun evento selezionato è stato modificato: escludilo dall’anteprima e riprova."
        case .archiveNotSaved: return "La copia di recupero non è salvata su disco. Non avvio altre modifiche al Calendario: completa il salvataggio nelle Impostazioni."
        case .acknowledgementNotSaved: return "Il Calendario potrebbe essere già cambiato, ma la conferma locale non è ancora salvata. Non ripetere l’operazione: verifica l’esito nello storico modifiche."
        case .uncertainOccurrence: return "L’evento è diverso dall’originale e dall’esito previsto. Non lo sovrascrivo e non creo copie: verifica questa occorrenza nel Calendario."
        case .creationOptions(let message), .invalidCreationOptions(let message): return message
        }
    }
}

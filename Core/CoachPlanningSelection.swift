import Foundation

/// Future local intake, not a proposal or Calendar permission. Deliberately
/// NOT Codable: original titles/locations/identities must not become a DTO.
struct CoachPlanningSelection {
    let intent: CoachPlanningIntent
    let requestID: String
    let sources: [CalendarItem]
    let reference: CalendarItem?
    let allowedIntervals: [DateInterval]
    let unconfirmedTravelIDs: [String]
    let pairedReviewIDs: [String]
    private let snapshot: CoachV8Snapshot
    private let intervalAnchor: Date
    private let requiresOnlineAccess: Bool

    struct Access { let calendar: Bool; let online: Bool }
    enum Failure: LocalizedError, Equatable {
        case accessRevoked, invalidIntent, staleContext, ineligibleActivity, pendingReview, invalidReference
        var errorDescription: String? {
            switch self {
            case .accessRevoked: return "Controlla l’accesso al Calendario e, per un nuovo messaggio online, il consenso AI."
            case .invalidIntent: return "Non riesco a verificare i vincoli del piano. Nessuna modifica preparata."
            case .staleContext: return "L’agenda o il piano è cambiato. Aggiorna e ripeti la richiesta."
            case .ineligibleActivity: return "L’attività è fissa, già svolta, in corso o non modificabile. Controllala prima di chiedere il recupero."
            case .pendingReview: return "C’è già una modifica da confermare per questa attività. Completa o annulla quella proposta prima di prepararne un’altra."
            case .invalidReference: return "Non riesco a identificare l’impegno dopo cui vuoi organizzarti. Specifica quale intendi."
            }
        }
    }
    // This is readiness to SEARCH, never readiness to write. Full duration,
    // preparation and every proposed slot/travel still need their own review.
    var maySearchLocally: Bool { !allowedIntervals.isEmpty && unconfirmedTravelIDs.isEmpty && pairedReviewIDs.isEmpty }

    static func prepare(_ intent: CoachPlanningIntent, responseRequestID: String, snapshot: CoachV8Snapshot, access: Access,
                        events: [CalendarItem], data: AppData, now: Date) throws -> Self {
        try prepare(intent, responseRequestID: responseRequestID, snapshot: snapshot, access: access,
                    events: events, data: data, now: now, anchor: snapshot.request.now, requiresOnline: true)
    }

    /// Reopening a previously authorized LOCAL plan sends nothing to the cloud.
    /// Its original civil-date anchor is retained, while every event and rule is
    /// checked afresh. Revoking online consent does not disable local review.
    static func restore(_ session: CoachPlanningSession, calendarAccess: Bool,
                        events: [CalendarItem], data: AppData, now: Date) throws -> Self {
        guard CoachPlanningStore.valid(data.coachState),
              data.coachState.planningSessions?.contains(session) == true else { throw Failure.staleContext }
        let snapshot = try CoachV8Snapshot.localPlanning(session, events: events, data: data, now: now)
        let context = try session.context(remapping: snapshot.sources, now: now)
        return try prepare(context.intent, responseRequestID: snapshot.request.requestID, snapshot: snapshot,
            access: .init(calendar: calendarAccess, online: false), events: events, data: data,
            now: now, anchor: context.anchor, requiresOnline: false)
    }

    private static func prepare(_ intent: CoachPlanningIntent, responseRequestID: String, snapshot: CoachV8Snapshot, access: Access,
                                events: [CalendarItem], data: AppData, now: Date, anchor: Date, requiresOnline: Bool) throws -> Self {
        guard access.calendar, !requiresOnline || access.online else { throw Failure.accessRevoked }
        guard validDate(now), validDate(snapshot.request.now), snapshot.request.purpose == "conversation",
              responseRequestID == snapshot.request.requestID,
              snapshot.isCurrent(events: events, data: data, now: now) else { throw Failure.staleContext }
        let aliases = Set(snapshot.request.events.map(\.id))
        guard aliases.count == snapshot.request.events.count, aliases == Set(snapshot.sources.keys),
              intent.isValid(knownAliases: aliases) else { throw Failure.invalidIntent }
        var selected: [CalendarItem] = [], travel: [String] = [], paired: [String] = []
        for alias in intent.eventIDs {
            guard let source = snapshot.sources[alias], CalendarEventBackup.valid(source), !source.isAllDay,
                  source.writable, source.end > source.start, source.end.timeIntervalSince(source.start) <= 86400,
                  ![Completion.running, .completed, .partial].contains(data.records[source.id]?.status ?? .pending) else {
                throw Failure.ineligibleActivity
            }
            guard !selected.contains(where: { sameOccurrence($0, source) }) else { throw Failure.invalidIntent }
            let rule = EventRule.effective(for: source, data: data)
            guard rule.flexibility != .fixed, (0...1440).contains(rule.travelBeforeMinutes),
                  (0...1440).contains(rule.travelAfterMinutes) else { throw Failure.ineligibleActivity }
            let pendingMove = data.moves.contains { !$0.syncedToCalendar && sameOccurrence($0.source, source) }
            let pendingChange = data.coachState.pendingCalendarChanges.contains { sameOccurrence($0.move.source, source) }
            let pendingBatch = (data.coachState.calendarBatches ?? []).contains { batch in
                [CoachCalendarBatchStatus.pending, .reviewRequired].contains(batch.status) && batch.actions.contains { sameOccurrence($0.source, source) }
            }
            guard !pendingMove, !pendingChange, !pendingBatch else { throw Failure.pendingReview }
            if !rule.travelConfirmed { travel.append(source.id) }
            // Do not route around the linked-pair executor's current safeguard.
            // No single-activity PlanMove is created for an activity/trip pair.
            if CalendarActivityLinks.requiresPairedReview(source, data: data) { paired.append(source.id) }
            selected.append(source)
        }
        let reference: CalendarItem?
        if let id = intent.afterEventID {
            guard let source = snapshot.sources[id], CalendarEventBackup.valid(source), !source.isAllDay,
                  source.end > source.start else { throw Failure.invalidReference }
            reference = source
        } else { reference = nil }
        let referenceEnds: [String: Date]
        if let alias = intent.afterEventID, let reference { referenceEnds = [alias: reference.end] }
        else { referenceEnds = [:] }
        let intervals = try intent.intervals(knownAliases: aliases, anchor: anchor, now: now, referenceEnds: referenceEnds)
        return .init(intent: intent, requestID: responseRequestID, sources: selected, reference: reference,
            allowedIntervals: intervals, unconfirmedTravelIDs: travel, pairedReviewIDs: paired, snapshot: snapshot,
            intervalAnchor: anchor, requiresOnlineAccess: requiresOnline)
    }
    func isCurrent(access: Access, events: [CalendarItem], data: AppData, now: Date) -> Bool {
        access.calendar && (!requiresOnlineAccess || access.online) && Self.validDate(now) && snapshot.isCurrent(events: events, data: data, now: now)
    }
    /// Repeat semantic eligibility as well as revision checks at the local
    /// search boundary. Never rely on a cached readiness flag after a review.
    func revalidated(access: Access, events: [CalendarItem], data: AppData, now: Date) throws -> Self {
        try Self.prepare(intent, responseRequestID: requestID, snapshot: snapshot, access: access, events: events, data: data,
                         now: now, anchor: intervalAnchor, requiresOnline: requiresOnlineAccess)
    }
    private static func validDate(_ value: Date) -> Bool {
        value.timeIntervalSince1970.isFinite && (0...253_402_300_799).contains(value.timeIntervalSince1970)
    }
    private static func sameOccurrence(_ first: CalendarItem, _ second: CalendarItem) -> Bool {
        first.id == second.id || (CalendarSnapshotMatch.identity(first, second)
            && CalendarSnapshotMatch.instant(first.start, second.start) && CalendarSnapshotMatch.instant(first.end, second.end))
    }
}

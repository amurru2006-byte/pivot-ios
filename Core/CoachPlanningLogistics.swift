import Foundation

/// Provenance and availability of LOCAL activity/travel groups. This path never
/// relaxes CoachPlanner's single-move safeguard and cannot write native events.
enum CoachPlanningLogistics {
    private struct NativeKey: Hashable { var calendar: String; var source: String?; var event: String }
    /// Bounded native-identity lookup. Repeated full-calendar scans for every
    /// archived link would make the contextual card quadratic on large stores.
    struct EventIndex {
        private var events: [CalendarItem]
        private var native: [NativeKey: [Int]] = [:]
        private var external: [NativeKey: [Int]] = [:]
        init(_ events: [CalendarItem]) {
            self.events = events
            for (index, event) in events.enumerated() {
                native[.init(calendar: event.calendarIdentifier, source: event.sourceIdentifier, event: event.eventIdentifier), default: []].append(index)
                if let id = event.externalIdentifier {
                    external[.init(calendar: event.calendarIdentifier, source: event.sourceIdentifier, event: id), default: []].append(index)
                }
            }
        }
        func matches(_ expected: CalendarItem) -> [CalendarItem] {
            let a = native[.init(calendar: expected.calendarIdentifier, source: expected.sourceIdentifier, event: expected.eventIdentifier)] ?? []
            let b = expected.externalIdentifier.flatMap { external[.init(calendar: expected.calendarIdentifier, source: expected.sourceIdentifier, event: $0)] } ?? []
            // Many ambiguous identities require review; never pick an arbitrary
            // first item or exhaustively compare a malformed series on the UI.
            guard a.count <= 8, b.count <= 8 else { return [] }
            return Set(a + b).sorted().map { events[$0] }.filter { CalendarSnapshotMatch.identity(expected, $0) }
        }
    }
    enum Failure: LocalizedError {
        case changed, review, invalid
        var errorDescription: String? {
            switch self {
            case .changed: return "L’attività o il viaggio collegato sono cambiati. Rivedi il gruppo prima di cercare nuove alternative."
            case .review: return "Questo piano non conserva ancora la verifica del viaggio collegato. Verifica insieme attività e viaggio nel piano."
            case .invalid: return "Non riesco a verificare il gruppo e i suoi tempi. Nessuna modifica preparata."
            }
        }
    }
    static func capture(sources: [CalendarItem], events: [CalendarItem], data: AppData) throws -> [CalendarActivityLink] {
        guard CalendarActivityLinks.valid(data) else { throw Failure.invalid }
        var captured: [CalendarActivityLink] = []
        for source in sources where CalendarActivityLinks.requiresPairedReview(source, data: data) {
            guard let link = CalendarActivityLinks.link(for: source, data: data),
                  CalendarSnapshotMatch.identity(link.activity, source),
                  CalendarSnapshotMatch.revision(link.activity, source),
                  !sources.contains(where: { CalendarSnapshotMatch.identity(link.travel, $0) }) else { throw Failure.changed }
            for expected in [link.activity, link.travel] {
                let current = events.filter { CalendarSnapshotMatch.identity(expected, $0) }
                guard current.count == 1, let current = current.first,
                      CalendarSnapshotMatch.revision(expected, current),
                      ![Completion.running, .completed, .partial].contains(data.records[current.id]?.status ?? .pending),
                      !data.moves.contains(where: { !$0.syncedToCalendar && CalendarSnapshotMatch.identity(expected, $0.source) }),
                      !data.coachState.pendingCalendarChanges.contains(where: { CalendarSnapshotMatch.identity(expected, $0.move.source) }),
                      !(data.coachState.calendarBatches ?? []).contains(where: { batch in
                          [.pending, .reviewRequired].contains(batch.status) && batch.actions.contains { CalendarSnapshotMatch.identity(expected, $0.source) }
                      }) else { throw Failure.changed }
            }
            captured.append(link)
        }
        guard Set(captured.map(\.id)).count == captured.count else { throw Failure.invalid }
        return captured
    }
    static func verify(_ session: CoachPlanningSession, events: [CalendarItem], data: AppData, now: Date) throws {
        let sources = session.intent.eventIDs.compactMap { session.bindings[$0] }
        let current = try capture(sources: sources, events: events, data: data)
        guard current == (session.groupSnapshots ?? []) else {
            throw session.groupSnapshots == nil && !current.isEmpty ? Failure.review : Failure.changed
        }
        for choice in session.durationChoices ?? [] {
            guard let source = sources.first(where: { $0.id == choice.sourceID }), let library = data.training else {
                throw CoachPlanningDurationChoice.Failure.changed
            }
            try choice.revalidated(source: source, library: library, now: now)
        }
    }
    static func duration(_ source: CalendarItem, session: CoachPlanningSession) -> TimeInterval {
        session.durationChoices?.first(where: { $0.sourceID == source.id }).map { Double($0.activityMinutes) * 60 }
            ?? source.end.timeIntervalSince(source.start)
    }
    static func budget(_ source: CalendarItem, session: CoachPlanningSession, data: AppData) throws -> CalendarTimeBudget {
        let seconds = duration(source, session: session), rule = EventRule.effective(for: source, data: data)
        let link = session.groupSnapshots?.first { $0.activity.id == source.id }
        let journey = link.map { Int(ceil($0.travel.end.timeIntervalSince($0.travel.start) / 60)) } ?? 0
        guard seconds.isFinite, seconds >= source.end.timeIntervalSince(source.start), seconds > 0, seconds <= 86400,
              seconds >= Double(max(1, rule.minimumMinutes)) * 60,
              let result = CalendarTimeBudget.confirmed(activityMinutes: Int(ceil(seconds / 60)), rule: rule,
                preparationMinutes: max(0, journey - rule.travelBeforeMinutes)) else { throw Failure.invalid }
        return result
    }
    static func tripMove(for move: PlanMove, session: CoachPlanningSession) -> PlanMove? {
        guard let link = session.groupSnapshots?.first(where: { $0.activity.id == move.source.id }) else { return nil }
        let seconds = link.travel.end.timeIntervalSince(link.travel.start)
        return .init(source: link.travel, proposedStart: move.proposedStart.addingTimeInterval(-seconds), proposedEnd: move.proposedStart)
    }
    static func hasSpecialReview(_ session: CoachPlanningSession) -> Bool {
        !(session.groupSnapshots ?? []).isEmpty || !(session.durationChoices ?? []).isEmpty
    }
    /// An explicitly linked journey is already an occupied event, not another
    /// destination requiring a second outbound journey. Preserve explicit rules
    /// and any unconfirmed per-event logistics; only resolve the default rule.
    static func availabilityData(events: [CalendarItem], data: AppData) -> AppData {
        var result = data
        let index = EventIndex(events)
        for link in data.calendarActivityLinks ?? [] where !link.deleted {
            let activities = index.matches(link.activity)
            let journeys = index.matches(link.travel)
            guard activities.count == 1, journeys.count == 1, link.isValid,
                  let activity = activities.first, let journey = journeys.first,
                  CalendarSnapshotMatch.revision(link.activity, activity), CalendarSnapshotMatch.revision(link.travel, journey),
                  data.rules[journey.id] == nil else { continue }
            result.rules[journey.id] = .init(flexibility: .fixed, minimumMinutes: journey.durationMinutes, travelConfirmed: true)
        }
        return result
    }
    static func validate(_ option: CoachOption, session: CoachPlanningSession, events: [CalendarItem], data: AppData, now: Date) -> String? {
        guard session.isActive(at: now) else { return Failure.changed.localizedDescription }
        guard hasSpecialReview(session) else { return CoachPlanner.validate(option, events: events, data: data, now: now) }
        do {
            try verify(session, events: events, data: data, now: now)
            let sources = session.intent.eventIDs.compactMap { session.bindings[$0] }
            guard option.moves.count == sources.count, Set(option.moves.map { $0.source.id }).count == sources.count else { throw Failure.invalid }
            var simulated = availabilityData(events: events, data: data)
            for (source, move) in zip(sources, option.moves) {
                guard source == move.source, move.proposedStart > now,
                      abs(move.proposedEnd.timeIntervalSince(move.proposedStart) - duration(source, session: session)) < 0.001 else { throw Failure.invalid }
                let value = try budget(source, session: session, data: data)
                let start = move.proposedStart.addingTimeInterval(-Double(value.beforeMinutes) * 60)
                let end = move.proposedStart.addingTimeInterval(Double(value.activityMinutes + value.afterMinutes) * 60)
                let matches = CalendarRecoveryWindows.find(target: source, budget: value, events: events, data: simulated,
                    now: now, days: 7, within: [.init(start: start, end: end)], limit: 1)
                guard matches.count == 1, abs(matches[0].activityStart.timeIntervalSince(move.proposedStart)) < 0.001 else { throw Failure.invalid }
                simulated.moves.append(move)
                if let trip = tripMove(for: move, session: session) { simulated.moves.append(trip) }
            }
            return nil
        } catch { return error.localizedDescription }
    }
    /// Only a locally staged batch. Its existing review expands the linked trip,
    /// asks for a fresh route choice when needed, and requires native confirmation.
    static func stage(_ option: CoachOption, session: CoachPlanningSession, events: [CalendarItem], data: inout AppData, now: Date) throws {
        guard data.coachState.planningSessions?.contains(session) == true,
              option.createdAt <= now, now.timeIntervalSince(option.createdAt) <= 120,
              validate(option, session: session, events: events, data: data, now: now) == nil else { throw Failure.changed }
        let actions = option.moves.map { move -> CoachCalendarMutation in
            var after = move.source; after.start = move.proposedStart; after.end = move.proposedEnd
            return .init(kind: .update, source: move.source, after: after)
        }
        let message = CoachMessage(dayKey: PivotDate.key(now), role: .coach,
            text: "Piano preparato per la revisione: attività e viaggi collegati vanno confermati insieme. Le stime di tragitto richiedono verifica al nuovo orario. Il Calendario non è cambiato.", createdAt: now)
        let batch = CoachCalendarBatch(messageID: message.id, dayKey: message.dayKey, createdAt: now, actions: actions)
        guard batch.isValid else { throw Failure.invalid }
        var next = data
        next.coachState.messages.append(message)
        var batches = next.coachState.calendarBatches ?? []; batches.append(batch); next.coachState.calendarBatches = batches
        guard CoachCalendarBatch.valid(next.coachState) else { throw Failure.invalid }
        data = next
    }
}

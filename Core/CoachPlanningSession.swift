import Foundation

/// Cloud-safe constraints retain their ORIGINAL date anchor across midnight.
/// Event aliases are remapped for each new request. No native IDs or addresses.
struct CoachPlanningContext: Codable, Equatable {
    var anchor: Date
    var intent: CoachPlanningIntent
    func isValid(knownAliases: Set<String>, now: Date) -> Bool {
        CoachPlanningSession.validDate(anchor) && CoachPlanningSession.validDate(now)
            && now >= anchor && now.timeIntervalSince(anchor) <= 8 * 86400
            && intent.isValid(knownAliases: knownAliases)
    }
}

/// Durable LOCAL provenance, never encoded into a provider request wholesale.
/// Saving this object is not acceptance of an alternative or a Calendar write.
struct CoachPlanningSession: Codable, Equatable, Identifiable {
    enum Status: String, Codable { case draft, staged, dismissed }
    enum Failure: LocalizedError, Equatable {
        case invalid, changed, expired, reviewRequired, limit
        var errorDescription: String? {
            switch self {
            case .invalid: return "Non riesco a verificare questa richiesta di recupero. Nessuna modifica preparata."
            case .changed: return "L’attività del piano è cambiata o non è più disponibile. Apri il piano per controllarla, oppure scegli Nuovo argomento."
            case .expired: return "La settimana di questo piano è terminata. Avvia una nuova richiesta: le vecchie date non sono state spostate a oggi."
            case .reviewRequired: return "Il piano include un giorno precedentemente escluso. Aprilo e conferma i giorni da reincludere prima di proseguire."
            case .limit: return "Hai raggiunto il limite dei piani salvati. Elimina una conversazione prima di prepararne un altro."
            }
        }
    }
    var id = UUID()
    var messageID: UUID
    var userMessageID: UUID
    var dayKey: String
    var createdAt: Date
    var updatedAt: Date
    var anchor: Date
    var intent: CoachPlanningIntent
    var bindings: [String: CalendarItem]
    // Earlier exclusions cannot be silently lifted by an inconsistent model turn.
    var protectedExcludedDays: [Date] = []
    var status: Status = .draft

    var isValid: Bool {
        let required = Set(intent.eventIDs + (intent.afterEventID.map { [$0] } ?? []))
        guard (1...4).contains(bindings.count), Set(bindings.keys) == required,
              intent.isValid(knownAliases: Set(bindings.keys)), bindings.values.allSatisfy({ CalendarEventBackup.valid($0) && !$0.isAllDay }),
              Set(bindings.values.map(\.id)).count == bindings.count,
              intent.eventIDs.allSatisfy({ alias in
                  guard let item = bindings[alias] else { return false }
                  return item.writable && item.end.timeIntervalSince(item.start) <= 86400
              }),
              [createdAt, updatedAt, anchor].allSatisfy(Self.validDate), createdAt <= anchor, anchor <= updatedAt,
              dayKey == PivotDate.key(anchor), protectedExcludedDays.count <= 7,
              Set(protectedExcludedDays).count == protectedExcludedDays.count else { return false }
        return protectedExcludedDays.allSatisfy { date in
            guard Self.validDate(date), date == PivotDate.calendar.startOfDay(for: date),
                  let offset = Self.offset(of: date, from: anchor) else { return false }
            return (0...6).contains(offset)
        }
    }
    var sourceTitles: String { intent.eventIDs.compactMap { bindings[$0]?.title }.joined(separator: ", ") }
    var allowedDays: [Date] { days(intent.allowedDayOffsets) }
    var excludedDays: [Date] { days(intent.excludedDayOffsets) }
    var pendingReadmittedDays: [Date] { allowedDays.filter { protectedExcludedDays.contains($0) } }
    func isActive(at now: Date) -> Bool {
        guard isValid, status == .draft, Self.validDate(now), now >= updatedAt,
              let end = PivotDate.calendar.date(byAdding: .day, value: 7, to: PivotDate.calendar.startOfDay(for: anchor)) else { return false }
        return now < end
    }

    static func make(_ response: CoachV8Response, snapshot: CoachV8Snapshot,
                     messageID: UUID, userMessageID: UUID, access: CoachPlanningSelection.Access,
                     events: [CalendarItem], data: AppData, now: Date) throws -> Self {
        guard response.version == 4, snapshot.request.version == 4, response.mode == .recover,
              response.eventIDs.isEmpty, response.actions?.isEmpty == true, response.draft == nil,
              response.rewrittenMessage == nil, let rawIntent = response.planning else { throw Failure.invalid }
        let selected = try CoachPlanningSelection.prepare(rawIntent, responseRequestID: response.requestID,
            snapshot: snapshot, access: access, events: events, data: data, now: now)
        if let declared = CoachRecoveryRequest.parse(snapshot.request.message, now: snapshot.request.now)?.sourceDay,
           !selected.sources.allSatisfy({ $0.occurs(on: declared) }) { throw Failure.changed }
        let required = Set(rawIntent.eventIDs + (rawIntent.afterEventID.map { [$0] } ?? []))
        let bindings = snapshot.sources.filter { required.contains($0.key) }
        let candidateParent = snapshot.focusedPlanningSession
        let parent = candidateParent.flatMap { saved -> Self? in
            let old = Set(saved.intent.eventIDs.compactMap { saved.bindings[$0]?.id })
            return saved.isActive(at: now) && old == Set(selected.sources.map(\.id)) ? saved : nil
        }
        var value = Self(messageID: messageID, userMessageID: userMessageID, dayKey: snapshot.request.dayKey,
            createdAt: parent?.createdAt ?? snapshot.request.now, updatedAt: now, anchor: snapshot.request.now,
            intent: rawIntent, bindings: bindings)
        if let parent { value.id = parent.id }
        let protected = (parent?.protectedExcludedDays ?? []) + value.excludedDays
        value.protectedExcludedDays = Array(Set(protected.filter {
            Self.offset(of: $0, from: value.anchor).map { (0...6).contains($0) } ?? false
        })).sorted()
        // Preserve an old exclusion omitted by the model. A conflict with a new
        // allowed day stays visible as pendingReadmittedDays, requiring native review.
        let retained = value.protectedExcludedDays.compactMap { Self.offset(of: $0, from: value.anchor) }
            .filter { !value.intent.allowedDayOffsets.contains($0) }
        value.intent.excludedDayOffsets = Array(Set(value.intent.excludedDayOffsets + retained)).sorted()
        guard value.isValid else { throw Failure.invalid }
        return value
    }

    func boundEvents(in events: [CalendarItem], now: Date) throws -> [CalendarItem] {
        guard isValid else { throw Failure.invalid }
        guard isActive(at: now) else { throw Failure.expired }
        let targets = Set(intent.eventIDs)
        return try bindings.keys.sorted().map { alias in
            guard let expected = bindings[alias] else { throw Failure.invalid }
            let matches = events.filter { current in
                guard expected.id == current.id else { return false }
                if targets.contains(alias) { return CalendarSnapshotMatch.revision(expected, current) }
                return CalendarSnapshotMatch.identity(expected, current) && CoachPlanner.matchesSnapshot(expected, current)
                    && expected.writable == current.writable && expected.recurring == current.recurring
                    && CoachPlanner.modificationDateMatches(expected.occurrenceAnchor, current.occurrenceAnchor)
            }
            guard matches.count == 1, let current = matches.first else { throw Failure.changed }
            return current
        }
    }
    func context(remapping sources: [String: CalendarItem], now: Date) throws -> CoachPlanningContext {
        guard isActive(at: now) else { throw Failure.expired }
        guard pendingReadmittedDays.isEmpty else { throw Failure.reviewRequired }
        let values = try boundEvents(in: Array(sources.values), now: now)
        var aliases: [String: String] = [:]
        for (old, item) in bindings {
            guard values.contains(where: { $0.id == item.id }),
                  let fresh = sources.first(where: { $0.value.id == item.id })?.key else { throw Failure.changed }
            aliases[old] = fresh
        }
        var remapped = intent
        remapped.eventIDs = try intent.eventIDs.map { old in
            guard let alias = aliases[old] else { throw Failure.changed }; return alias
        }
        if let old = intent.afterEventID {
            guard let alias = aliases[old] else { throw Failure.changed }; remapped.afterEventID = alias
        }
        let result = CoachPlanningContext(anchor: anchor, intent: remapped)
        guard result.isValid(knownAliases: Set(sources.keys), now: now) else { throw Failure.invalid }
        return result
    }

    mutating func confirmReadmittedDays(now: Date) throws {
        guard isActive(at: now) else { throw Failure.expired }
        let readmitted = Set(pendingReadmittedDays)
        guard !readmitted.isEmpty else { throw Failure.invalid }
        protectedExcludedDays.removeAll { readmitted.contains($0) }; updatedAt = now
    }
    private func days(_ offsets: [Int]) -> [Date] {
        guard Self.validDate(anchor) else { return [] }
        let start = PivotDate.calendar.startOfDay(for: anchor)
        return offsets.sorted().compactMap { PivotDate.calendar.date(byAdding: .day, value: $0, to: start) }
    }
    static func validDate(_ value: Date) -> Bool {
        value.timeIntervalSince1970.isFinite && (0...253_402_300_799).contains(value.timeIntervalSince1970)
    }
    private static func offset(of date: Date, from anchor: Date) -> Int? {
        guard validDate(date), validDate(anchor) else { return nil }
        return PivotDate.calendar.dateComponents([.day], from: PivotDate.calendar.startOfDay(for: anchor),
            to: PivotDate.calendar.startOfDay(for: date)).day
    }
}

enum CoachPlanningStore {
    static let limit = 1000
    static func valid(_ state: CoachState) -> Bool {
        let values = state.planningSessions ?? []
        let messages = Dictionary(state.messages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard values.count <= limit, Set(values.map(\.id)).count == values.count,
              Set(values.map(\.messageID)).count == values.count, Set(values.map(\.userMessageID)).count == values.count,
              messages.count == state.messages.count,
              values.allSatisfy(\.isValid),
              state.focusedPlanningSessionID == nil || state.focusedCalendarDraftID == nil,
              state.focusedPlanningSessionID.map({ id in values.contains { $0.id == id && $0.status == .draft } }) ?? true else { return false }
        return values.allSatisfy { value in
            guard let reply = messages[value.messageID], let user = messages[value.userMessageID] else { return false }
            return reply.role == .coach && reply.dayKey == value.dayKey
                && user.role == .user && user.dayKey == value.dayKey && user.onlineHistoryEligible == true && user.healthDerived != true
        }
    }
    static func save(_ value: CoachPlanningSession, in state: inout CoachState) throws {
        var values = state.planningSessions ?? []
        guard value.isValid, value.status == .draft else { throw CoachPlanningSession.Failure.invalid }
        if let index = values.firstIndex(where: { $0.id == value.id }) { values[index] = value }
        else { guard values.count < limit else { throw CoachPlanningSession.Failure.limit }; values.append(value) }
        var next = state; next.planningSessions = values; next.focusedPlanningSessionID = value.id
        next.focusedCalendarDraftID = nil; next.omitPreviousDraft = true
        guard valid(next) else { throw CoachPlanningSession.Failure.invalid }
        state = next
    }
}

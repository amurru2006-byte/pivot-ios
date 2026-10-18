import Foundation

// Network DTOs deliberately omit calendar IDs, titles, notes, locations and Health data.
struct CoachV8Request: Codable {
    var version = 1
    var purpose: String? = nil
    var requestID: String
    var now: Date
    var dayKey: String
    var message: String
    var events: [Event]
    var history: [Message]
    var memories: [String]
    // V3 only. Draft facts were supplied/reviewed by the user; no calendar
    // titles, notes, source IDs or addresses are added to event summaries.
    var draftContext: [CoachCalendarDraft]? = nil
    var references: [String]? = nil
    var historyOmittedCount: Int? = nil

    struct Event: Codable {
        var id: String
        var kind: EventKind
        var category: Category
        var status: Completion
        var start: Date
        var end: Date
        var durationMinutes: Int
        var flexibility: EventFlexibility
        var travelConfirmed: Bool
    }
    enum Category: String, Codable { case lunch, gym, other }
    struct Message: Codable {
        var role: String
        var text: String
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}
struct CoachV8Response: Decodable {
    var version: Int
    var requestID: String
    var mode: Mode
    var eventIDs: [String]
    var reply: String
    var draft: CoachCalendarDraft? = nil
    var rewrittenMessage: String? = nil
    var actions: [CoachCalendarEdit]? = nil
    enum Mode: String, Decodable { case conversation, clarify, plan, create, rewrite, actions }

    static func decode(_ bytes: Data, for request: CoachV8Request) throws -> Self {
        var keys: Set<String> = request.version >= 2
            ? ["version", "requestID", "mode", "eventIDs", "reply", "draft", "rewrittenMessage"]
            : ["version", "requestID", "mode", "eventIDs", "reply"]
        if request.version == 3 { keys.insert("actions") }
        guard bytes.count <= (request.version >= 2 ? 32_000 : 8192),
              let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              Set(object.keys) == keys else {
            throw CoachV8Error.invalidResponse
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let value = try decoder.decode(Self.self, from: bytes)
        guard value.version == request.version, value.requestID == request.requestID,
              !value.reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.reply.count <= 1000,
              Set(value.eventIDs).count == value.eventIDs.count,
              value.eventIDs.allSatisfy({ id in request.events.contains { $0.id == id } }),
              (value.mode == .plan ? (1...2).contains(value.eventIDs.count) : value.eventIDs.isEmpty) else {
            throw CoachV8Error.invalidResponse
        }
        if request.version == 1 {
            guard value.mode != .create, value.mode != .rewrite, value.mode != .actions else { throw CoachV8Error.invalidResponse }
        } else {
            guard [2, 3].contains(request.version) else { throw CoachV8Error.invalidResponse }
            if request.version == 3 {
                guard let actions = value.actions, actions.count <= 10,
                      Set(actions.map(\.eventID)).count == actions.count,
                      actions.allSatisfy({ $0.valid(now: request.now) }) else { throw CoachV8Error.invalidResponse }
                guard actions.allSatisfy({ action in request.events.contains { $0.id == action.eventID } }),
                      (value.mode == .actions ? !actions.isEmpty : actions.isEmpty) else { throw CoachV8Error.invalidResponse }
                if let rawActions = object["actions"] as? [[String: Any]] {
                    guard rawActions.allSatisfy({ Set($0.keys) == Set(["kind", "eventID", "title", "start", "end", "notes"]) }) else { throw CoachV8Error.invalidResponse }
                } else { throw CoachV8Error.invalidResponse }
            } else if value.mode == .actions { throw CoachV8Error.invalidResponse }
            if value.mode == .create || (request.version == 3 && [.clarify, .actions].contains(value.mode) && value.draft != nil) {
                guard request.purpose == "conversation", let draft = value.draft,
                      value.mode != .create || !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      draft.title.count <= 160, draft.notes.count <= 3000,
                      (draft.calendarHint?.count ?? 0) <= 160,
                      let raw = object["draft"] as? [String: Any],
                      Set(raw.keys) == Set(["title", "start", "end", "calendarHint", "notes", "endEstimated"]),
                      value.rewrittenMessage == nil else { throw CoachV8Error.invalidResponse }
            } else if value.mode == .rewrite {
                guard request.purpose == "rewrite", value.draft == nil,
                      let text = value.rewrittenMessage, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      text.count <= 12_000 else { throw CoachV8Error.invalidResponse }
            } else {
                guard request.purpose == "conversation", value.draft == nil,
                      value.rewrittenMessage == nil else { throw CoachV8Error.invalidResponse }
            }
        }
        return value
    }
}

enum CoachV8Error: Error, LocalizedError {
    case invalidResponse, contextTooLarge, emptyMessage, staleContext
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "La risposta AI non supera i controlli. Nessuna modifica preparata."
        case .contextTooLarge: return "Il messaggio o il calendario supera i limiti di questo collegamento AI. Il testo resta qui e non viene tagliato: dividi il messaggio o usa la base locale."
        case .emptyMessage: return "Scrivi un messaggio prima di inviare."
        case .staleContext: return "La richiesta è scaduta o i dati sono cambiati. Prepara una nuova anteprima."
        }
    }
}

struct CoachV8Snapshot {
    private(set) var request: CoachV8Request
    private(set) var encodedRequest: Data
    private(set) var originalEvents: [CalendarItem]
    private(set) var dataUpdatedAt: Date
    private(set) var sources: [String: CalendarItem]

    static func make(message: String, events: [CalendarItem], data: AppData, now: Date, purpose: String? = nil,
        protocolVersion: Int = 2) throws -> Self {
        let clean = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw CoachV8Error.emptyMessage }
        guard clean.count <= (purpose == nil ? 1500 : 12_000),
              purpose == nil || ["conversation", "rewrite"].contains(purpose!) else { throw CoachV8Error.contextTooLarge }
        let canonical = EventCoalescer.unique(events, data: data)
        let calendarData = CoachPrivacy.calendarData(data)
        let planned = Planner.plannedEvents(events, data: calendarData).filter { purpose != "rewrite" && !$0.isAllDay && $0.occurs(on: now) }
            .sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
        guard planned.count <= 48 else { throw CoachV8Error.contextTooLarge }
        var sources: [String: CalendarItem] = [:]
        let summaries: [CoachV8Request.Event] = planned.enumerated().compactMap { index, item in
            guard let source = canonical.first(where: { $0.id == item.id }) else { return nil }
            let alias = "e\(index)"
            sources[alias] = source
            let title = EventCoalescer.normalized(item.title)
            let category: CoachV8Request.Category
            if item.kind == .meal && title.split(separator: " ").contains("pranzo") { category = .lunch }
            else if item.kind == .workout && CardioKind.suggested(item.title) == nil { category = .gym }
            else { category = .other }
            let rule = EventRule.effective(for: item, data: data)
            return .init(id: alias, kind: item.kind, category: category,
                         status: calendarData.records[item.id]?.status ?? .pending,
                         start: item.start, end: item.end, durationMinutes: item.durationMinutes,
                         flexibility: rule.flexibility, travelConfirmed: rule.travelConfirmed)
        }
        let eligibleHistory = data.coachState.messages.filter {
            purpose != "rewrite" && $0.dayKey == PivotDate.key(now) && $0.onlineHistoryEligible == true
                && $0.healthDerived != true && ($0.role == .user || $0.role == .coach)
        }
        let version = purpose == nil ? 1 : (purpose == "conversation" && protocolVersion == 3 ? 3 : 2)
        let history = eligibleHistory.suffix(version == 3 ? 20 : 6).map {
            let text = CoachPrivacy.text($0.text, events: events, data: data)
            return CoachV8Request.Message(role: $0.role == .user ? "user" : "assistant", text: version == 3 ? text : String(text.prefix(400)))
        }
        var request = CoachV8Request(version: version, purpose: purpose,
                                     requestID: UUID().uuidString, now: now, dayKey: PivotDate.key(now),
                                     message: CoachPrivacy.text(clean, events: events, data: data), events: summaries, history: history,
                                     // Memories lack provenance and per-message cloud consent.
                                     memories: [])
        if version == 3 {
            let messages = data.coachState.messages
            let drafts = (data.coachState.calendarDrafts ?? []).filter { saved in
                saved.dayKey == PivotDate.key(now) && saved.createdEventID == nil
                    && messages.contains { $0.id == saved.messageID && $0.onlineHistoryEligible == true && $0.healthDerived != true }
            }.sorted { $0.updatedAt < $1.updatedAt }
            request.draftContext = drafts.last.map { saved in
                var draft = saved.draft
                draft.title = CoachPrivacy.text(draft.title, events: events, data: data)
                draft.notes = CoachPrivacy.text(draft.notes, events: events, data: data)
                draft.calendarHint = draft.calendarHint.map { CoachPrivacy.text($0, events: events, data: data) }
                return [draft]
            } ?? []
            // A local exact title mention resolves to aliases, without sending
            // that private title to the provider. Multiple matches stay ambiguous.
            let mentions = EventCoalescer.normalized(clean)
            request.references = sources.keys.sorted().filter { alias in
                guard let source = sources[alias] else { return false }
                let title = EventCoalescer.normalized(source.title)
                return title.count >= 4 && (" " + mentions + " ").contains(" " + title + " ")
            }
            request.historyOmittedCount = eligibleHistory.count - history.count
            // Drop whole oldest turns, never silently cut facts halfway through
            // a sentence. The disclosure and model see how many were omitted.
            while !request.history.isEmpty {
                let tooLarge = try request.encoded().count > 24_000
                if !tooLarge && !request.history.contains(where: { $0.text.count > 12_000 }) { break }
                request.history.removeFirst(); request.historyOmittedCount! += 1
            }
        }
        guard request.message.count <= (purpose == nil ? 1500 : 12_000) else { throw CoachV8Error.contextTooLarge }
        let bytes = try request.encoded()
        guard bytes.count <= 24_000 else { throw CoachV8Error.contextTooLarge }
        return .init(request: request, encodedRequest: bytes, originalEvents: events, dataUpdatedAt: data.updatedAt, sources: sources)
    }

    func isCurrent(events: [CalendarItem], data: AppData, now: Date) -> Bool {
        events == originalEvents && data.updatedAt == dataUpdatedAt
            && PivotDate.key(now) == request.dayKey
            && now >= request.now && now.timeIntervalSince(request.now) <= 120
    }
}

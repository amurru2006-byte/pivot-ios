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
    enum Mode: String, Decodable { case conversation, clarify, plan, create, rewrite }

    static func decode(_ bytes: Data, for request: CoachV8Request) throws -> Self {
        let keys: Set<String> = request.version == 2
            ? ["version", "requestID", "mode", "eventIDs", "reply", "draft", "rewrittenMessage"]
            : ["version", "requestID", "mode", "eventIDs", "reply"]
        guard bytes.count <= (request.version == 2 ? 32_000 : 8192),
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
            guard value.mode != .create, value.mode != .rewrite else { throw CoachV8Error.invalidResponse }
        } else {
            guard request.version == 2 else { throw CoachV8Error.invalidResponse }
            if value.mode == .create {
                guard request.purpose == "conversation", let draft = value.draft,
                      !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
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

    static func make(message: String, events: [CalendarItem], data: AppData, now: Date, purpose: String? = nil) throws -> Self {
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
            let rule = data.rules[item.id] ?? .defaultRule(for: item)
            return .init(id: alias, kind: item.kind, category: category,
                         status: calendarData.records[item.id]?.status ?? .pending,
                         start: item.start, end: item.end, durationMinutes: item.durationMinutes,
                         flexibility: rule.flexibility, travelConfirmed: rule.travelConfirmed)
        }
        let history = data.coachState.messages.filter {
            purpose != "rewrite" && $0.dayKey == PivotDate.key(now) && $0.onlineHistoryEligible == true
                && $0.healthDerived != true && ($0.role == .user || $0.role == .coach)
        }.suffix(6).map { CoachV8Request.Message(role: $0.role == .user ? "user" : "assistant",
                                               text: String(CoachPrivacy.text($0.text, events: events, data: data).prefix(400))) }
        let request = CoachV8Request(version: purpose == nil ? 1 : 2, purpose: purpose,
                                     requestID: UUID().uuidString, now: now, dayKey: PivotDate.key(now),
                                     message: CoachPrivacy.text(clean, events: events, data: data), events: summaries, history: history,
                                     // Memories lack provenance and per-message cloud consent.
                                     memories: [])
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

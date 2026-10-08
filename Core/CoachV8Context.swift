import Foundation

// Network DTOs deliberately omit calendar IDs, titles, notes, locations and Health data.
struct CoachV8Request: Codable {
    var version = 1
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
    enum Mode: String, Decodable { case conversation, clarify, plan }

    static func decode(_ bytes: Data, for request: CoachV8Request) throws -> Self {
        guard bytes.count <= 8192,
              let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              Set(object.keys) == Set(["version", "requestID", "mode", "eventIDs", "reply"]) else {
            throw CoachV8Error.invalidResponse
        }
        let value = try JSONDecoder().decode(Self.self, from: bytes)
        guard value.version == 1, value.requestID == request.requestID,
              !value.reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.reply.count <= 1000,
              Set(value.eventIDs).count == value.eventIDs.count,
              value.eventIDs.allSatisfy({ id in request.events.contains { $0.id == id } }),
              (value.mode == .plan ? (1...2).contains(value.eventIDs.count) : value.eventIDs.isEmpty) else {
            throw CoachV8Error.invalidResponse
        }
        return value
    }
}

enum CoachV8Error: Error, LocalizedError {
    case invalidResponse, contextTooLarge, emptyMessage, staleContext
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "La risposta AI non supera i controlli. Nessuna modifica preparata."
        case .contextTooLarge: return "Il contesto è troppo ampio per questo primo collegamento AI. Usa le regole locali."
        case .emptyMessage: return "Scrivi un messaggio prima di inviare."
        case .staleContext: return "La giornata è cambiata. Aggiorna prima di chiedere una nuova proposta."
        }
    }
}

struct CoachV8Snapshot {
    var request: CoachV8Request
    private(set) var originalEvents: [CalendarItem]
    private(set) var dataUpdatedAt: Date
    private(set) var sources: [String: CalendarItem]

    static func make(message: String, events: [CalendarItem], data: AppData, now: Date) throws -> Self {
        let clean = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw CoachV8Error.emptyMessage }
        guard clean.count <= 1500 else { throw CoachV8Error.contextTooLarge }
        let canonical = EventCoalescer.unique(events, data: data)
        let planned = Planner.plannedEvents(events, data: data).filter { !$0.isAllDay && $0.occurs(on: now) }
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
                         status: data.records[item.id]?.status ?? .pending,
                         start: item.start, end: item.end, durationMinutes: item.durationMinutes,
                         flexibility: rule.flexibility, travelConfirmed: rule.travelConfirmed)
        }
        let history = data.coachState.messages.filter {
            $0.dayKey == PivotDate.key(now) && $0.healthDerived != true && ($0.role == .user || $0.role == .coach)
        }.suffix(6).map { CoachV8Request.Message(role: $0.role == .user ? "user" : "assistant", text: String($0.text.prefix(400))) }
        let request = CoachV8Request(requestID: UUID().uuidString, now: now, dayKey: PivotDate.key(now),
                                     message: clean, events: summaries, history: history,
                                     memories: data.coachState.memories.suffix(4).map { String($0.text.prefix(240)) })
        guard try request.encoded().count <= 24_000 else { throw CoachV8Error.contextTooLarge }
        return .init(request: request, originalEvents: events, dataUpdatedAt: data.updatedAt, sources: sources)
    }

    func isCurrent(events: [CalendarItem], data: AppData, now: Date) -> Bool {
        events == originalEvents && data.updatedAt == dataUpdatedAt
            && PivotDate.key(now) == request.dayKey
            && now >= request.now && now.timeIntervalSince(request.now) <= 120
    }
}

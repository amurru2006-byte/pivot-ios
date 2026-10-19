import Foundation

/// User-controlled context. No generated summaries, inferred habits or additional
/// provider calls: the exact strings still appear in the outgoing disclosure.
enum CoachMemoryContext {
    static let onlineLimit = 4

    static func online(memories: [CoachMemory], events: [CalendarItem], data: AppData, now: Date) throws -> [String] {
        try memories.filter { $0.onlineSharingAllowed == true && $0.isActive(at: now) }
            .sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt }
            .prefix(onlineLimit).map {
                let clean = CoachPrivacy.text($0.text, events: events, data: data)
                // Never trim a preference mid-sentence or drop its qualification.
                guard !clean.isEmpty, clean.utf16.count <= 240 else { throw CoachV8Error.contextTooLarge }
                return clean
            }
    }

    static func problem(_ memory: CoachMemory, replacing id: UUID?, in memories: [CoachMemory]) -> String? {
        guard memory.isValid else { return "Controlla testo e scadenza: massimo 1.500 caratteri, oppure 240 per una preferenza condivisa online." }
        if memory.onlineSharingAllowed == true,
           memories.filter({ $0.id != id && $0.onlineSharingAllowed == true }).count >= onlineLimit {
            return "Puoi condividere al massimo 4 preferenze. Disattivane una prima di aggiungerne un’altra."
        }
        return nil
    }
}

enum CoachConversationFocus {
    /// An explicit focus is strict. If it was deleted, saved or belongs to a
    /// different day, never fall through to an unrelated older draft.
    static func draft(in state: CoachState, dayKey: String) -> CoachSavedCalendarDraft? {
        guard state.omitPreviousDraft != true else { return nil }
        let drafts = state.calendarDrafts ?? []
        if let id = state.focusedCalendarDraftID {
            return drafts.first { $0.id == id && eligible($0, state: state, dayKey: dayKey) }
        }
        let order = Dictionary(state.messages.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        return drafts.filter { eligible($0, state: state, dayKey: dayKey) }
            .max { (order[$0.messageID] ?? -1) < (order[$1.messageID] ?? -1) }
    }

    static func eligible(_ draft: CoachSavedCalendarDraft, state: CoachState, dayKey: String) -> Bool {
        guard draft.dayKey == dayKey, draft.createdEventID == nil, draft.creationNeedsVerification != true else { return false }
        let sourceID = draft.userMessageID ?? draft.messageID
        return state.messages.contains { $0.id == sourceID && $0.onlineHistoryEligible == true && $0.healthDerived != true }
    }

    /// Only an explicitly focused, same-title draft may be enriched. A new title
    /// starts a separate draft. No completed or uncertain write is ever rewritten.
    static func continuing(_ draft: CoachCalendarDraft, parent: CoachSavedCalendarDraft?) -> CoachCalendarDraft {
        guard let parent, parent.createdEventID == nil, parent.creationNeedsVerification != true,
              draft.title.isEmpty || EventCoalescer.normalized(draft.title) == EventCoalescer.normalized(parent.draft.title) else { return draft }
        var result = draft
        if result.title.isEmpty { result.title = parent.draft.title }
        if result.start == nil { result.start = parent.draft.start }
        if result.end == nil, result.start == parent.draft.start {
            result.end = parent.draft.end; result.endEstimated = parent.draft.endEstimated
        }
        if result.calendarHint == nil { result.calendarHint = parent.draft.calendarHint }
        // A focused continuation retains omitted notes. Explicitly emptying them
        // remains available in the event editor, before any calendar confirmation.
        if result.notes.isEmpty { result.notes = parent.draft.notes }
        return result
    }
}

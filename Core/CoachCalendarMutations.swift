import Foundation

/// Untrusted model patch. Nil means preserve; an empty notes string explicitly
/// clears notes. Event IDs are request aliases, never provider-supplied EK IDs.
struct CoachCalendarEdit: Codable, Equatable {
    var kind: CalendarMutationKind
    var eventID: String
    var title: String?
    var start: Date?
    var end: Date?
    var notes: String?

    func valid(now: Date) -> Bool {
        guard now.timeIntervalSinceReferenceDate.isFinite,
              eventID.range(of: #"^e[0-9]{1,2}$"#, options: .regularExpression) != nil,
              title.map({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 160 }) ?? true,
              (notes?.count ?? 0) <= 3000 else { return false }
        if kind == .delete { return title == nil && start == nil && end == nil && notes == nil }
        guard title != nil || start != nil || end != nil || notes != nil else { return false }
        if start != nil || end != nil {
            guard let start, let end, start.timeIntervalSinceReferenceDate.isFinite, end.timeIntervalSinceReferenceDate.isFinite,
                  end > start, end.timeIntervalSince(start) <= 86400,
                  start <= now.addingTimeInterval(366 * 86400) else { return false }
        }
        return true
    }
}

struct CoachCalendarMutation: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: CalendarMutationKind
    var source: CalendarItem
    var after: CalendarItem?
    var isValid: Bool {
        guard CalendarEventBackup.valid(source), source.writable, !source.isAllDay else { return false }
        if kind == .delete { return after == nil }
        guard let after, CalendarEventBackup.valid(after), !after.isAllDay,
              after.end.timeIntervalSince(after.start) <= 86400 else { return false }
        // A patch cannot switch account, identity, recurrence or location.
        var before = source, patched = after
        before.title = ""; before.start = .distantPast; before.end = .distantFuture; before.notes = ""
        patched.title = ""; patched.start = .distantPast; patched.end = .distantFuture; patched.notes = ""
        return before == patched && after != source
    }
}

enum CoachCalendarBatchStatus: String, Codable { case pending, applied, discarded, reviewRequired }
struct CoachCalendarBatch: Codable, Identifiable, Equatable {
    var id = UUID()
    var messageID: UUID
    var dayKey: String
    var createdAt: Date
    var actions: [CoachCalendarMutation]
    var status: CoachCalendarBatchStatus = .pending
    var isValid: Bool {
        (1...10).contains(actions.count) && createdAt.timeIntervalSinceReferenceDate.isFinite
            && dayKey == PivotDate.key(createdAt)
            && Set(actions.map(\.id)).count == actions.count && Set(actions.map { $0.source.id }).count == actions.count
            && actions.allSatisfy(\.isValid)
    }
    static func make(_ edits: [CoachCalendarEdit], sources: [String: CalendarItem], messageID: UUID,
        now: Date, data: AppData) throws -> Self {
        guard (1...10).contains(edits.count), Set(edits.map(\.eventID)).count == edits.count else { throw CoachV8Error.invalidResponse }
        let actions: [CoachCalendarMutation] = try edits.map { edit in
            guard edit.valid(now: now), let source = sources[edit.eventID], source.occurs(on: now),
                  source.writable, !source.isAllDay, data.records[source.id]?.status != .running,
                  !data.moves.contains(where: { !$0.syncedToCalendar && $0.source.id == source.id }) else { throw CoachV8Error.invalidResponse }
            var after: CalendarItem?
            if edit.kind == .update {
                var value = source
                if let title = edit.title { value.title = title }
                if let start = edit.start, let end = edit.end { value.start = start; value.end = end }
                if let notes = edit.notes { value.notes = notes }
                after = value
            }
            let action = CoachCalendarMutation(kind: edit.kind, source: source, after: after)
            guard action.isValid else { throw CoachV8Error.invalidResponse }
            return action
        }
        let batch = Self(messageID: messageID, dayKey: PivotDate.key(now), createdAt: now, actions: actions)
        guard batch.isValid else { throw CoachV8Error.invalidResponse }
        return batch
    }
    static func valid(_ state: CoachState) -> Bool {
        let batches = state.calendarBatches ?? []
        guard batches.count <= 10_000, Set(batches.map(\.id)).count == batches.count,
              Set(batches.map(\.messageID)).count == batches.count, batches.allSatisfy(\.isValid) else { return false }
        return batches.allSatisfy { batch in
            state.messages.contains { $0.id == batch.messageID && $0.role == .coach && $0.dayKey == batch.dayKey }
        }
    }
}

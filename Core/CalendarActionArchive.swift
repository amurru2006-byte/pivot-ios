import Foundation

enum CalendarMutationKind: String, Codable { case update, delete }
enum CalendarArchiveStatus: String, Codable {
    // Prepared is durably written BEFORE an external mutation. An interrupted
    // acknowledgement remains reviewable; it is never a license to retry blindly.
    case prepared, committed, uncertain, failed, restorationPrepared, restored
}

struct CalendarAlarmBackup: Codable, Equatable {
    var absoluteDate: Date?
    var relativeSeconds: Double?
    var isValid: Bool {
        if let absoluteDate {
            return relativeSeconds == nil && absoluteDate.timeIntervalSinceReferenceDate.isFinite
        }
        guard let relativeSeconds else { return false }
        return relativeSeconds.isFinite && abs(relativeSeconds) <= 366 * 86400
    }
}

/// Private recovery data, never an online-Coach DTO or a PT/finance report.
/// Unsupported metadata must block the native mutation, not be silently lost.
struct CalendarEventBackup: Codable, Equatable {
    var snapshot: CalendarItem
    var originalNotes: String?
    var url: String?
    var timeZoneIdentifier: String?
    var availabilityRawValue: Int
    var alarms: [CalendarAlarmBackup]
    var isValid: Bool {
        Self.valid(snapshot) && CalendarNoteText.plain(originalNotes ?? "") == snapshot.notes
            && (originalNotes?.count ?? 0) <= 65_536 && (url?.count ?? 0) <= 4096
            && (timeZoneIdentifier.map { TimeZone(identifier: $0) != nil } ?? true)
            && (-1...3).contains(availabilityRawValue) && alarms.count <= 32 && alarms.allSatisfy(\.isValid)
    }
    static func valid(_ item: CalendarItem) -> Bool {
        !item.id.isEmpty && item.id.count <= 4096 && !item.eventIdentifier.isEmpty && item.eventIdentifier.count <= 4096
            && !item.calendarIdentifier.isEmpty && item.calendarIdentifier.count <= 4096
            && item.title.count <= 4096 && item.notes.count <= 65_536 && item.location.count <= 4096
            && item.start.timeIntervalSinceReferenceDate.isFinite && item.end.timeIntervalSinceReferenceDate.isFinite
            && item.end > item.start && item.end.timeIntervalSince(item.start) <= 366 * 86400
    }
}

struct ArchivedCalendarMutation: Codable, Identifiable, Equatable {
    var id = UUID()
    var batchID: UUID
    var actionID: UUID
    var kind: CalendarMutationKind
    var original: CalendarEventBackup
    var after: CalendarItem?
    var afterBackup: CalendarEventBackup? = nil
    var status: CalendarArchiveStatus = .prepared
    var preparedAt: Date
    var committedAt: Date?
    var restoredAt: Date?
    var restoredEvent: CalendarItem?
    var linkedTravelBefore: CalendarCreationTravel? = nil
    var isValid: Bool {
        guard original.isValid, linkedTravelBefore?.isValid ?? true, preparedAt.timeIntervalSinceReferenceDate.isFinite,
              committedAt.map({ $0.timeIntervalSinceReferenceDate.isFinite && $0 >= preparedAt }) ?? true,
              restoredAt.map({ $0.timeIntervalSinceReferenceDate.isFinite && $0 >= preparedAt }) ?? true,
              after.map(CalendarEventBackup.valid) ?? true,
              afterBackup.map({ $0.isValid && $0.snapshot == after }) ?? true,
              restoredEvent.map(CalendarEventBackup.valid) ?? true else { return false }
        if kind == .delete && (after != nil || afterBackup != nil) { return false }
        if kind == .update && [.committed, .restorationPrepared, .restored].contains(status) && (after == nil || afterBackup == nil) { return false }
        if [.committed, .restorationPrepared, .restored].contains(status) && committedAt == nil { return false }
        if status == .restored { return restoredAt != nil && restoredEvent != nil }
        return restoredAt == nil && restoredEvent == nil
    }
}

/// A locally confirmed restore gets a new EventKit identity. Keep the original
/// logical ID without trusting URLs found in external calendars; otherwise a
/// restored lesson could be imported again as a new source of money.
struct CalendarRestorationLink: Codable, Identifiable, Equatable {
    var id = UUID()
    var archiveID: UUID
    var original: CalendarItem
    var restored: CalendarItem
    var isValid: Bool {
        CalendarEventBackup.valid(original) && CalendarEventBackup.valid(restored)
            && restored.recurring == false && restored.writable
            && (restored.eventIdentifier != original.eventIdentifier || restored.calendarIdentifier != original.calendarIdentifier)
    }
    func recognizes(_ current: CalendarItem) -> Bool {
        guard isValid, current.calendarIdentifier == restored.calendarIdentifier, current.recurring == false else { return false }
        if current.eventIdentifier == restored.eventIdentifier { return true }
        // EventKit's native identifier can change during synchronization. Only
        // an already captured external UID in this same calendar is a fallback.
        return restored.externalIdentifier != nil && restored.externalIdentifier == current.externalIdentifier
    }
}

enum CalendarArchive {
    /// Only a fresh attempt that is proven to have stopped before any external
    /// write may release the historical-import interlock. An older interrupted
    /// restore stays unresolved even if its next preflight is rejected.
    static func failedRestorationStatus(previous: CalendarArchiveStatus, stoppedBeforeWrite: Bool) -> CalendarArchiveStatus {
        previous == .committed && stoppedBeforeWrite ? .committed : .restorationPrepared
    }
    static func valid(_ data: AppData) -> Bool {
        let entries = data.calendarActionArchive ?? [], links = data.calendarRestorations ?? []
        guard entries.count <= 20_000 && links.count <= 20_000,
              Set(entries.map(\.id)).count == entries.count,
              Set(entries.map(\.actionID)).count == entries.count,
              entries.allSatisfy(\.isValid), Set(links.map(\.id)).count == links.count,
              Set(links.map { $0.restored.calendarIdentifier + "|" + $0.restored.eventIdentifier }).count == links.count,
              links.allSatisfy(\.isValid) else { return false }
        return links.allSatisfy { link in
            entries.contains { $0.id == link.archiveID && $0.status == .restored && $0.original.snapshot == link.original && $0.restoredEvent == link.restored }
        } && entries.filter { $0.kind == .delete && $0.status == .restored }.allSatisfy { entry in
            links.filter { $0.archiveID == entry.id }.count == 1
        }
    }
    static func logicalEvent(_ current: CalendarItem, data: AppData) -> CalendarItem {
        logicalEvents([current], data: data)[0]
    }
    static func logicalEvents(_ events: [CalendarItem], data: AppData) -> [CalendarItem] {
        let trusted = trustedLinks(data)
        let grouped = Dictionary(grouping: trusted) { $0.restored.calendarIdentifier + "|" + $0.restored.eventIdentifier }
        let external = Dictionary(grouping: trusted.filter { $0.restored.externalIdentifier != nil }) {
            $0.restored.calendarIdentifier + "|" + $0.restored.externalIdentifier!
        }
        return events.map { event in
            let native = grouped[event.calendarIdentifier + "|" + event.eventIdentifier] ?? []
            let byUID = event.externalIdentifier.flatMap { external[event.calendarIdentifier + "|" + $0] } ?? []
            let candidates = Dictionary((native + byUID).filter { $0.recognizes(event) }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let ids = Set(candidates.values.map { $0.original.id })
            guard ids.count == 1, let id = ids.first else { return event }
            var logical = event; logical.id = id; return logical
        }
    }
    private static func trustedLinks(_ data: AppData) -> [CalendarRestorationLink] {
        let archived = Dictionary((data.calendarActionArchive ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return (data.calendarRestorations ?? []).filter { link in
            guard link.isValid, let entry = archived[link.archiveID], entry.isValid, entry.kind == .delete else { return false }
            return entry.status == .restored && entry.original.snapshot == link.original && entry.restoredEvent == link.restored
        }
    }
    static func requiresIdentityReview(_ event: CalendarItem, data: AppData) -> Bool {
        let trusted = trustedLinks(data)
        if Set(trusted.filter { $0.recognizes(event) }.map { $0.original.id }).count > 1 { return true }
        return trusted.contains { link in
            let restored = link.restored
            return !link.recognizes(event) && event.calendarIdentifier == restored.calendarIdentifier
                && event.title == restored.title && CalendarSnapshotMatch.instant(event.start, restored.start) && CalendarSnapshotMatch.instant(event.end, restored.end)
                && event.location == restored.location && event.notes == restored.notes
        }
    }
}

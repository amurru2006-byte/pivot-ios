import Foundation

/// AppData's legacy ISO8601 codec stores whole seconds. Match the same SDK
/// revision with that encoding precision, without relaxing content or account
/// checks. Calendar display names/colors and derived kinds are not event edits.
enum CalendarSnapshotMatch {
    static func instant(_ a: Date, _ b: Date) -> Bool {
        a.timeIntervalSinceReferenceDate.isFinite && b.timeIntervalSinceReferenceDate.isFinite
            && abs(a.timeIntervalSince(b)) < 1
    }
    static func identity(_ a: CalendarItem, _ b: CalendarItem) -> Bool {
        guard a.calendarIdentifier == b.calendarIdentifier, a.sourceIdentifier == b.sourceIdentifier else { return false }
        guard a.recurring == b.recurring || (a.recurring != true && b.recurring != true) else { return false }
        if let first = a.externalIdentifier, let second = b.externalIdentifier, first != second { return false }
        if a.eventIdentifier == b.eventIdentifier { return true }
        guard a.externalIdentifier != nil, a.externalIdentifier == b.externalIdentifier else { return false }
        if a.recurring == false && b.recurring == false { return true }
        guard let first = a.occurrenceAnchor, let second = b.occurrenceAnchor else { return false }
        return instant(first, second)
    }
    static func revision(_ expected: CalendarItem, _ current: CalendarItem, requireModificationDate: Bool = true) -> Bool {
        identity(expected, current) && expected.writable && current.writable
            && expected.sourceIdentifier == current.sourceIdentifier
            && expected.title == current.title && expected.notes == current.notes && expected.location == current.location
            && expected.isAllDay == current.isAllDay && expected.recurring == current.recurring
            && instant(expected.start, current.start) && instant(expected.end, current.end)
            && (!requireModificationDate || CoachPlanner.modificationDateMatches(expected.calendarModifiedAt, current.calendarModifiedAt))
            && CoachPlanner.modificationDateMatches(expected.occurrenceAnchor, current.occurrenceAnchor)
    }
    static func alarm(_ a: CalendarAlarmBackup, _ b: CalendarAlarmBackup) -> Bool {
        a.isValid && b.isValid && CoachPlanner.modificationDateMatches(a.absoluteDate, b.absoluteDate)
            && a.relativeSeconds == b.relativeSeconds
    }
    static func backup(_ expected: CalendarEventBackup, _ current: CalendarEventBackup, requireModificationDate: Bool = true) -> Bool {
        expected.isValid && current.isValid && revision(expected.snapshot, current.snapshot, requireModificationDate: requireModificationDate)
            && expected.originalNotes == current.originalNotes && expected.url == current.url
            && expected.timeZoneIdentifier == current.timeZoneIdentifier && expected.availabilityRawValue == current.availabilityRawValue
            && expected.alarms.count == current.alarms.count && zip(expected.alarms, current.alarms).allSatisfy({ alarm($0.0, $0.1) })
    }
}

import Foundation

/// Local review metadata, never a provider DTO. The civil date is stable while
/// the floating EventKit boundaries depend on the device's default time zone.
struct CalendarCreationAllDay: Codable, Equatable {
    var day: String
    var nativeTimeZoneIdentifier: String

    var isValid: Bool {
        guard nativeTimeZoneIdentifier.count <= 128, let zone = TimeZone(identifier: nativeTimeZoneIdentifier),
              canonicalInterval != nil else { return false }
        return CoachDocumentCivilDay.interval(day, timeZone: zone) != nil
    }
    var canonicalInterval: DateInterval? { CoachDocumentCivilDay.interval(day) }
    func matches(_ draft: CoachCalendarDraft) -> Bool {
        guard isValid, let interval = canonicalInterval else { return false }
        return draft.start == interval.start && draft.end == interval.end && !draft.endEstimated
    }
    /// A changed device zone requires a new review, not an invisible shift.
    func nativeInterval(currentTimeZone: TimeZone) -> DateInterval? {
        guard isValid, currentTimeZone.identifier == nativeTimeZoneIdentifier else { return nil }
        return CoachDocumentCivilDay.interval(day, timeZone: currentTimeZone)
    }
    static func isCanonicalDay(start: Date, end: Date) -> Bool {
        guard start.timeIntervalSinceReferenceDate.isFinite, end.timeIntervalSinceReferenceDate.isFinite,
              let interval = CoachDocumentCivilDay.interval(PivotDate.key(start)) else { return false }
        return start == interval.start && end == interval.end
    }
    /// Converts *civil dates*, never elapsed seconds. Accept only native midnight
    /// boundaries; unexpected floating metadata remains an explicit failure.
    /// Supports external multi-day ranges for read-only conflict comparisons.
    static func normalizeNative(start: Date, end: Date, timeZone: TimeZone) -> DateInterval? {
        guard start.timeIntervalSinceReferenceDate.isFinite, end.timeIntervalSinceReferenceDate.isFinite, end > start else { return nil }
        var native = Calendar(identifier: .gregorian); native.timeZone = timeZone
        guard native.startOfDay(for: start) == start, native.startOfDay(for: end) == end,
              let count = native.dateComponents([.day], from: start, to: end).day, (1...366).contains(count) else { return nil }
        func key(_ value: Date) -> String? {
            let c = native.dateComponents([.year, .month, .day], from: value)
            guard let y = c.year, let m = c.month, let d = c.day else { return nil }
            return String(format: "%04d-%02d-%02d", y, m, d)
        }
        guard let firstKey = key(start), let endKey = key(end),
              let first = CoachDocumentCivilDay.interval(firstKey)?.start,
              let last = CoachDocumentCivilDay.interval(endKey)?.start, last > first else { return nil }
        return .init(start: first, end: last)
    }
}

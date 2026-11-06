import Foundation
import EventKit

/// Timing bridge only. It never requests access, looks up calendars or saves an
/// event. The existing worker retains all authorization and confirmation gates.
enum CalendarCreationNative {
    enum Failure: LocalizedError {
        case timing
        var errorDescription: String? { "Non riesco a verificare data e fuso dell’evento giornaliero. Nessun nuovo evento è stato salvato." }
    }
    static func query(parts: [CalendarCreationPart], options: CalendarCreationOptions,
                      nativeTimeZone: TimeZone, readOnly: Bool) throws -> DateInterval {
        guard options.isValid, (1...2).contains(parts.count),
              parts.allSatisfy({ $0.start.timeIntervalSinceReferenceDate.isFinite
                  && $0.end.timeIntervalSinceReferenceDate.isFinite && $0.end > $0.start }),
              let first = parts.first, let last = parts.last,
              last.end > first.start else { throw Failure.timing }
        guard let allDay = options.allDay else {
            guard parts.allSatisfy({ !$0.isAllDay }) else { throw Failure.timing }
            return .init(start: first.start, end: last.end)
        }
        guard parts.count == 1, first.isAllDay, !first.isTravel,
              allDay.canonicalInterval?.start == first.start,
              allDay.canonicalInterval?.end == first.end else { throw Failure.timing }
        // Reconciliation may read in a new zone. It cannot use this exception
        // to authorize another write with stale review metadata.
        let interval = readOnly ? CoachDocumentCivilDay.interval(allDay.day, timeZone: nativeTimeZone)
            : allDay.nativeInterval(currentTimeZone: nativeTimeZone)
        guard let interval else { throw Failure.timing }
        return interval
    }
    static func interval(_ event: EKEvent, nativeTimeZone: TimeZone, normalizeFloating: Bool) throws -> DateInterval {
        guard let start = event.startDate, let end = event.endDate,
              start.timeIntervalSinceReferenceDate.isFinite, end.timeIntervalSinceReferenceDate.isFinite,
              end > start else { throw Failure.timing }
        if event.isAllDay && normalizeFloating {
            return try floatingInterval(start: start, end: end, nativeTimeZone: nativeTimeZone)
        }
        return .init(start: start, end: end)
    }
    /// Validate the exact dates returned by EventKit, without using its setters
    /// to manufacture malformed test values (the setters normalize those).
    static func floatingInterval(start: Date, end: Date, nativeTimeZone: TimeZone) throws -> DateInterval {
        guard start.timeIntervalSinceReferenceDate.isFinite, end.timeIntervalSinceReferenceDate.isFinite,
              end > start else { throw Failure.timing }
        // EventKit may expose the last included day's final second. Keep
        // that representation at this boundary: Core uses exclusive civil
        // midnights. Accept only the exact endpoint, never a rounded time.
        var native = Calendar(identifier: .gregorian); native.timeZone = nativeTimeZone
        let exclusiveEnd: Date
        if native.startOfDay(for: end) == end {
            exclusiveEnd = end
        } else if let day = native.dateInterval(of: .day, for: end),
                  end == day.end.addingTimeInterval(-1) {
            exclusiveEnd = day.end
        } else { throw Failure.timing }
        guard let result = CalendarCreationAllDay.normalizeNative(start: start, end: exclusiveEnd, timeZone: nativeTimeZone) else { throw Failure.timing }
        return result
    }
    /// Mutates only the supplied in-memory EKEvent. No EventKit commit occurs.
    static func assign(_ part: CalendarCreationPart, options: CalendarCreationOptions,
                       to event: EKEvent, nativeTimeZone: TimeZone) throws {
        guard options.isValid else { throw Failure.timing }
        let dates: DateInterval
        if part.isAllDay {
            dates = try query(parts: [part], options: options, nativeTimeZone: nativeTimeZone, readOnly: false)
        } else {
            guard options.allDay == nil, part.start.timeIntervalSinceReferenceDate.isFinite,
                  part.end.timeIntervalSinceReferenceDate.isFinite, part.end > part.start else { throw Failure.timing }
            dates = .init(start: part.start, end: part.end)
        }
        event.isAllDay = part.isAllDay
        event.timeZone = part.isAllDay ? nil : PivotDate.calendar.timeZone
        event.startDate = dates.start
        // An all-day end selects its included civil day. Supplying the next
        // midnight makes EventKit include an extra day on the tested SDK.
        // Subtract only the final second, not a fixed-length civil day.
        event.endDate = part.isAllDay ? dates.end.addingTimeInterval(-1) : dates.end
    }
}

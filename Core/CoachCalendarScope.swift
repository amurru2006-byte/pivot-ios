import Foundation

/// Explicit on-device disclosure scope. It is not an instruction or a raw
/// calendar identifier supplied by the model, and does not enlarge token limits.
enum CoachCalendarScope: String, CaseIterable, Identifiable {
    case today, week
    var id: String { rawValue }
    var label: String { self == .today ? "Oggi" : "Prossimi 7 giorni" }
    func contains(_ item: CalendarItem, now: Date) -> Bool {
        guard now.timeIntervalSince1970.isFinite else { return false }
        let start = PivotDate.calendar.startOfDay(for: now)
        guard let end = PivotDate.calendar.date(byAdding: .day, value: self == .today ? 1 : 7, to: start) else { return false }
        return !item.isAllDay && item.start < end && item.end > start
    }
}

import Foundation

/// Local contact visibility only. No effect on receipts, arrears or annual totals.
struct ClientActivityState: Codable, Equatable {
    var inactive = false
    var manuallyInactive = false
    var firstObservedAt: Date
    var activatedAt: Date? = nil
    var lastCalendarActivityAt: Date? = nil

    var isValid: Bool {
        [firstObservedAt, activatedAt, lastCalendarActivityAt].compactMap { $0 }
            .allSatisfy { $0.timeIntervalSinceReferenceDate.isFinite }
            && (!manuallyInactive || inactive)
    }
}

/// An explicit scan, never the much shorter home-agenda window. Only an
/// authorized, complete and current scan can establish absence within its range.
struct ClientCalendarActivity: Equatable {
    var observedAt: Date
    var from: Date
    var through: Date
    var complete: Bool
    var items: [CalendarItem]

    func isCurrent(at now: Date) -> Bool {
        [now, observedAt, from, through].allSatisfy { $0.timeIntervalSinceReferenceDate.isFinite }
            && from < through && observedAt <= now && now.timeIntervalSince(observedAt) <= 900
    }

    func canDeactivate(at now: Date) -> Bool {
        guard let requiredFrom = PivotDate.calendar.date(byAdding: .day, value: -ClientActivity.inactivityDays, to: now),
              let requiredThrough = PivotDate.calendar.date(byAdding: .year, value: 4, to: now) else { return false }
        return complete && isCurrent(at: now)
            && from <= requiredFrom && through >= requiredThrough
    }
}

enum ClientActivity {
    static let inactivityDays = 90
    enum Failure: Error, Equatable { case missing, calendarNotVerified, futureAppointment }

    static func matching(_ scan: ClientCalendarActivity?, clients: [Client], data: AppData) -> [UUID: [CalendarItem]] {
        var result: [UUID: [CalendarItem]] = [:]
        for item in scan?.items ?? [] where item.end > item.start {
            guard data.records[item.id]?.status != .skipped,
                  let client = StudentRecognition.recognize(title: item.title, clients: clients).client else { continue }
            result[client.id, default: []].append(item)
        }
        return result
    }

    static func nextAppointment(clientID: UUID, data: AppData, scan: ClientCalendarActivity?, now: Date) -> CalendarItem? {
        guard scan?.isCurrent(at: now) == true else { return nil }
        return matching(scan, clients: data.clients, data: data)[clientID]?
            .filter { $0.end > now }.min { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }

    static func nextAppointments(data: AppData, scan: ClientCalendarActivity?, now: Date) -> [UUID: CalendarItem] {
        guard scan?.isCurrent(at: now) == true else { return [:] }
        return matching(scan, clients: data.clients, data: data).compactMapValues { items in
            items.filter { $0.end > now }.min { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
        }
    }

    static func lastActivity(clientID: UUID, data: AppData, now: Date) -> Date? {
        activityDates(data: data, now: now)[clientID]
    }

    private static func activityDates(data: AppData, now: Date) -> [UUID: Date] {
        var result: [UUID: Date] = [:], owners: [UUID: UUID] = [:]
        func remember(_ date: Date?, _ clientID: UUID) {
            guard let date, date.timeIntervalSinceReferenceDate.isFinite, date <= now else { return }
            result[clientID] = max(result[clientID] ?? .distantPast, date)
        }
        for client in data.clients { remember(client.activityState?.lastCalendarActivityAt, client.id) }
        for entry in data.income { owners[entry.id] = entry.clientID; remember(entry.date, entry.clientID) }
        for payment in data.payments {
            if let id = owners[payment.incomeID] { remember(payment.date, id) }
        }
        return result
    }

    static func refreshed(data: AppData, scan: ClientCalendarActivity?, now: Date) -> [Client] {
        let matches = matching(scan?.isCurrent(at: now) == true ? scan : nil, clients: data.clients, data: data)
        let dates = activityDates(data: data, now: now)
        return data.clients.map { client in
            var client = client
            var state = client.activityState ?? .init(firstObservedAt: now)
            let events = matches[client.id] ?? []
            if let last = events.filter({ $0.end <= now }).map(\.end).max() {
                state.lastCalendarActivityAt = max(state.lastCalendarActivityAt ?? .distantPast, last)
            }
            let future = events.contains { $0.end > now }
            if future {
                state.inactive = false; state.manuallyInactive = false
            } else if !state.manuallyInactive {
                // Updating a tariff, importing an old year, or toggling the
                // control must not become the sorting date of a real activity.
                let last = max(dates[client.id] ?? state.firstObservedAt,
                               state.lastCalendarActivityAt ?? .distantPast)
                let anchor = max(last, state.activatedAt ?? .distantPast)
                let cutoff = PivotDate.calendar.date(byAdding: .day, value: -inactivityDays, to: now)!
                if anchor > cutoff { state.inactive = false }
                else if scan?.canDeactivate(at: now) == true { state.inactive = true }
            }
            client.activityState = state
            return client
        }
    }

    static func setActive(_ active: Bool, clientID: UUID, data: inout AppData,
                          scan: ClientCalendarActivity?, now: Date) throws {
        guard let index = data.clients.firstIndex(where: { $0.id == clientID }) else { throw Failure.missing }
        if !active {
            if nextAppointment(clientID: clientID, data: data, scan: scan, now: now) != nil { throw Failure.futureAppointment }
            guard scan?.canDeactivate(at: now) == true else { throw Failure.calendarNotVerified }
        }
        var state = data.clients[index].activityState ?? .init(firstObservedAt: now)
        state.inactive = !active; state.manuallyInactive = !active
        if active { state.activatedAt = now }
        data.clients[index].activityState = state
    }

    static func sorted(_ clients: [Client], data: AppData, now: Date) -> [Client] {
        let dates = activityDates(data: data, now: now)
        return clients.sorted { lhs, rhs in
            let a = dates[lhs.id] ?? .distantPast
            let b = dates[rhs.id] ?? .distantPast
            if a != b { return a > b }
            let an = EventCoalescer.normalized(lhs.name), bn = EventCoalescer.normalized(rhs.name)
            return an == bn ? lhs.id.uuidString < rhs.id.uuidString : an < bn
        }
    }
}

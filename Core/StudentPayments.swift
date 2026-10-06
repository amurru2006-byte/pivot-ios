import Foundation

enum PaymentCadence: String, Codable, CaseIterable {
    case everyLesson, weekly
    var label: String { self == .weekly ? "A fine settimana" : "A ogni lezione" }
    var timing: PaymentTiming { self == .weekly ? .weekly : .everyLesson }
}
enum PaymentTiming: String, Codable, CaseIterable {
    case everyLesson, weekly, nextLesson, chosenDate
    var label: String {
        switch self {
        case .everyLesson: return "A ogni lezione"
        case .weekly: return "All’ultima lezione della settimana"
        case .nextLesson: return "Alla prossima lezione"
        case .chosenDate: return "In una data che scelgo"
        }
    }
    var cadence: PaymentCadence? {
        switch self { case .everyLesson: return .everyLesson; case .weekly: return .weekly; default: return nil }
    }
}
struct PaymentDue: Identifiable, Equatable {
    var id: String
    var clientID: UUID
    var clientName: String
    var entryIDs: [UUID]
    var amountCents: Int
    var date: Date?
    var timing: PaymentTiming
    func isOverdue(at now: Date) -> Bool { date.map { $0 < now } ?? false }
}

enum StudentPayments {
    // Weeks are Monday–Sunday in Europe/Rome, independent of the device locale.
    static func week(containing date: Date) -> DateInterval {
        var calendar = Calendar(identifier: .iso8601); calendar.timeZone = PivotDate.calendar.timeZone
        return calendar.dateInterval(of: .weekOfYear, for: date)!
    }
    static func timing(for entry: IncomeEntry, data: AppData) -> PaymentTiming {
        entry.paymentTiming ?? data.clients.first { $0.id == entry.clientID }?.paymentCadence?.timing ?? .everyLesson
    }
    static func dues(planned events: [CalendarItem], data: AppData) -> [PaymentDue] {
        let unpaid = data.income.filter { $0.outstandingCents > 0 }
        guard !unpaid.isEmpty else { return [] }
        let knownPeople = Dictionary(data.income.compactMap { entry in entry.calendarEventID.map { ($0, entry.clientID) } }, uniquingKeysWith: { first, _ in first })
        let eventsByID = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var lessonsByClient: [UUID: [CalendarItem]] = [:]
        for event in events where [.tutoring, .work].contains(event.kind) && !event.isAllDay && data.records[event.id]?.status != .skipped {
            let clientID = knownPeople[event.id] ?? StudentRecognition.recognize(title: event.title, clients: data.clients).client?.id
            if let clientID { lessonsByClient[clientID, default: []].append(event) }
        }
        var groups: [String: PaymentDue] = [:]
        for entry in unpaid.sorted(by: { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }) {
            let timing = timing(for: entry, data: data)
            let lessons = lessonsByClient[entry.clientID] ?? []
            let recorded = entry.calendarEventID.flatMap { data.records[$0] }
            let lessonStart = recorded?.actualStart ?? recorded?.snapshot.start ?? entry.calendarEventID.flatMap { eventsByID[$0]?.start } ?? entry.date
            let interval = week(containing: lessonStart)
            let due: Date?
            let anchor: String
            switch timing {
            case .everyLesson:
                due = entry.date; anchor = PivotDate.key(entry.date)
            case .weekly:
                // Calendar edits/cancellations can change the last lesson. No reminder
                // is due at the earlier lessons simply because they remain unpaid.
                let last = lessons.filter { $0.start >= interval.start && $0.start < interval.end }.map(\.end).max()
                // No invented lesson/deadline if the calendar isn't available yet.
                due = last.map { max(entry.date, $0) }; anchor = PivotDate.key(interval.start)
            case .nextLesson:
                due = lessons.filter { $0.id != entry.calendarEventID && $0.start >= (entry.paymentDeferralAfter ?? entry.date) }.min { $0.start < $1.start }?.end
                anchor = due.map(PivotDate.key) ?? entry.id.uuidString
            case .chosenDate:
                due = entry.promisedPaymentDate; anchor = due.map(PivotDate.key) ?? entry.id.uuidString
            }
            let key = entry.clientID.uuidString + "|" + timing.rawValue + "|" + anchor
            if var group = groups[key] {
                group.entryIDs.append(entry.id); group.amountCents += entry.outstandingCents
                if let due { group.date = max(group.date ?? due, due) }
                groups[key] = group
            } else {
                groups[key] = PaymentDue(id: key, clientID: entry.clientID, clientName: entry.clientName, entryIDs: [entry.id], amountCents: entry.outstandingCents, date: due, timing: timing)
            }
        }
        return groups.values.sorted { ($0.date ?? .distantFuture) == ($1.date ?? .distantFuture) ? $0.id < $1.id : ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }
    static func balance(clientID: UUID, data: AppData) -> Int {
        data.income.filter { $0.clientID == clientID }.reduce(0) { $0 + $1.outstandingCents }
    }
    // A single real receipt can settle several lessons, oldest first. There is
    // no synthetic money, overpayment or implicit "paid" at a promised date.
    @discardableResult static func collect(clientID: UUID, cents: Int, date: Date, data: inout AppData) -> Bool {
        guard cents > 0, cents <= balance(clientID: clientID, data: data) else { return false }
        let ids = data.income.filter { $0.clientID == clientID && $0.outstandingCents > 0 }
            .sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }.map(\.id)
        var remaining = cents
        for id in ids {
            guard remaining > 0, let index = data.income.firstIndex(where: { $0.id == id }) else { break }
            let paid = min(remaining, data.income[index].outstandingCents)
            data.income[index].paidCents += paid; remaining -= paid
            data.payments.append(.init(incomeID: id, clientName: data.income[index].clientName, date: date, amountCents: paid))
        }
        return remaining == 0
    }
    static func remember(_ timing: PaymentTiming, for clientID: UUID, data: inout AppData) {
        guard let cadence = timing.cadence, let index = data.clients.firstIndex(where: { $0.id == clientID }) else { return }
        data.clients[index].paymentCadence = cadence
    }
}

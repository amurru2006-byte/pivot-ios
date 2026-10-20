import Foundation

/// A saved review schedule, not permission to move money or write a calendar.
/// Notification and calendar activation must be confirmed on this device.
struct SavingsWeeklyPlan: Codable, Equatable {
    var weekday = 1 // Foundation weekday: Sunday = 1.
    var hour = 20
    var minute = 0
    var reservePercent = 100

    var isValid: Bool {
        (1...7).contains(weekday) && (0...23).contains(hour)
            && (0...59).contains(minute) && (0...100).contains(reservePercent)
    }
    func nextReview(after now: Date) -> Date? {
        guard isValid, now.timeIntervalSinceReferenceDate.isFinite else { return nil }
        return PivotDate.calendar.nextDate(after: now,
            matching: DateComponents(hour: hour, minute: minute, second: 0, weekday: weekday),
            matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
    }
}

/// End-of-week suggestions use money actually received, not the future income
/// forecast. A suggestion never modifies receipts, expenses or reservations.
struct SavingsWeeklyReview: Equatable {
    enum Issue: String, Equatable {
        case verifyRecentData, receiptsNotConfirmed, expensesNotConfirmed, unknownReceiptDates, underfunded
    }
    var weekStart: Date
    var verifiedThrough: Date?
    var nextReview: Date
    var receivedCents: Int
    var spentCents: Int
    var alreadyReservedCents: Int
    var remainingCents: Int
    var freeCents: Int
    var proposedCents: Int?
    var issues: [Issue]

    static func make(goalID: UUID, data: AppData, now: Date) throws -> Self {
        guard now.timeIntervalSinceReferenceDate.isFinite,
              let budget = data.savingsBudget,
              let goal = budget.goals.first(where: { $0.id == goalID && !$0.archived }),
              let plan = goal.weeklyPlan, plan.isValid, let next = plan.nextReview(after: now),
              Set(data.clients.map(\.id)).count == data.clients.count,
              Set(data.income.map(\.id)).count == data.income.count,
              data.income.allSatisfy({ $0.date.timeIntervalSinceReferenceDate.isFinite }),
              budget.expenses.allSatisfy({ $0.date.timeIntervalSinceReferenceDate.isFinite }),
              budget.allocations.allSatisfy({ $0.date.timeIntervalSinceReferenceDate.isFinite }) else { throw SavingsBudgetError.invalidData }
        let balance = try SavingsAccounting.balance(budget, payments: data.payments)
        let reserved = try SavingsAccounting.reserved(for: goalID, in: budget)
        let start = StudentPayments.week(containing: now).start
        var result = Self(weekStart: start, verifiedThrough: nil, nextReview: next, receivedCents: 0,
            spentCents: 0, alreadyReservedCents: 0, remainingCents: max(0, goal.targetCents - reserved),
            freeCents: balance.freeCents, proposedCents: nil, issues: [])
        if balance.shortfallCents > 0 { result.issues.append(.underfunded); return result }
        if result.remainingCents == 0 { result.proposedCents = 0; return result }
        guard let coverage = data.incomeObservationCoverage, coverage.isValid,
              coverage.from <= start, coverage.through <= now,
              PivotDate.calendar.isDate(coverage.through, inSameDayAs: now) else {
            result.issues.append(.verifyRecentData); return result
        }
        result.verifiedThrough = coverage.through
        if !coverage.receiptsConfirmed { result.issues.append(.receiptsNotConfirmed) }
        if !coverage.expensesConfirmed { result.issues.append(.expensesNotConfirmed) }
        let cutoff = coverage.through
        func isThisWeek(_ date: Date) -> Bool { date >= start && date <= cutoff }
        let clients = Set(data.clients.filter {
            $0.activityState?.inactive != true && $0.participatesInOrdinaryForecast
        }.map(\.id))
        let entries = Dictionary(uniqueKeysWithValues: data.income.filter {
            clients.contains($0.clientID) && [.lesson, .work].contains($0.activityKind)
        }.map { ($0.id, $0) })
        func add(_ a: Int, _ b: Int) throws -> Int {
            let (sum, overflow) = a.addingReportingOverflow(b)
            guard !overflow, (-OrdinaryIncomePreparation.maximumWeeklyCents...OrdinaryIncomePreparation.maximumWeeklyCents).contains(sum) else {
                throw SavingsBudgetError.invalidData
            }
            return sum
        }
        for payment in data.payments where payment.excludedFromBudget != true {
            guard let entry = entries[payment.incomeID] else { continue }
            if let date = payment.date, entry.historicalSource?.paymentDateAssumed != true {
                guard date.timeIntervalSinceReferenceDate.isFinite else { throw SavingsBudgetError.invalidData }
                if isThisWeek(date) { result.receivedCents = try add(result.receivedCents, payment.amountCents) }
            } else if isThisWeek(entry.date), !result.issues.contains(.unknownReceiptDates) {
                result.issues.append(.unknownReceiptDates)
            }
        }
        let receiptsByEntry = Dictionary(grouping: data.payments, by: \.incomeID)
        for entry in entries.values where isThisWeek(entry.date) {
            let total = try (receiptsByEntry[entry.id] ?? []).reduce(0) { try add($0, $1.amountCents) }
            if total != entry.paidCents, !result.issues.contains(.unknownReceiptDates) {
                result.issues.append(.unknownReceiptDates)
            }
        }
        for expense in budget.expenses where expense.voided != true && isThisWeek(expense.date) {
            result.spentCents = try add(result.spentCents, expense.amountCents)
        }
        for allocation in budget.allocations where allocation.goalID == goalID && isThisWeek(allocation.date) {
            result.alreadyReservedCents = try add(result.alreadyReservedCents, allocation.cents)
        }
        guard result.issues.isEmpty else { return result }
        let margin = max(0, result.receivedCents - result.spentCents)
        let proposed = max(0, margin * plan.reservePercent / 100 - max(0, result.alreadyReservedCents))
        result.proposedCents = min(proposed, result.freeCents, result.remainingCents)
        return result
    }
}

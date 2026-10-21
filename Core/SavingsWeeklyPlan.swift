import Foundation

enum SavingsWeeklyMode: String, Codable { case manual, automatic }

/// Only local bookkeeping. It cannot transfer money between bank accounts.
struct SavingsWeeklyPlan: Codable, Equatable {
    var weekday = 1 // Foundation weekday: Sunday = 1.
    var hour = 20
    var minute = 0
    var reservePercent = 100
    var mode: SavingsWeeklyMode? = nil
    var activatedAt: Date? = nil
    var notificationsEnabled: Bool? = nil

    var isValid: Bool {
        (1...7).contains(weekday) && (0...23).contains(hour)
            && (0...59).contains(minute) && (0...100).contains(reservePercent)
            && (activatedAt?.timeIntervalSinceReferenceDate.isFinite ?? true)
    }
    func nextReview(after now: Date) -> Date? {
        guard isValid, now.timeIntervalSinceReferenceDate.isFinite else { return nil }
        return PivotDate.calendar.nextDate(after: now,
            matching: DateComponents(hour: hour, minute: minute, second: 0, weekday: weekday),
            matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
    }
    func previousReview(before date: Date) -> Date? {
        guard isValid, date.timeIntervalSinceReferenceDate.isFinite else { return nil }
        return PivotDate.calendar.nextDate(after: date,
            matching: DateComponents(hour: hour, minute: minute, second: 0, weekday: weekday),
            matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .backward)
    }
    func latestDue(at now: Date) -> Date? {
        guard let activatedAt, let first = nextReview(after: activatedAt),
              let due = previousReview(before: now.addingTimeInterval(0.001)), due >= first, due <= now else { return nil }
        return due
    }
    var requiringDeviceActivation: Self {
        var copy = self; copy.activatedAt = nil; copy.notificationsEnabled = false
        return copy
    }
}

struct SavingsWeeklyReceipt: Codable, Equatable {
    var periodStart: Date
    var periodEnd: Date
    var automatic: Bool
    var isValid: Bool {
        periodStart.timeIntervalSinceReferenceDate.isFinite && periodEnd.timeIntervalSinceReferenceDate.isFinite
            && periodStart < periodEnd && periodEnd.timeIntervalSince(periodStart) <= 8 * 86400
    }
}

/// End-of-week suggestions use money actually received, not the future income
/// forecast. A suggestion never modifies receipts, expenses or reservations.
struct SavingsWeeklyReview: Equatable {
    enum Issue: String, Equatable {
        case verifyRecentData, receiptsNotConfirmed, expensesNotConfirmed, unknownReceiptDates, underfunded
    }
    var weekStart: Date
    var periodEnd: Date
    var verifiedThrough: Date?
    var nextReview: Date
    var receivedCents: Int
    var spentCents: Int
    var alreadyReservedCents: Int
    var remainingCents: Int
    var freeCents: Int
    var proposedCents: Int?
    var issues: [Issue]

    static func make(goalID: UUID, data: AppData, now: Date, periodEnd: Date? = nil) throws -> Self {
        let end = periodEnd ?? min(now, data.incomeObservationCoverage?.through ?? now)
        guard now.timeIntervalSinceReferenceDate.isFinite,
              end.timeIntervalSinceReferenceDate.isFinite, end <= now,
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
        guard let start = plan.previousReview(before: end) else { throw SavingsBudgetError.invalidData }
        var result = Self(weekStart: start, periodEnd: end, verifiedThrough: nil, nextReview: next, receivedCents: 0,
            spentCents: 0, alreadyReservedCents: 0, remainingCents: max(0, goal.targetCents - reserved),
            freeCents: balance.freeCents, proposedCents: nil, issues: [])
        if balance.shortfallCents > 0 { result.issues.append(.underfunded); return result }
        if result.remainingCents == 0 { result.proposedCents = 0; return result }
        guard let coverage = data.incomeObservationCoverage, coverage.isValid,
              coverage.from <= start, coverage.through <= now,
              PivotDate.calendar.isDate(coverage.through, inSameDayAs: now), coverage.through >= end else {
            result.issues.append(.verifyRecentData); return result
        }
        result.verifiedThrough = coverage.through
        if !coverage.receiptsConfirmed { result.issues.append(.receiptsNotConfirmed) }
        if !coverage.expensesConfirmed { result.issues.append(.expensesNotConfirmed) }
        let cutoff = min(coverage.through, end)
        func isThisWeek(_ date: Date) -> Bool { date > start && date <= cutoff }
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
        // The same week's cash cannot feed several goals twice. Existing
        // allocations to any goal consume that shared, already saved margin.
        for allocation in budget.allocations where isThisWeek(allocation.weeklyReview?.periodEnd ?? allocation.date) {
            result.alreadyReservedCents = try add(result.alreadyReservedCents, allocation.cents)
        }
        guard result.issues.isEmpty else { return result }
        let margin = max(0, result.receivedCents - result.spentCents)
        let proposed = max(0, margin * plan.reservePercent / 100 - max(0, result.alreadyReservedCents))
        result.proposedCents = min(proposed, result.freeCents, result.remainingCents, SavingsAccounting.maximumMovementCents)
        return result
    }
}

enum SavingsWeeklyAutomation {
    static func reviewEnd(goal: SavingsGoal, budget: SavingsBudget, now: Date) -> Date? {
        if let due = goal.weeklyPlan?.latestDue(at: now),
           !budget.allocations.contains(where: { $0.goalID == goal.id && $0.weeklyReview?.periodEnd == due }) { return due }
        return nil
    }
    /// Recompute against the current ledger and commit allocation + provenance
    /// atomically. A repeated refresh, restart or tap cannot process a due twice.
    @discardableResult static func apply(goalID: UUID, expected: SavingsWeeklyReview, automatic: Bool,
                                        now: Date, data: inout AppData) throws -> Bool {
        guard let budget = data.savingsBudget,
              let goal = budget.goals.first(where: { $0.id == goalID && !$0.archived }),
              let plan = goal.weeklyPlan else { throw SavingsBudgetError.missingGoal }
        if budget.allocations.contains(where: { $0.goalID == goalID && $0.weeklyReview?.periodEnd == expected.periodEnd }) { return false }
        if automatic {
            guard plan.mode == .automatic, plan.latestDue(at: now) == expected.periodEnd else { return false }
        }
        let fresh = try SavingsWeeklyReview.make(goalID: goalID, data: data, now: now, periodEnd: expected.periodEnd)
        guard fresh == expected else { throw SavingsBudgetError.conflict }
        guard let amount = fresh.proposedCents, amount > 0 else { return false }
        var copy = data
        let operation = UUID()
        try SavingsAccounting.reserve(amount, goalID: goalID, operationID: operation, at: now, data: &copy)
        guard let index = copy.savingsBudget?.allocations.firstIndex(where: { $0.id == operation }) else { throw SavingsBudgetError.invalidData }
        copy.savingsBudget?.allocations[index].weeklyReview = .init(periodStart: fresh.weekStart, periodEnd: fresh.periodEnd, automatic: automatic)
        try SavingsAccounting.validate(copy.savingsBudget!)
        data = copy
        return true
    }
    @discardableResult static func applyDue(now: Date, data: inout AppData) throws -> Int {
        var copy = data, count = 0
        for goal in copy.savingsBudget?.goals ?? [] where !goal.archived && goal.weeklyPlan?.mode == .automatic {
            guard let due = goal.weeklyPlan?.latestDue(at: now) else { continue }
            let review = try SavingsWeeklyReview.make(goalID: goal.id, data: copy, now: now, periodEnd: due)
            if try apply(goalID: goal.id, expected: review, automatic: true, now: now, data: &copy) { count += 1 }
        }
        if count > 0 { data = copy }
        return count
    }
}

struct SavingsWeeklyNotification: Equatable {
    var goalID: UUID
    var weekday: Int
    var hour: Int
    var minute: Int
    var id: String { "savings-weekly-" + goalID.uuidString }
    static func make(data: AppData) -> [Self] {
        guard let budget = data.savingsBudget, (try? SavingsAccounting.balance(budget, payments: data.payments)) != nil else { return [] }
        return budget.goals.compactMap { goal in
            guard !goal.archived, let plan = goal.weeklyPlan, plan.isValid, plan.activatedAt != nil,
                  plan.notificationsEnabled == true,
                  let reserved = try? SavingsAccounting.reserved(for: goal.id, in: budget), reserved < goal.targetCents else { return nil }
            return .init(goalID: goal.id, weekday: plan.weekday, hour: plan.hour, minute: plan.minute)
        }
    }
}

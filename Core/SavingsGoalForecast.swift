import Foundation

/// A user's hypothetical saving cadence, not an income prediction, balance
/// mutation, receipt, reservation or promise of future work.
struct SavingsGoalForecast: Equatable {
    var reservedCents: Int
    var freeCents: Int
    var hypotheticalUpfrontCents: Int
    var remainingCents: Int
    var weeklyCents: Int
    var weeksNeeded: Int?
    var completionDate: Date?
    var contributionsBeforeDeadline: Int?
    var requiredWeeklyCents: Int?
    var deadlineMissed: Bool

    static func make(goalID: UUID, data: AppData, upfrontCents: Int, weeklyCents: Int, now: Date) -> Self? {
        guard now.timeIntervalSinceReferenceDate.isFinite,
              let budget = data.savingsBudget,
              let goal = budget.goals.first(where: { $0.id == goalID && !$0.archived }),
              let balance = try? SavingsAccounting.balance(budget, payments: data.payments), balance.shortfallCents == 0,
              let reserved = try? SavingsAccounting.reserved(for: goal.id, in: budget),
              (0...SavingsAccounting.maximumMovementCents).contains(weeklyCents),
              upfrontCents >= 0 && upfrontCents <= min(balance.freeCents, goal.targetCents - reserved),
              goal.deadline.map({ $0.timeIntervalSinceReferenceDate.isFinite }) ?? true else { return nil }
        let remaining = max(0, goal.targetCents - reserved - upfrontCents)
        let weeks: Int? = remaining == 0 ? 0 : (weeklyCents > 0 ? quotientUp(remaining, by: weeklyCents) : nil)
        // Avoid an overflow or misleading date millions of years into the future.
        let completion = weeks.flatMap { value in
            value <= 5200 ? PivotDate.calendar.date(byAdding: .weekOfYear, value: value, to: now) : nil
        }
        let periods: Int? = goal.deadline.flatMap { deadline in
            guard deadline > now else { return 0 }
            guard deadline.timeIntervalSince(now) <= 366 * 100 * 86400 else { return nil }
            return max(0, PivotDate.calendar.dateComponents([.weekOfYear], from: now, to: deadline).weekOfYear ?? 0)
        }
        let required = periods.flatMap { $0 > 0 ? quotientUp(remaining, by: $0) : nil }
        return .init(reservedCents: reserved, freeCents: balance.freeCents, hypotheticalUpfrontCents: upfrontCents,
                     remainingCents: remaining, weeklyCents: weeklyCents, weeksNeeded: weeks, completionDate: completion,
                     contributionsBeforeDeadline: periods, requiredWeeklyCents: required,
                     deadlineMissed: goal.deadline.map { $0 < now && remaining > 0 } ?? false)
    }
    private static func quotientUp(_ value: Int, by divisor: Int) -> Int {
        value / divisor + (value % divisor == 0 ? 0 : 1)
    }
}

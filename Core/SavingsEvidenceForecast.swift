import Foundation

/// Read-only, local scenarios. Earned work, dated cash receipts and spending
/// are different series. A complete calendar alone cannot prove cash timing
/// or expenses. No forecast is added to the available balance or reserved.
struct SavingsEvidenceForecast: Equatable {
    enum Limitation: String, Equatable {
        case receiptsNotConfirmed, unknownReceiptDates, expensesNotConfirmed, provisional
    }
    struct Week: Equatable {
        var start: Date
        var savingCents: Int
        var lowerScenarioCents: Int?
        var upperScenarioCents: Int?
    }
    var income: OrdinaryIncomeProjection
    var cash: OrdinaryIncomeProjection?
    var spending: OrdinaryIncomeProjection?
    var limitations: [Limitation]
    var weeks: [Week]
    var remainingCents: Int
    var completionDate: Date?
    var slowerScenarioDate: Date?
    var fasterScenarioDate: Date?
    var deadline: Date?
    var projectedBeforeDeadlineCents: Int?
    var reservePercent: Int

    static func make(goalID: UUID, data: AppData, observations: OrdinaryIncomeObservations,
                     upfrontCents: Int, reservePercent: Int, now: Date, horizon: Int = 52) throws -> Self {
        guard (1...103).contains(horizon), (0...100).contains(reservePercent),
              let scenario = SavingsGoalForecast.make(goalID: goalID, data: data, upfrontCents: upfrontCents,
                                                       weeklyCents: 0, now: now),
              let goal = data.savingsBudget?.goals.first(where: { $0.id == goalID && !$0.archived }) else {
            throw IncomeProjectionError.invalidData
        }
        let income = try OrdinaryIncomeProjection.make(observations, now: now, horizon: horizon + 1)
        var limitations: [Limitation] = []
        if !observations.receiptsComplete { limitations.append(.receiptsNotConfirmed) }
        if observations.unknownPaymentDates > 0 { limitations.append(.unknownReceiptDates) }
        if !observations.expensesComplete { limitations.append(.expensesNotConfirmed) }
        func series(_ key: KeyPath<OrdinaryIncomeWeek, Int>) throws -> OrdinaryIncomeProjection {
            var copy = observations
            copy.weeks = observations.weeks.map { week in
                .init(start: week.start, earnedCents: week[keyPath: key])
            }
            return try OrdinaryIncomeProjection.make(copy, now: now, horizon: horizon + 1)
        }
        let cash = observations.receiptsComplete && observations.unknownPaymentDates == 0 ? try series(\.knownCashCents) : nil
        let spending = observations.expensesComplete ? try series(\.knownSpentCents) : nil
        if income.provisional || cash?.provisional == true || spending?.provisional == true { limitations.append(.provisional) }
        var weeks: [Week] = []
        func portion(_ received: Int, _ spent: Int) -> Int {
            // Valid series are capped at 10^12 cents. Multiplication by <=100
            // remains safe on all supported iPhone architectures.
            // Keep negative margins: clamping each week to zero would erase
            // expensive weeks and make a later contribution appear affordable.
            (received - spent) * reservePercent / 100
        }
        if let cash, let spending {
            // Element zero is a NOWCAST for the current, partly elapsed week.
            // Never add it to funds already received/reserved. Start with the
            // next full Monday week and date contributions at its close.
            weeks = zip(cash.weeks.dropFirst(), spending.weeks.dropFirst()).map { received, spent in
                let lower = received.lowerScenarioCents.flatMap { a in spent.upperScenarioCents.map { portion(a, $0) } }
                let upper = received.upperScenarioCents.flatMap { a in spent.lowerScenarioCents.map { portion(a, $0) } }
                return .init(start: received.start, savingCents: portion(received.earnedCents, spent.earnedCents),
                             lowerScenarioCents: lower, upperScenarioCents: upper)
            }
        }
        func close(_ start: Date) -> Date {
            PivotDate.calendar.date(byAdding: .weekOfYear, value: 1, to: start)!.addingTimeInterval(-1)
        }
        func reaching(_ amount: (Week) -> Int?) -> Date? {
            if scenario.remainingCents == 0 { return now }
            guard !limitations.contains(.provisional), !weeks.isEmpty else { return nil }
            var total = 0
            for week in weeks {
                guard let value = amount(week) else { return nil }
                total += value
                if total >= scenario.remainingCents { return close(week.start) }
            }
            return nil // No invented extrapolated date outside this horizon.
        }
        let beforeDeadline: Int? = goal.deadline.flatMap { deadline in
            guard !weeks.isEmpty else { return nil }
            return max(0, weeks.filter { close($0.start) <= deadline }.reduce(0) { $0 + $1.savingCents })
        }
        return .init(income: income, cash: cash, spending: spending, limitations: limitations, weeks: weeks,
                     remainingCents: scenario.remainingCents, completionDate: reaching { $0.savingCents },
                     slowerScenarioDate: reaching { $0.lowerScenarioCents }, fasterScenarioDate: reaching { $0.upperScenarioCents },
                     deadline: goal.deadline, projectedBeforeDeadlineCents: beforeDeadline, reservePercent: reservePercent)
    }
}

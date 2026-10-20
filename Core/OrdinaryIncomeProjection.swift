import Foundation

/// Completeness is an explicit input, not inferred from the first/last receipt
/// or from a selective historical import. This is not a bank-balance snapshot.
struct IncomeObservationCoverage: Equatable {
    var from: Date
    var through: Date
    var activitiesConfirmed: Bool
    var expensesConfirmed = false
}

struct OrdinaryIncomeWeek: Equatable {
    var start: Date
    var earnedCents = 0
    var knownCashCents = 0
    var knownSpentCents = 0
}

struct OrdinaryIncomeObservations: Equatable {
    var weeks: [OrdinaryIncomeWeek]
    var activeOrdinaryClients: Int
    var expensesComplete: Bool
    var unknownPaymentDates: Int
}

enum IncomeProjectionError: Error, Equatable { case coverageRequired, insufficientWeeks, staleCoverage, invalidData }

/// Read-only preparation. Gifts, one-off "other" income and inactive contacts
/// stay in the ledger, but do not train ordinary earning capacity. No provider,
/// calendar write, reservation or automatic allocation is involved.
enum OrdinaryIncomePreparation {
    static let maximumWeeklyCents = 1_000_000_000_000

    static func make(data: AppData, coverage: IncomeObservationCoverage?, now: Date) throws -> OrdinaryIncomeObservations {
        guard let coverage, coverage.activitiesConfirmed else { throw IncomeProjectionError.coverageRequired }
        guard [now, coverage.from, coverage.through].allSatisfy({ $0.timeIntervalSinceReferenceDate.isFinite }),
              coverage.from < coverage.through, coverage.through <= now,
              Set(data.clients.map(\.id)).count == data.clients.count,
              Set(data.income.map(\.id)).count == data.income.count,
              Set(data.payments.map(\.id)).count == data.payments.count,
              Set((data.savingsBudget?.expenses ?? []).map(\.id)).count == (data.savingsBudget?.expenses.count ?? 0) else {
            throw IncomeProjectionError.invalidData
        }
        let calendar = PivotDate.calendar
        // Monday boundaries use calendar arithmetic, including DST changes.
        let end = StudentPayments.week(containing: coverage.through).start
        let earliest = calendar.date(byAdding: .weekOfYear, value: -156, to: end)!
        var start = StudentPayments.week(containing: max(coverage.from, earliest)).start
        if start < coverage.from { start = calendar.date(byAdding: .weekOfYear, value: 1, to: start)! }
        var weeks: [OrdinaryIncomeWeek] = []
        var cursor = start
        while cursor < end && weeks.count < 156 {
            weeks.append(.init(start: cursor))
            cursor = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor)!
        }
        guard !weeks.isEmpty else { throw IncomeProjectionError.insufficientWeeks }
        let indices = Dictionary(uniqueKeysWithValues: weeks.enumerated().map { ($0.element.start, $0.offset) })
        let clients = data.clients.filter { $0.activityState?.inactive != true && [.lesson, .work].contains($0.activityKind) }
        let clientsByID = Dictionary(uniqueKeysWithValues: clients.map { ($0.id, $0) })
        var entries: [UUID: IncomeEntry] = [:]
        for entry in data.income where clientsByID[entry.clientID] != nil && [.lesson, .work].contains(entry.activityKind) {
            guard entry.date.timeIntervalSinceReferenceDate.isFinite, (1...100_000_000).contains(entry.amountCents) else {
                throw IncomeProjectionError.invalidData
            }
            entries[entry.id] = entry
            if let i = indices[StudentPayments.week(containing: entry.date).start] {
                weeks[i].earnedCents = try add(weeks[i].earnedCents, entry.amountCents)
            }
        }
        var unknownDates = 0
        for payment in data.payments {
            guard let entry = entries[payment.incomeID] else { continue }
            guard (1...100_000_000).contains(payment.amountCents) else { throw IncomeProjectionError.invalidData }
            guard let date = payment.date, entry.historicalSource?.paymentDateAssumed != true else {
                if entry.date >= start && entry.date < end { unknownDates += 1 }
                continue
            }
            guard date.timeIntervalSinceReferenceDate.isFinite else { throw IncomeProjectionError.invalidData }
            // A backfill excluded from today's budget is never new cash.
            if payment.excludedFromBudget != true, let i = indices[StudentPayments.week(containing: date).start] {
                weeks[i].knownCashCents = try add(weeks[i].knownCashCents, payment.amountCents)
            }
        }
        for expense in data.savingsBudget?.expenses ?? [] where expense.voided != true {
            guard expense.date.timeIntervalSinceReferenceDate.isFinite, (1...100_000_000).contains(expense.amountCents) else {
                throw IncomeProjectionError.invalidData
            }
            if let i = indices[StudentPayments.week(containing: expense.date).start] {
                // An aggregate expense remains one amount; no invented items.
                weeks[i].knownSpentCents = try add(weeks[i].knownSpentCents, expense.amountCents)
            }
        }
        return .init(weeks: weeks, activeOrdinaryClients: clients.count,
                     expensesComplete: coverage.expensesConfirmed, unknownPaymentDates: unknownDates)
    }

    private static func add(_ a: Int, _ b: Int) throws -> Int {
        let (sum, overflow) = a.addingReportingOverflow(b)
        guard !overflow, (0...maximumWeeklyCents).contains(sum) else { throw IncomeProjectionError.invalidData }
        return sum
    }
}

/// First forecasting layer: earned work, NOT future payment or disposable
/// savings. Those require a separate cash-timing/expense-coverage model.
struct OrdinaryIncomeProjection: Equatable {
    enum Model: String, CaseIterable { case recentMedian, recentMean, dampedTrend }
    struct Week: Equatable {
        var start: Date
        var earnedCents: Int
        // Empirical error scenarios, not a promised 80/95% probability.
        var lowerScenarioCents: Int?
        var upperScenarioCents: Int?
    }
    var model: Model
    var observations: Int
    var backtestCount: Int
    var meanAbsoluteErrorCents: Int?
    var rootMeanSquaredErrorCents: Int?
    var provisional: Bool
    var weeks: [Week]

    static func make(_ input: OrdinaryIncomeObservations, now: Date, horizon: Int = 13) throws -> Self {
        guard now.timeIntervalSinceReferenceDate.isFinite, (1...104).contains(horizon), input.weeks.count <= 156,
              input.weeks.allSatisfy({ [ $0.earnedCents, $0.knownCashCents, $0.knownSpentCents ].allSatisfy {
                  (0...OrdinaryIncomePreparation.maximumWeeklyCents).contains($0)
              } && $0.start.timeIntervalSinceReferenceDate.isFinite }) else { throw IncomeProjectionError.invalidData }
        guard input.weeks.count >= 8 else { throw IncomeProjectionError.insufficientWeeks }
        for (a, b) in zip(input.weeks, input.weeks.dropFirst()) {
            guard PivotDate.calendar.date(byAdding: .weekOfYear, value: 1, to: a.start) == b.start else {
                throw IncomeProjectionError.invalidData
            }
        }
        let lastCompleteWeek = PivotDate.calendar.date(byAdding: .weekOfYear, value: -1, to: StudentPayments.week(containing: now).start)!
        guard input.weeks.last?.start == lastCompleteWeek else { throw IncomeProjectionError.staleCoverage }
        let values = input.weeks.map { Double($0.earnedCents) }
        // Rolling origin: each held-out week sees only strictly earlier weeks.
        // The latest at most 12 errors select a current-regime model.
        let cuts = Array(max(8, values.count - 12)..<values.count)
        var errors: [Model: [Double]] = [:]
        for model in Model.allCases {
            errors[model] = cuts.map { cut in abs(values[cut] - predict(Array(values.prefix(cut)), model: model, step: 1)) }
        }
        let model: Model
        if cuts.count < 4 { model = .recentMedian }
        else {
            model = Model.allCases.min { a, b in
                // Cumulative earning capacity needs an expected amount. MAE
                // alone can prefer zero on intermittent but recurring work.
                let x = rootMeanSquare(errors[a] ?? []), y = rootMeanSquare(errors[b] ?? [])
                if x == y { return Model.allCases.firstIndex(of: a)! < Model.allCases.firstIndex(of: b)! }
                return x < y
            } ?? .recentMedian
        }
        let selected = errors[model] ?? []
        let hasBacktest = selected.count >= 4
        let dispersion = hasBacktest ? quantile(selected, fraction: 0.8) : nil
        let last = input.weeks.last!.start
        let projected = (1...horizon).map { step -> Week in
            let center = predict(values, model: model, step: step)
            let spread = dispersion.map { $0 * sqrt(Double(step)) }
            return .init(start: PivotDate.calendar.date(byAdding: .weekOfYear, value: step, to: last)!,
                         earnedCents: cents(center), lowerScenarioCents: spread.map { cents(center - $0) },
                         upperScenarioCents: spread.map { cents(center + $0) })
        }
        return .init(model: model, observations: values.count, backtestCount: selected.count,
                     meanAbsoluteErrorCents: hasBacktest ? cents(mean(selected)) : nil,
                     rootMeanSquaredErrorCents: hasBacktest ? cents(rootMeanSquare(selected)) : nil,
                     provisional: !hasBacktest, weeks: projected)
    }

    private static func predict(_ values: [Double], model: Model, step: Int) -> Double {
        let recent = Array(values.suffix(4)), level = quantile(recent, fraction: 0.5)
        switch model {
        case .recentMedian: return level
        case .recentMean: return mean(Array(values.suffix(8)))
        case .dampedTrend:
            guard values.count >= 6 else { return level }
            let latest = quantile(Array(values.suffix(3)), fraction: 0.5)
            let previous = quantile(Array(values.dropLast(3).suffix(3)), fraction: 0.5)
            let slope = (latest - previous) / 3
            let damping = (1...step).reduce(0.0) { $0 + pow(0.8, Double($1)) }
            return min(Double(OrdinaryIncomePreparation.maximumWeeklyCents), max(0, latest + slope * damping))
        }
    }
    private static func mean(_ values: [Double]) -> Double { values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count) }
    private static func rootMeanSquare(_ values: [Double]) -> Double { sqrt(mean(values.map { $0 * $0 })) }
    private static func quantile(_ values: [Double], fraction: Double) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let x = Double(sorted.count - 1) * fraction, lo = Int(x.rounded(.down)), hi = Int(x.rounded(.up))
        return sorted[lo] + (sorted[hi] - sorted[lo]) * (x - Double(lo))
    }
    private static func cents(_ value: Double) -> Int {
        Int(min(Double(OrdinaryIncomePreparation.maximumWeeklyCents), max(0, value)).rounded())
    }
}

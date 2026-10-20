import XCTest
@testable import PivotCore

final class SavingsEvidenceForecastTests: XCTestCase {
    private let now = PivotDate.calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 12))!
    private func fixture(count: Int = 16, cash: Int = 10_000, expenses: Int = 2000) -> (AppData, OrdinaryIncomeObservations, UUID) {
        let goal = SavingsGoal(name: "Obiettivo sintetico", targetCents: 100_000)
        var data = AppData(); data.savingsBudget = .init(openingFundsCents: 20_000, goals: [goal],
            allocations: [.init(goalID: goal.id, cents: 10_000, date: now)])
        let monday = StudentPayments.week(containing: now).start
        let weeks = (0..<count).map { index in
            OrdinaryIncomeWeek(start: PivotDate.calendar.date(byAdding: .weekOfYear, value: index - count, to: monday)!,
                earnedCents: 15_000, knownCashCents: cash, knownSpentCents: expenses)
        }
        return (data, .init(weeks: weeks, activeOrdinaryClients: 1, expensesComplete: true,
                            unknownPaymentDates: 0, receiptsComplete: true), goal.id)
    }
    private func make(_ data: AppData, _ input: OrdinaryIncomeObservations, _ id: UUID,
                      upfront: Int = 0, percent: Int = 100, horizon: Int = 52) throws -> SavingsEvidenceForecast {
        try .make(goalID: id, data: data, observations: input, upfrontCents: upfront,
                  reservePercent: percent, now: now, horizon: horizon)
    }
    func testEarnedWorkCannotBeConfusedWithCashOrSavingAndCurrentWeekIsExcluded() throws {
        let (data, input, id) = fixture()
        let value = try make(data, input, id)
        XCTAssertEqual(value.income.weeks[0].earnedCents, 15_000)
        XCTAssertEqual(value.cash?.weeks[0].earnedCents, 10_000)
        XCTAssertEqual(value.weeks.first?.savingCents, 8000)
        XCTAssertEqual(value.weeks.first?.start, PivotDate.calendar.date(byAdding: .weekOfYear, value: 1,
            to: StudentPayments.week(containing: now).start))
        XCTAssertEqual(value.remainingCents, 90_000)
        XCTAssertEqual(value.completionDate, PivotDate.calendar.date(byAdding: .weekOfYear, value: 13,
            to: StudentPayments.week(containing: now).start)!.addingTimeInterval(-1))
    }
    func testUnknownDatesAndUnconfirmedReceiptsCannotProduceASavingDate() throws {
        let (data, input, id) = fixture()
        var missing = input; missing.receiptsComplete = false
        var value = try make(data, missing, id)
        XCTAssertNil(value.cash); XCTAssertTrue(value.weeks.isEmpty); XCTAssertNil(value.completionDate)
        XCTAssertTrue(value.limitations.contains(.receiptsNotConfirmed))
        missing = input; missing.unknownPaymentDates = 1
        value = try make(data, missing, id)
        XCTAssertNil(value.cash); XCTAssertNil(value.completionDate)
        XCTAssertTrue(value.limitations.contains(.unknownReceiptDates))
    }
    func testVerifiedHistoricalReceiptsTrainFutureScenarioButRemainUnavailableToday() throws {
        var (data, template, id) = fixture()
        data.savingsBudget?.openingFundsCents = 0
        data.savingsBudget?.allocations = []
        let client = Client(name: "Storico verificato QA", rateCents: 1500)
        data.clients = [client]
        for week in template.weeks {
            let entry = IncomeEntry(clientID: client.id, clientName: client.name, date: week.start,
                minutes: 60, amountCents: 10_000, paidCents: 10_000)
            data.income.append(entry)
            data.payments.append(.init(incomeID: entry.id, clientName: client.name, date: week.start,
                amountCents: 10_000, excludedFromBudget: true))
        }
        let coverage = IncomeObservationCoverage(from: template.weeks[0].start, through: now,
            activitiesConfirmed: true, expensesConfirmed: true, receiptsConfirmed: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let original = try encoder.encode(data)
        let observations = try OrdinaryIncomePreparation.make(data: data, coverage: coverage, now: now)
        let value = try make(data, observations, id)
        XCTAssertEqual(value.weeks.first?.savingCents, 10_000)
        XCTAssertNotNil(value.completionDate)
        XCTAssertEqual(try SavingsAccounting.balance(data.savingsBudget!, payments: data.payments).freeCents, 0)
        XCTAssertThrowsError(try make(data, observations, id, upfront: 1))
        XCTAssertEqual(try encoder.encode(data), original)
    }
    func testUnconfirmedExpensesAreNotAutomaticallyZero() throws {
        let (data, input, id) = fixture()
        var missing = input; missing.expensesComplete = false
        let value = try make(data, missing, id)
        XCTAssertNotNil(value.cash); XCTAssertNil(value.spending); XCTAssertTrue(value.weeks.isEmpty)
        XCTAssertNil(value.completionDate); XCTAssertTrue(value.limitations.contains(.expensesNotConfirmed))
    }
    func testUserAllocationShareAndAggregateExpenseChangeOnlyScenario() throws {
        let (data, input, id) = fixture()
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let original = try encoder.encode(data)
        XCTAssertEqual(try make(data, input, id, upfront: 5000, percent: 50).weeks[0].savingCents, 4000)
        XCTAssertEqual(try make(data, input, id, upfront: 5000).remainingCents, 85_000)
        XCTAssertNil(try make(data, input, id, percent: 0).completionDate)
        XCTAssertEqual(try encoder.encode(data), original)
        XCTAssertThrowsError(try make(data, input, id, upfront: 10_001))
        XCTAssertThrowsError(try make(data, input, id, percent: 101))
    }
    func testNoInventedDatesForNegativeNetSmallSampleOrOutOfHorizon() throws {
        let (data, input, id) = fixture(cash: 1000, expenses: 2000)
        XCTAssertTrue(try make(data, input, id).weeks.allSatisfy { $0.savingCents == -1000 },
            "An expensive week must not be erased from the cumulative margin")
        XCTAssertNil(try make(data, input, id).completionDate)
        let (_, small, _) = fixture(count: 8)
        let provisional = try make(data, small, id)
        XCTAssertTrue(provisional.limitations.contains(.provisional)); XCTAssertNil(provisional.completionDate)
        let (_, good, _) = fixture()
        XCTAssertNil(try make(data, good, id, horizon: 2).completionDate)
    }
    func testDeadlineUsesWeeklyCashAvailabilityNotRequiredArithmeticQuota() throws {
        var (data, input, id) = fixture()
        data.savingsBudget?.goals[0].deadline = now.addingTimeInterval(3 * 86400)
        var value = try make(data, input, id)
        XCTAssertEqual(value.projectedBeforeDeadlineCents, 0)
        XCTAssertNotNil(value.completionDate)
        data.savingsBudget?.goals[0].deadline = PivotDate.calendar.date(byAdding: .weekOfYear, value: 3,
            to: StudentPayments.week(containing: now).start)!
        value = try make(data, input, id)
        XCTAssertEqual(value.projectedBeforeDeadlineCents, 16_000)
    }
    func testNoDateWhenExistingReservationsAreUnderfundedAndNoUseOfOtherGoalFunds() throws {
        var (data, input, id) = fixture()
        data.savingsBudget?.expenses = [.init(amountCents: 15_000, date: now, description: "Spesa QA")]
        XCTAssertThrowsError(try make(data, input, id))
        data.savingsBudget?.expenses = []
        let other = SavingsGoal(name: "Altro QA", targetCents: 10_000)
        data.savingsBudget?.goals.append(other)
        data.savingsBudget?.allocations.append(.init(goalID: other.id, cents: 10_000, date: now))
        XCTAssertThrowsError(try make(data, input, id, upfront: 1))
    }
    func testAlreadyFundedGoalNeedsNoFutureReceiptAndCoverageIsExplicitlyCodable() throws {
        var (data, input, id) = fixture()
        data.savingsBudget?.goals[0].targetCents = 10_000
        let value = try make(data, input, id)
        XCTAssertEqual(value.remainingCents, 0); XCTAssertEqual(value.completionDate, now)
        let coverage = IncomeObservationCoverage(from: input.weeks[0].start, through: now,
            activitiesConfirmed: true, expensesConfirmed: false, receiptsConfirmed: false)
        XCTAssertTrue(coverage.isValid)
        XCTAssertEqual(try JSONDecoder().decode(IncomeObservationCoverage.self, from: JSONEncoder().encode(coverage)), coverage)
    }
    func testCoverageSurvivesBackupButInvalidIntervalIsRejectedAndLegacyPaidTotalsAreNotCash() throws {
        var (data, input, _) = fixture()
        let coverage = IncomeObservationCoverage(from: input.weeks[0].start, through: now,
            activitiesConfirmed: true, expensesConfirmed: true, receiptsConfirmed: true)
        data.incomeObservationCoverage = coverage
        XCTAssertEqual(try BackupCodec.decode(BackupCodec.encode(data)).incomeObservationCoverage, coverage)
        data.incomeObservationCoverage?.from = now.addingTimeInterval(1)
        XCTAssertThrowsError(try BackupCodec.decode(BackupCodec.encode(data)))
        let client = Client(name: "Precedente QA", rateCents: 1500)
        data.clients = [client]
        data.income = [.init(clientID: client.id, clientName: client.name, date: input.weeks[0].start,
            minutes: 60, amountCents: 1500, paidCents: 1500)]
        data.payments = []
        input = try OrdinaryIncomePreparation.make(data: data, coverage: coverage, now: now)
        XCTAssertEqual(input.unknownPaymentDates, 1)
        XCTAssertEqual(input.weeks[0].earnedCents, 1500)
        XCTAssertEqual(input.weeks[0].knownCashCents, 0)
    }
}

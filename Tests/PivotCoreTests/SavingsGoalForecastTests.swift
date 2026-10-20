import XCTest
@testable import PivotCore

final class SavingsGoalForecastTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func data() -> AppData {
        var data = AppData()
        let goal = SavingsGoal(name: "Obiettivo QA", targetCents: 90_000)
        data.savingsBudget = .init(openingFundsCents: 38_000, goals: [goal],
                                  allocations: [.init(goalID: goal.id, cents: 20_000, date: now)])
        return data
    }
    private func make(_ data: AppData, upfront: Int = 0, weekly: Int = 10_000) -> SavingsGoalForecast? {
        SavingsGoalForecast.make(goalID: data.savingsBudget!.goals[0].id, data: data, upfrontCents: upfront, weeklyCents: weekly, now: now)
    }
    func testScenarioDoesNotSpendReserveOrInventAReceipt() throws {
        let data = data(), original = try JSONEncoder().encode(data)
        let result = try XCTUnwrap(make(data, upfront: 10_000))
        XCTAssertEqual(result.reservedCents, 20_000); XCTAssertEqual(result.freeCents, 18_000)
        XCTAssertEqual(result.remainingCents, 60_000); XCTAssertEqual(result.weeksNeeded, 6)
        XCTAssertEqual(result.completionDate, PivotDate.calendar.date(byAdding: .weekOfYear, value: 6, to: now))
        let restored = try JSONDecoder().decode(AppData.self, from: original)
        XCTAssertEqual(data.payments.count, restored.payments.count)
        XCTAssertEqual(data.savingsBudget?.allocations.count, restored.savingsBudget?.allocations.count)
        XCTAssertEqual(try SavingsAccounting.balance(data.savingsBudget!, payments: data.payments),
                       try SavingsAccounting.balance(restored.savingsBudget!, payments: restored.payments))
    }
    func testCannotHypothesizeUnavailableCashAsAlreadyAvailable() {
        let data = data()
        XCTAssertNil(make(data, upfront: 18_001)); XCTAssertNil(make(data, upfront: -1))
        XCTAssertNotNil(make(data, upfront: 18_000))
    }
    func testZeroWeeklyHasNoInventedCompletionDate() {
        let result = make(data(), weekly: 0)
        XCTAssertNil(result?.weeksNeeded); XCTAssertNil(result?.completionDate)
    }
    func testWeeksRoundUpAndDeadlineUsesOnlyWholeFutureContributions() {
        var data = data()
        data.savingsBudget?.goals[0].deadline = PivotDate.calendar.date(byAdding: .day, value: 24, to: now)
        let result = make(data, weekly: 11_000)
        XCTAssertEqual(result?.weeksNeeded, 7)
        XCTAssertEqual(result?.contributionsBeforeDeadline, 3)
        XCTAssertEqual(result?.requiredWeeklyCents, 23_334)
    }
    func testDeadlineBeforeFirstWeeklyContributionIsExplicit() {
        var data = data()
        data.savingsBudget?.goals[0].deadline = now.addingTimeInterval(3 * 86400)
        XCTAssertEqual(make(data)?.contributionsBeforeDeadline, 0); XCTAssertNil(make(data)?.requiredWeeklyCents)
        data.savingsBudget?.goals[0].deadline = now.addingTimeInterval(-1)
        XCTAssertEqual(make(data)?.deadlineMissed, false, "The selected day has not ended")
        data.savingsBudget?.goals[0].deadline = PivotDate.calendar.date(byAdding: .day, value: -1, to: now)
        XCTAssertEqual(make(data)?.deadlineMissed, true)
    }
    func testDateOnlyDeadlineIncludesTheWholeChosenDayWithoutCountingNextMidnight() throws {
        var data = data()
        let contribution = PivotDate.calendar.date(byAdding: .weekOfYear, value: 1, to: now)!
        let day = PivotDate.calendar.startOfDay(for: contribution)
        data.savingsBudget?.goals[0].deadline = day
        XCTAssertEqual(make(data)?.contributionsBeforeDeadline, 1)
        data.savingsBudget?.goals[0].deadline = day.addingTimeInterval(20 * 3600)
        XCTAssertEqual(make(data)?.contributionsBeforeDeadline, 1)
        let midnight = PivotDate.calendar.startOfDay(for: now)
        let nextWeek = PivotDate.calendar.date(byAdding: .weekOfYear, value: 1, to: midnight)!
        data.savingsBudget?.goals[0].deadline = PivotDate.calendar.date(byAdding: .day, value: -1, to: nextWeek)
        let value = SavingsGoalForecast.make(goalID: data.savingsBudget!.goals[0].id, data: data,
            upfrontCents: 0, weeklyCents: 1000, now: midnight)
        XCTAssertEqual(value?.contributionsBeforeDeadline, 0)
        for (month, day, hours) in [(3, 29, 23), (10, 25, 25)] {
            let date = PivotDate.calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
            let goal = SavingsGoal(name: "Scadenza DST QA", targetCents: 1000, deadline: date)
            XCTAssertEqual(goal.deadlineEndExclusive?.timeIntervalSince(date), Double(hours * 3600),
                "Use calendar days, not a fixed 24-hour deadline")
        }
    }
    func testArchivedGoalAndUnbalancedFundsDoNotProduceAForecast() {
        var data = data()
        data.savingsBudget?.goals[0].archived = true; XCTAssertNil(make(data))
        data.savingsBudget?.goals[0].archived = false
        data.savingsBudget?.expenses = [.init(amountCents: 30_000, date: now, description: "Spesa QA")]
        XCTAssertNil(make(data))
    }
    func testDistantCentPerWeekDoesNotOverflowACompletionDate() {
        var data = data(); data.savingsBudget?.goals[0].targetCents = SavingsAccounting.maximumMovementCents
        let result = make(data, weekly: 1)
        XCTAssertNotNil(result?.weeksNeeded); XCTAssertNil(result?.completionDate)
        XCTAssertNil(make(data, weekly: Int.max))
    }
    func testHistoricalAnnualOpeningDoesNotBecomeAvailableFunds() throws {
        var data = data()
        data.ledger = AnnualLedger(); data.ledger?.openingCents = ["2026": 900_000]
        XCTAssertEqual(make(data)?.freeCents, 18_000)
        XCTAssertEqual(make(data)?.remainingCents, 70_000)
    }
}

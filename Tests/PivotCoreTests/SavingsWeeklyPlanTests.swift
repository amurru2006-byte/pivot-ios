import XCTest
@testable import PivotCore

final class SavingsWeeklyPlanTests: XCTestCase {
    private let now = PivotDate.calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 12))!
    private func fixture() -> (AppData, UUID) {
        var data = AppData()
        let client = Client(name: "Cliente settimanale QA", rateCents: 1500)
        let entry = IncomeEntry(clientID: client.id, clientName: client.name, date: now.addingTimeInterval(-7200),
            minutes: 60, amountCents: 10_000, paidCents: 10_000)
        let goal = SavingsGoal(name: "Obiettivo QA", targetCents: 90_000, weeklyPlan: .init())
        data.clients = [client]; data.income = [entry]
        data.payments = [.init(incomeID: entry.id, clientName: client.name, date: entry.date, amountCents: 10_000)]
        data.savingsBudget = .init(openingFundsCents: 22_000, goals: [goal], expenses: [
            .init(amountCents: 2000, date: now.addingTimeInterval(-3600), description: "Spese aggregate QA")])
        data.incomeObservationCoverage = .init(from: StudentPayments.week(containing: now).start,
            through: now.addingTimeInterval(-1), activitiesConfirmed: true, expensesConfirmed: true, receiptsConfirmed: true)
        return (data, goal.id)
    }
    private func review(_ data: AppData, _ id: UUID) throws -> SavingsWeeklyReview {
        try .make(goalID: id, data: data, now: now)
    }
    func testWeeklyScheduleUsesChosenLocalDayAndTimeAndDoesNotRepeatTodayPastTheTime() throws {
        let plan = SavingsWeeklyPlan()
        let next = try XCTUnwrap(plan.nextReview(after: now))
        let parts = PivotDate.calendar.dateComponents([.weekday, .hour, .minute], from: next)
        XCTAssertEqual(parts.weekday, 1); XCTAssertEqual(parts.hour, 20); XCTAssertEqual(parts.minute, 0)
        let following = try XCTUnwrap(plan.nextReview(after: next))
        XCTAssertEqual(PivotDate.calendar.dateComponents([.day], from: next, to: following).day, 7)
        XCTAssertEqual(PivotDate.calendar.component(.hour, from: following), 20)
        XCTAssertEqual(following.timeIntervalSince(next), 168 * 3600)
        let previous = PivotDate.calendar.date(byAdding: .day, value: -7, to: next)!
        XCTAssertEqual(next.timeIntervalSince(previous), 169 * 3600, "The preceding review interval crosses autumn DST")
    }
    func testKnownCashLessAggregateExpensesIsASuggestionNotAMoneyMovement() throws {
        let (data, id) = fixture()
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let original = try encoder.encode(data)
        let value = try review(data, id)
        XCTAssertEqual(value.receivedCents, 10_000); XCTAssertEqual(value.spentCents, 2000)
        XCTAssertEqual(value.proposedCents, 8000); XCTAssertEqual(value.freeCents, 30_000)
        XCTAssertTrue(value.issues.isEmpty)
        XCTAssertEqual(try encoder.encode(data), original)
    }
    func testAlreadyReservedMoneyIsNotSuggestedTwiceAndOtherGoalsKeepTheirFunds() throws {
        var (data, id) = fixture()
        data.savingsBudget?.allocations = [.init(goalID: id, cents: 3000, date: now.addingTimeInterval(-30))]
        XCTAssertEqual(try review(data, id).proposedCents, 5000)
        let other = SavingsGoal(name: "Altro QA", targetCents: 50_000)
        data.savingsBudget?.goals.append(other)
        data.savingsBudget?.allocations.append(.init(goalID: other.id, cents: 26_000, date: now))
        XCTAssertEqual(try review(data, id).proposedCents, 1000)
        data.savingsBudget?.goals[0].targetCents = 3500
        XCTAssertEqual(try review(data, id).proposedCents, 500)
    }
    func testShareAppliesToNetCashAndExtraordinaryOrHistoricalReceiptsCannotRaiseIt() throws {
        var (data, id) = fixture()
        data.savingsBudget?.goals[0].weeklyPlan?.reservePercent = 50
        let expected = try review(data, id).proposedCents
        let client = Client(name: "Regalo QA", rateCents: 0, activity: .gift)
        let gift = IncomeEntry(clientID: client.id, clientName: client.name, date: now,
            minutes: 0, amountCents: 100_000, paidCents: 100_000, activity: .gift)
        data.clients.append(client); data.income.append(gift)
        data.payments.append(.init(incomeID: gift.id, clientName: client.name, date: now.addingTimeInterval(-1), amountCents: 100_000))
        XCTAssertEqual(expected, 4000); XCTAssertEqual(try review(data, id).proposedCents, expected)
        data.payments[0].excludedFromBudget = true
        XCTAssertEqual(try review(data, id).proposedCents, 0, "Historical cash is not newly available this week")
    }
    func testUnconfirmedOrOldCoverageCannotBePresentedAsAnUpdatedWeeklyAmount() throws {
        var (data, id) = fixture()
        data.incomeObservationCoverage?.expensesConfirmed = false
        XCTAssertNil(try review(data, id).proposedCents)
        XCTAssertTrue(try review(data, id).issues.contains(.expensesNotConfirmed))
        data.incomeObservationCoverage?.expensesConfirmed = true
        data.incomeObservationCoverage?.receiptsConfirmed = false
        XCTAssertTrue(try review(data, id).issues.contains(.receiptsNotConfirmed))
        data.incomeObservationCoverage?.through = now.addingTimeInterval(-86400)
        XCTAssertTrue(try review(data, id).issues.contains(.verifyRecentData))
        data.incomeObservationCoverage = nil
        XCTAssertNil(try review(data, id).proposedCents)
    }
    func testUndatedReceiptsAndLegacyPaidTotalsRequireReviewRatherThanAZeroCashClaim() throws {
        var (data, id) = fixture()
        data.payments[0].date = nil
        XCTAssertTrue(try review(data, id).issues.contains(.unknownReceiptDates))
        data.payments = []
        XCTAssertNil(try review(data, id).proposedCents)
        XCTAssertTrue(try review(data, id).issues.contains(.unknownReceiptDates))
    }
    func testExpensesCanReduceTheQuotaToZeroAndUnderfundedReservationsBlockIt() throws {
        var (data, id) = fixture()
        data.savingsBudget?.expenses[0].amountCents = 11_000
        XCTAssertEqual(try review(data, id).proposedCents, 0)
        data.savingsBudget?.allocations = [.init(goalID: id, cents: 22_000, date: now)]
        XCTAssertTrue(try review(data, id).issues.contains(.underfunded))
        XCTAssertNil(try review(data, id).proposedCents)
    }
    func testMetadataSurvivesBackupAndInvalidScheduleIsRejected() throws {
        var (data, id) = fixture()
        let restored = try BackupCodec.decode(BackupCodec.encode(data))
        XCTAssertEqual(restored.savingsBudget?.goals[0].weeklyPlan, .init())
        XCTAssertEqual(try review(restored, id).proposedCents, 8000)
        for invalid in [SavingsWeeklyPlan(weekday: 0), .init(hour: 24), .init(minute: 60), .init(reservePercent: 101)] {
            XCTAssertFalse(invalid.isValid); XCTAssertNil(invalid.nextReview(after: now))
            data.savingsBudget?.goals[0].weeklyPlan = invalid
            XCTAssertThrowsError(try BackupCodec.decode(BackupCodec.encode(data)))
        }
    }
}

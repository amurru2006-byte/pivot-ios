import XCTest
@testable import PivotCore

final class OrdinaryIncomeProjectionTests: XCTestCase {
    private let now = PivotDate.calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 12))!
    private func week(_ offset: Int) -> Date {
        PivotDate.calendar.date(byAdding: .weekOfYear, value: offset, to: StudentPayments.week(containing: now).start)!
    }
    private func fixture(_ amounts: [Int]) -> AppData {
        var data = AppData()
        let client = Client(name: "Cliente ordinario QA", rateCents: 1500)
        data.clients = [client]
        for (i, amount) in amounts.enumerated() where amount > 0 {
            let date = week(i - amounts.count).addingTimeInterval(3600)
            let entry = IncomeEntry(clientID: client.id, clientName: client.name, date: date, minutes: 60,
                                    amountCents: amount, paidCents: amount)
            data.income.append(entry)
            data.payments.append(.init(incomeID: entry.id, clientName: client.name, date: date, amountCents: amount))
        }
        return data
    }
    private func prepared(_ data: AppData, count: Int = 16, expenses: Bool = false) throws -> OrdinaryIncomeObservations {
        try OrdinaryIncomePreparation.make(data: data,
            coverage: .init(from: week(-count), through: now, activitiesConfirmed: true, expensesConfirmed: expenses), now: now)
    }
    func testExplicitCoverageRequiredAndMissingPeriodsAreNotInferredAsZero() {
        let data = fixture([1000, 1000])
        XCTAssertThrowsError(try OrdinaryIncomePreparation.make(data: data, coverage: nil, now: now)) {
            XCTAssertEqual($0 as? IncomeProjectionError, .coverageRequired)
        }
        XCTAssertThrowsError(try OrdinaryIncomePreparation.make(data: data,
            coverage: .init(from: week(-16), through: now, activitiesConfirmed: false), now: now))
    }
    func testOnlyFullObservedWeeksAndConfirmedZerosEnterTraining() throws {
        var data = fixture([1000, 0, 2000, 0, 1500, 0, 1000, 0])
        data.income.append(.init(clientID: data.clients[0].id, clientName: "Cliente QA", date: now,
                                 minutes: 60, amountCents: 100_000))
        let input = try prepared(data, count: 8)
        XCTAssertEqual(input.weeks.count, 8)
        XCTAssertEqual(input.weeks.map(\.earnedCents), [1000, 0, 2000, 0, 1500, 0, 1000, 0])
        XCTAssertFalse(input.expensesComplete)
        let partial = try OrdinaryIncomePreparation.make(data: data,
            coverage: .init(from: week(-8).addingTimeInterval(3600), through: now, activitiesConfirmed: true), now: now)
        XCTAssertEqual(partial.weeks.count, 7)
    }
    func testGiftsOtherIncomeAndInactivePortfolioCannotRaiseOrdinaryEstimate() throws {
        var data = fixture(Array(repeating: 2000, count: 16))
        let expected = try OrdinaryIncomeProjection.make(prepared(data), now: now)
        for kind in [IncomeActivityKind.gift, .other, .lesson] {
            var client = Client(name: "Entrata esclusa QA", rateCents: 9000, activity: kind)
            if kind == .lesson { client.activityState = .init(inactive: true, manuallyInactive: true, firstObservedAt: week(-30)) }
            data.clients.append(client)
            data.income.append(.init(clientID: client.id, clientName: client.name, date: week(-1), minutes: 60,
                                     amountCents: 900_000, paidCents: 900_000, activity: kind))
        }
        let result = try OrdinaryIncomeProjection.make(prepared(data), now: now)
        XCTAssertEqual(result, expected)
        XCTAssertEqual(data.income.count, 19, "Excluded from training is not deleted from the ledger")
    }
    func testCashAndCompetenceStaySeparateAndLateReceiptIsNotNewDemand() throws {
        var data = fixture(Array(repeating: 1500, count: 16))
        let firstID = data.income[0].id
        data.payments.removeAll { $0.incomeID == firstID }
        data.payments.append(.init(incomeID: firstID, clientName: "Cliente QA", date: week(-1), amountCents: 1500))
        let result = try prepared(data)
        XCTAssertEqual(result.weeks[0].earnedCents, 1500); XCTAssertEqual(result.weeks[0].knownCashCents, 0)
        XCTAssertEqual(result.weeks.last?.earnedCents, 1500); XCTAssertEqual(result.weeks.last?.knownCashCents, 3000)
        data.payments[0].date = nil
        let unknown = try prepared(data)
        XCTAssertEqual(unknown.unknownPaymentDates, 1)
    }
    func testBudgetExcludedBackfillDoesNotCreateCurrentAvailableCash() throws {
        var data = fixture(Array(repeating: 1500, count: 16))
        data.payments[0].excludedFromBudget = true
        let input = try prepared(data)
        XCTAssertEqual(input.weeks[0].earnedCents, 1500)
        XCTAssertEqual(input.weeks[0].knownCashCents, 0)
        data.ledger = .init(openingCents: ["2026": 90_000])
        XCTAssertEqual(try prepared(data), input, "The aggregate opening amount cannot train a weekly earning rate")
    }
    func testAssumedHistoricalPaymentDayDoesNotProveImmediateCollection() throws {
        var data = fixture(Array(repeating: 1500, count: 16))
        let date = data.income[0].date
        let event = CalendarItem(id: "history-forecast-qa", eventIdentifier: "history-forecast-qa", calendarIdentifier: "qa-work",
            calendarTitle: "Lavoro QA", title: "Lezione QA", start: date.addingTimeInterval(-3600), end: date,
            location: "", notes: "", colorHex: "7EE6CD", isAllDay: false, writable: true, kind: .tutoring)
        data.income[0].historicalSource = .init(event: event, rateCents: 1500, openingAttributedCents: 1500,
            receivedYear: 2026, receiptID: data.payments[0].id, importedAt: now, paymentDateAssumed: true)
        let result = try prepared(data)
        XCTAssertEqual(result.weeks[0].earnedCents, 1500)
        XCTAssertEqual(result.weeks[0].knownCashCents, 0)
        XCTAssertEqual(result.unknownPaymentDates, 1)
    }
    func testAggregateExpensesStayAmountsAndRequireSeparateCompleteness() throws {
        var data = fixture(Array(repeating: 1500, count: 16))
        data.savingsBudget = .init(openingFundsCents: 0, expenses: [
            .init(amountCents: 1500, date: week(-1), description: "Spese aggregate QA"),
            .init(amountCents: 9000, date: week(-1), description: "Annullata QA", voided: true)
        ])
        let unknown = try prepared(data)
        XCTAssertFalse(unknown.expensesComplete); XCTAssertEqual(unknown.weeks.last?.knownSpentCents, 1500)
        XCTAssertTrue(try prepared(data, expenses: true).expensesComplete)
        XCTAssertEqual(data.savingsBudget?.expenses.count, 2)
    }
    func testRecentRegimeReplacesOldLowAnnualAverageWithoutDoublingRule() throws {
        let data = fixture(Array(repeating: 1000, count: 16) + Array(repeating: 3000, count: 12))
        let value = try OrdinaryIncomeProjection.make(prepared(data, count: 28), now: now)
        XCTAssertEqual(value.weeks.first?.earnedCents, 3000)
        XCTAssertEqual(value.backtestCount, 12)
        XCTAssertFalse(value.provisional)
    }
    func testSmallSamplesCannotInventBacktestAccuracyOrScenarioBounds() throws {
        let value = try OrdinaryIncomeProjection.make(prepared(fixture(Array(repeating: 1500, count: 8)), count: 8), now: now)
        XCTAssertTrue(value.provisional); XCTAssertNil(value.meanAbsoluteErrorCents)
        XCTAssertNil(value.rootMeanSquaredErrorCents)
        XCTAssertNil(value.weeks.first?.lowerScenarioCents); XCTAssertNil(value.weeks.first?.upperScenarioCents)
        XCTAssertThrowsError(try OrdinaryIncomeProjection.make(prepared(fixture([1500]), count: 7), now: now))
    }
    func testIntermittentRecurringWorkIsNotForecastAsZeroJustBecauseMostWeeksAreEmpty() throws {
        let amounts = Array(repeating: [0, 0, 0, 6000], count: 8).flatMap { $0 }
        let value = try OrdinaryIncomeProjection.make(prepared(fixture(amounts), count: 32), now: now)
        XCTAssertEqual(value.model, .recentMean)
        XCTAssertEqual(value.weeks.first?.earnedCents, 1500)
        XCTAssertNotNil(value.rootMeanSquaredErrorCents)
    }
    func testMissingRecentCoverageCannotBecomeATodaysForecast() throws {
        var input = try prepared(fixture(Array(repeating: 1500, count: 16)))
        input.weeks.removeLast()
        XCTAssertThrowsError(try OrdinaryIncomeProjection.make(input, now: now)) {
            XCTAssertEqual($0 as? IncomeProjectionError, .staleCoverage)
        }
        input.weeks.remove(at: 2)
        XCTAssertThrowsError(try OrdinaryIncomeProjection.make(input, now: now)) {
            XCTAssertEqual($0 as? IncomeProjectionError, .invalidData)
        }
    }
    func testDstWeeksUseCalendarBoundariesAndPredictionsRemainBounded() throws {
        let input = try prepared(fixture(Array(repeating: 1500, count: 16)))
        let value = try OrdinaryIncomeProjection.make(input, now: now, horizon: 104)
        XCTAssertEqual(value.weeks.count, 104)
        XCTAssertTrue(value.weeks.allSatisfy { $0.earnedCents == 1500 })
        XCTAssertNotEqual(value.weeks[1].start.timeIntervalSince(value.weeks[0].start), 7 * 86400,
                          "The week crossing October DST has a different number of seconds")
        XCTAssertThrowsError(try OrdinaryIncomeProjection.make(input, now: now, horizon: Int.max))
    }
    func testMalformedDuplicatesAndInvalidMoneyFailClosed() throws {
        var data = fixture(Array(repeating: 1500, count: 16))
        data.income.append(data.income[0]); XCTAssertThrowsError(try prepared(data))
        data.income.removeLast(); data.income[0].amountCents = Int.max
        XCTAssertThrowsError(try prepared(data))
        var input = try prepared(fixture(Array(repeating: 1500, count: 16)))
        input.weeks[0].earnedCents = -1
        XCTAssertThrowsError(try OrdinaryIncomeProjection.make(input, now: now))
    }
    func testObservedSeasonalityUsesCompleteYearsAndCurrentLevelRatherThanOldAnnualCash() throws {
        let amounts = (0..<156).map { index -> Int in
            let date = PivotDate.calendar.date(byAdding: .day, value: 3, to: week(index - 156))!
            let month = PivotDate.calendar.component(.month, from: date)
            let year = PivotDate.calendar.component(.year, from: date)
            return (month.isMultiple(of: 2) ? 3000 : 1000) * (year >= 2025 ? 2 : 1)
        }
        let input = try prepared(fixture(amounts), count: 156)
        let forecast = try OrdinaryIncomeProjection.make(input, now: now, horizon: 13)
        XCTAssertEqual(forecast.model, .seasonalRecentMean)
        let november = try XCTUnwrap(forecast.weeks.first { PivotDate.calendar.component(.month, from: $0.start.addingTimeInterval(3 * 86400)) == 11 })
        let december = try XCTUnwrap(forecast.weeks.first { PivotDate.calendar.component(.month, from: $0.start.addingTimeInterval(3 * 86400)) == 12 })
        XCTAssertTrue((1700...2300).contains(november.earnedCents))
        XCTAssertTrue((5500...6500).contains(december.earnedCents))
    }
    func testPartialYearsCannotInventARecurringSeasonalPattern() throws {
        let amounts = (0..<80).map { $0.isMultiple(of: 4) ? 6000 : 1000 }
        let forecast = try OrdinaryIncomeProjection.make(prepared(fixture(amounts), count: 80), now: now)
        XCTAssertNotEqual(forecast.model, .seasonalRecentMean)
    }
    func testReadOnlyModelNeverCreatesPaymentsExpensesOrSavingsReservations() throws {
        let data = fixture(Array(repeating: 1500, count: 16))
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let before = try encoder.encode(data)
        _ = try OrdinaryIncomeProjection.make(prepared(data), now: now)
        XCTAssertEqual(try encoder.encode(data), before)
    }
    func testOneOffWorkNeedsExplicitRecurringChoiceAndLessonsCanOptOutWithoutChangingHistory() throws {
        var data = fixture(Array(repeating: 2000, count: 16))
        var work = Client(name: "Progetto una tantum QA", rateCents: 90_000, activity: .work)
        data.clients.append(work)
        data.income.append(.init(clientID: work.id, clientName: work.name, date: week(-1), minutes: 60,
            amountCents: 90_000, activity: .work))
        XCTAssertEqual(try prepared(data).weeks.last?.earnedCents, 2000)
        data.clients[1].ordinaryForecastEnabled = true
        XCTAssertEqual(try prepared(data).weeks.last?.earnedCents, 92_000)
        data.clients[0].ordinaryForecastEnabled = false
        XCTAssertEqual(try prepared(data).weeks.last?.earnedCents, 90_000)
        work.activity = .gift; work.ordinaryForecastEnabled = true
        XCTAssertFalse(work.participatesInOrdinaryForecast)
        XCTAssertEqual(data.income.count, 17)
    }
    @MainActor func testCancelledCalculationStopsBeforePreparingOrForecasting() async throws {
        let data = fixture(Array(repeating: 2000, count: 16)), input = try prepared(data)
        // Both tasks inherit this actor, so cancellation is set before they can
        // run. This tests the pure engine, not cancellation of a mock delay.
        let preparation = Task { try self.prepared(data) }
        preparation.cancel()
        do { _ = try await preparation.value; XCTFail("Cancelled preparation continued") }
        catch { XCTAssertTrue(error is CancellationError) }
        let projection = Task { try OrdinaryIncomeProjection.make(input, now: self.now, horizon: 104) }
        projection.cancel()
        do { _ = try await projection.value; XCTFail("Cancelled forecast continued") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}

import XCTest
@testable import PivotCore

final class SavingsBudgetTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-06-01T12:00:00Z")!
    private func data() -> AppData {
        var data = AppData(); data.ledger = .init(openingCents: ["2026": 20_000])
        let client = Client(name: "Contatto di prova", rateCents: 1000)
        let entry = IncomeEntry(clientID: client.id, clientName: client.name, date: now, minutes: 60, amountCents: 100_000, paidCents: 12_000)
        data.clients = [client]; data.income = [entry]
        data.payments = [.init(incomeID: entry.id, clientName: client.name, date: now, amountCents: 12_000)]
        return data
    }
    private func goal(data: inout AppData) throws -> SavingsGoal {
        let goal = SavingsGoal(name: "Obiettivo di prova", targetCents: 95_000)
        try SavingsAccounting.addGoal(goal, data: &data)
        return goal
    }
    private func balance(_ data: AppData) throws -> SavingsBalance {
        try SavingsAccounting.balance(XCTUnwrap(data.savingsBudget), payments: data.payments)
    }
    private func receipt(_ cents: Int, historical: Bool = false, data: inout AppData) {
        data.income[0].paidCents += cents
        data.payments.append(.init(incomeID: data.income[0].id, clientName: "Contatto di prova", date: now, amountCents: cents, excludedFromBudget: historical ? true : nil))
    }

    func testLegacyFundsInitializeOnceAndUnpaidIncomeNeverFundsGoals() throws {
        var data = data(); try SavingsAccounting.initialize(data: &data)
        XCTAssertEqual(try balance(data).freeCents, 32_000)
        XCTAssertEqual(data.income[0].outstandingCents, 88_000)
        data.ledger?.openingCents["2026"] = 0
        try SavingsAccounting.initialize(data: &data)
        XCTAssertEqual(try balance(data).freeCents, 32_000)
    }

    func testHistoricalOpeningReclassificationDoesNotDuplicateOrRemoveFunds() throws {
        var data = data(); try SavingsAccounting.initialize(data: &data)
        data.ledger?.openingCents["2026"] = 0
        receipt(20_000, historical: true, data: &data)
        XCTAssertEqual(data.ledger?.total(year: 2026, payments: data.payments), 32_000)
        XCTAssertEqual(try balance(data).freeCents, 32_000)
    }

    func testAdditionalHistoricalEarningsOnlyIncreaseAnnualTotal() throws {
        var data = data(); try SavingsAccounting.initialize(data: &data)
        receipt(30_000, historical: true, data: &data)
        XCTAssertEqual(data.ledger?.total(year: 2026, payments: data.payments), 62_000)
        XCTAssertEqual(try balance(data).freeCents, 32_000)
    }

    func testNewNormalReceiptIncreasesFundsWithoutAutomaticReservation() throws {
        var data = data(); _ = try goal(data: &data)
        receipt(10_000, data: &data)
        XCTAssertEqual(try balance(data).freeCents, 42_000)
        XCTAssertEqual(try balance(data).reservedCents, 0)
    }

    func testReservePreservesEarningsAndCannotReuseTheSameMoney() throws {
        var data = data(); let first = try goal(data: &data), second = try goal(data: &data)
        try SavingsAccounting.reserve(30_000, goalID: first.id, at: now, data: &data)
        XCTAssertEqual(try balance(data).freeCents, 2000)
        XCTAssertThrowsError(try SavingsAccounting.reserve(15_000, goalID: second.id, at: now, data: &data))
        XCTAssertEqual(data.savingsBudget?.allocations.count, 1)
        XCTAssertEqual(data.ledger?.total(year: 2026, payments: data.payments), 32_000)
    }

    func testReserveAndReleaseAreIdempotentByConfirmationID() throws {
        var data = data(); let goal = try goal(data: &data), id = UUID()
        try SavingsAccounting.reserve(10_000, goalID: goal.id, operationID: id, at: now, data: &data)
        try SavingsAccounting.reserve(10_000, goalID: goal.id, operationID: id, at: now.addingTimeInterval(1), data: &data)
        XCTAssertEqual(data.savingsBudget?.allocations.count, 1)
        XCTAssertThrowsError(try SavingsAccounting.reserve(11_000, goalID: goal.id, operationID: id, data: &data))
        let release = UUID()
        try SavingsAccounting.release(4000, goalID: goal.id, operationID: release, data: &data)
        try SavingsAccounting.release(4000, goalID: goal.id, operationID: release, data: &data)
        XCTAssertEqual(try balance(data).reservedCents, 6000)
        XCTAssertEqual(try balance(data).freeCents, 26_000)
    }

    func testExcessiveReleaseAndGoalOverfundingAreRejectedAtomically() throws {
        var data = data()
        let goal = SavingsGoal(name: "Piccolo obiettivo", targetCents: 5000)
        try SavingsAccounting.addGoal(goal, data: &data)
        XCTAssertThrowsError(try SavingsAccounting.reserve(6000, goalID: goal.id, data: &data))
        XCTAssertTrue(data.savingsBudget!.allocations.isEmpty)
        try SavingsAccounting.reserve(4000, goalID: goal.id, data: &data)
        XCTAssertThrowsError(try SavingsAccounting.release(5000, goalID: goal.id, data: &data))
        XCTAssertEqual(try balance(data).reservedCents, 4000)
    }

    func testRealExpenseCanRevealShortfallWithoutErasingReservations() throws {
        var data = data(); let goal = try goal(data: &data)
        try SavingsAccounting.reserve(20_000, goalID: goal.id, data: &data)
        let expense = BudgetExpense(amountCents: 40_000, date: now, description: "Spesa realmente avvenuta")
        try SavingsAccounting.expense(expense, data: &data)
        XCTAssertEqual(try balance(data).cashCents, -8000)
        XCTAssertEqual(try balance(data).shortfallCents, 28_000)
        XCTAssertEqual(try balance(data).reservedCents, 20_000)
        XCTAssertThrowsError(try SavingsAccounting.reserve(1, goalID: goal.id, data: &data))
        try SavingsAccounting.release(5000, goalID: goal.id, data: &data)
        XCTAssertEqual(try balance(data).reservedCents, 15_000)
    }

    func testRepeatedExpenseDoesNotDoubleCountAndConflictFails() throws {
        var data = data()
        var expense = BudgetExpense(amountCents: 350, date: now, description: "Descrizione di prova")
        try SavingsAccounting.expense(expense, data: &data)
        try SavingsAccounting.expense(expense, data: &data)
        XCTAssertEqual(try balance(data).spentCents, 350)
        expense.amountCents = 700
        XCTAssertThrowsError(try SavingsAccounting.expense(expense, data: &data))
        XCTAssertEqual(data.savingsBudget?.expenses.count, 1)
    }

    func testReceiptCorrectionShowsShortfallInsteadOfChangingGoals() throws {
        var data = data(); let goal = try goal(data: &data)
        try SavingsAccounting.reserve(30_000, goalID: goal.id, data: &data)
        try IncomeEdits.receipt(paymentID: data.payments[0].id, cents: 1000, data: &data)
        XCTAssertEqual(try balance(data).receivedCents, 21_000)
        XCTAssertEqual(try balance(data).shortfallCents, 9000)
        XCTAssertEqual(try balance(data).reservedCents, 30_000)
    }

    func testArchiveRequiresReleasedFundsAndKeepsJournal() throws {
        var data = data(); let goal = try goal(data: &data)
        try SavingsAccounting.reserve(1000, goalID: goal.id, data: &data)
        XCTAssertThrowsError(try SavingsAccounting.archive(goalID: goal.id, data: &data))
        try SavingsAccounting.release(1000, goalID: goal.id, data: &data)
        try SavingsAccounting.archive(goalID: goal.id, data: &data)
        XCTAssertTrue(data.savingsBudget!.goals[0].archived)
        XCTAssertEqual(data.savingsBudget?.allocations.count, 2)
        XCTAssertThrowsError(try SavingsAccounting.reserve(100, goalID: goal.id, data: &data))
    }

    func testFailedGoalCreationDoesNotInitializeOrMutateData() {
        var data = data()
        XCTAssertThrowsError(try SavingsAccounting.addGoal(.init(name: "  ", targetCents: 1000), data: &data))
        XCTAssertNil(data.savingsBudget)
    }

    func testBackupRoundTripPreservesBudgetAndExcludesImportedFunds() throws {
        var data = data(); let goal = try goal(data: &data)
        try SavingsAccounting.reserve(10_000, goalID: goal.id, at: now, data: &data)
        receipt(5000, historical: true, data: &data)
        let decoded = try BackupCodec.decode(BackupCodec.encode(data))
        XCTAssertEqual(try balance(decoded), try balance(data))
        XCTAssertEqual(decoded.payments.last?.excludedFromBudget, true)
        XCTAssertEqual(decoded.savingsBudget?.goals.first?.deadline, nil)
    }

    func testInvalidJournalAndIntegerOverflowFailClosed() throws {
        var data = data(); let goal = try goal(data: &data)
        data.savingsBudget?.allocations = [.init(goalID: goal.id, cents: Int.min, date: now)]
        XCTAssertThrowsError(try BackupCodec.decode(BackupCodec.encode(data)))
        data = self.data(); data.payments[0].amountCents = Int.max
        XCTAssertThrowsError(try SavingsAccounting.initialize(data: &data))
        XCTAssertNil(data.savingsBudget)
    }

    func testReceiptSumOverflowInLegacyBackupIsAnErrorNotACrash() throws {
        var data = data()
        data.income[0].amountCents = Int.max; data.income[0].paidCents = Int.max
        data.payments[0].amountCents = Int.max
        data.payments.append(.init(incomeID: data.income[0].id, clientName: "Contatto di prova", date: now, amountCents: 1))
        XCTAssertThrowsError(try BackupCodec.decode(BackupCodec.encode(data)))
    }
}

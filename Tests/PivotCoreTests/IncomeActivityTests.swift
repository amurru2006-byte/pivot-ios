import XCTest
@testable import PivotCore

final class IncomeActivityTests: XCTestCase {
    private let date = ISO8601DateFormatter().date(from: "2026-04-10T12:00:00Z")!
    private func register(client: Client, id: UUID = UUID(), paid: Int = 1500, minutes: Int = 60, data: inout AppData) throws -> UUID {
        try ManualIncome.register(id: id, client: client, date: date, minutes: minutes, amountCents: 2000,
            receivedCents: paid, paymentDate: date, notes: "Prova sintetica", data: &data)
    }
    func testPartialReceiptLeavesOriginalCompensationAndResidualSeparate() throws {
        var data = AppData(); let client = Client(name: "Cliente di prova", rateCents: 2000); data.clients = [client]
        _ = try register(client: client, data: &data)
        XCTAssertEqual(data.income[0].amountCents, 2000); XCTAssertEqual(data.income[0].paidCents, 1500)
        XCTAssertEqual(data.income[0].outstandingCents, 500); XCTAssertEqual(data.payments.count, 1)
    }
    func testRepeatedConfirmationIsIdempotentAndDifferentAmountConflicts() throws {
        var data = AppData(); let client = Client(name: "Cliente di prova", rateCents: 2000); data.clients = [client]
        let id = try register(client: client, data: &data)
        XCTAssertEqual(try register(client: client, id: id, data: &data), id)
        XCTAssertEqual(data.income.count, 1); XCTAssertEqual(data.payments.count, 1)
        XCTAssertThrowsError(try register(client: client, id: id, paid: 1000, data: &data))
        XCTAssertEqual(data.payments[0].amountCents, 1500)
    }
    func testGiftAndFixedWorkDoNotInventWorkedHours() throws {
        for activity in [IncomeActivityKind.gift, .work, .other] {
            var data = AppData(); let client = Client(name: "Contatto di prova", rateCents: 0, activity: activity, billing: .fixed)
            data.clients = [client]; _ = try register(client: client, minutes: 60, data: &data)
            XCTAssertEqual(data.income[0].minutes, 0); XCTAssertFalse(data.income[0].hasDuration)
            XCTAssertEqual(data.income[0].activityKind, activity)
            XCTAssertNoThrow(try BackupCodec.decode(BackupCodec.encodeCompact(data)))
        }
    }
    func testHourlyWorkAndLessonsRequireActualPositiveDuration() {
        for activity in [IncomeActivityKind.lesson, .work] {
            var data = AppData(); let client = Client(name: "Contatto di prova", rateCents: 2000, activity: activity, billing: .hourly)
            data.clients = [client]
            XCTAssertThrowsError(try register(client: client, minutes: 0, data: &data))
            XCTAssertTrue(data.income.isEmpty); XCTAssertTrue(data.payments.isEmpty)
        }
    }
    func testChangedContactAndOverpaymentFailWithoutPartialWrite() {
        var data = AppData(); let client = Client(name: "Contatto di prova", rateCents: 2000); data.clients = [client]
        XCTAssertThrowsError(try register(client: client, paid: 2100, data: &data))
        data.clients[0].rateCents = 2500
        XCTAssertThrowsError(try register(client: client, data: &data))
        XCTAssertTrue(data.income.isEmpty); XCTAssertTrue(data.payments.isEmpty)
    }
    func testUpdatingContactTypeDoesNotReclassifyOldIncome() throws {
        var data = AppData(); let client = Client(name: "Contatto di prova", rateCents: 2000); data.clients = [client]
        _ = try register(client: client, data: &data)
        _ = try ClientRegistry.save(name: client.name, rateCents: 0, cadence: .everyLesson,
            editingID: client.id, activity: .gift, billing: .fixed, data: &data)
        XCTAssertEqual(data.clients[0].activityKind, .gift)
        XCTAssertEqual(data.income[0].activityKind, .lesson); XCTAssertTrue(data.income[0].hasDuration)
        XCTAssertEqual(data.income[0].amountCents, 2000)
    }
    func testLegacyContactAndIncomeDefaultToHourlyLessons() throws {
        var data = AppData(); let client = Client(name: "Contatto di prova", rateCents: 2000); data.clients = [client]
        let entry = IncomeEntry(clientID: client.id, clientName: client.name, date: date, minutes: 60, amountCents: 2000)
        data.income = [entry]
        let decoded = try BackupCodec.decode(BackupCodec.encodeCompact(data))
        XCTAssertEqual(decoded.clients[0].activityKind, .lesson); XCTAssertEqual(decoded.clients[0].billingMode, .hourly)
        XCTAssertEqual(decoded.income[0].activityKind, .lesson); XCTAssertTrue(decoded.income[0].hasDuration)
    }
    func testContactStatisticsUseStableIdentityNotSharedName() throws {
        var data = AppData(); let a = Client(name: "Stesso nome Test", rateCents: 2000), b = Client(name: "Stesso nome Test", rateCents: 2000)
        data.clients = [a, b]; _ = try register(client: a, data: &data); _ = try register(client: b, paid: 1000, data: &data)
        XCTAssertEqual(try IncomeAnalytics.total(IncomeAnalytics.receipts(clientID: a.id, data: data), period: .all), 1500)
        XCTAssertEqual(try IncomeAnalytics.outstanding(clientID: a.id, data: data), 500)
        XCTAssertEqual(try IncomeAnalytics.outstanding(clientID: b.id, data: data), 1000)
    }
    func testYearOnlyReceiptsAppearInAllAndYearButNotInventedMonth() throws {
        let receipt = Payment(incomeID: UUID(), clientName: "Test", date: nil, amountCents: 1500, excludedFromBudget: true, receivedYear: 2026)
        XCTAssertEqual(try IncomeAnalytics.total([receipt], period: .all), 1500)
        XCTAssertEqual(try IncomeAnalytics.total([receipt], period: .year(2026)), 1500)
        XCTAssertEqual(try IncomeAnalytics.total([receipt], period: .month(year: 2026, month: 4)), 0)
        XCTAssertEqual(try IncomeAnalytics.undated(year: 2026, payments: [receipt]), 1500)
        XCTAssertEqual(try IncomeAnalytics.months(year: 2026, payments: [receipt]).map(\.cents), Array(repeating: 0, count: 12))
    }
    func testStatisticsUseReceiptDateRatherThanActivityDate() throws {
        let receipt = Payment(incomeID: UUID(), clientName: "Test", date: date, amountCents: 1500)
        XCTAssertEqual(try IncomeAnalytics.total([receipt], period: .month(year: 2026, month: 4)), 1500)
        XCTAssertEqual(try IncomeAnalytics.total([receipt], period: .month(year: 2026, month: 3)), 0)
        XCTAssertEqual(try IncomeAnalytics.total([receipt], period: .year(2025)), 0)
        XCTAssertEqual(try IncomeAnalytics.months(year: 2026, payments: [receipt])[3].cents, 1500)
    }
    func testStatisticsRejectOverflowAndInvalidMonthInsteadOfCrashing() {
        let receipts = [Payment(incomeID: UUID(), clientName: "Test", date: date, amountCents: Int.max), Payment(incomeID: UUID(), clientName: "Test", date: date, amountCents: 1)]
        XCTAssertThrowsError(try IncomeAnalytics.total(receipts, period: .all))
        XCTAssertThrowsError(try IncomeAnalytics.total([], period: .month(year: 2026, month: 13)))
    }
    func testUnpaidActivityDoesNotGenerateReceiptOrSavingsMoney() throws {
        var data = AppData(); let client = Client(name: "Contatto di prova", rateCents: 2000); data.clients = [client]
        _ = try register(client: client, paid: 0, data: &data)
        XCTAssertTrue(data.payments.isEmpty)
        try SavingsAccounting.initialize(data: &data)
        XCTAssertEqual(try SavingsAccounting.balance(data.savingsBudget!, payments: data.payments).freeCents, 0)
    }
}

import XCTest
@testable import PivotCore

final class CoachRecoveryRefinementTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-19T12:00:00+02:00")!
    private func request() throws -> CoachRecoveryRequest {
        var value = try XCTUnwrap(CoachRecoveryRequest.parse("Oggi non sono riuscito ad allenarmi, recuperiamo domani sera", now: now))
        value.targetID = "target-qa"
        return value
    }

    func testFollowUpRetainsOriginalTargetAndStatedMissedDayWhileChangingDateAndBand() throws {
        let original = try request()
        let value = try XCTUnwrap(original.refining("Domani no, meglio giovedì pomeriggio", now: now))
        XCTAssertEqual(value.targetID, "target-qa"); XCTAssertEqual(value.requestedAt, now)
        XCTAssertEqual(value.instruction, original.instruction)
        XCTAssertEqual(value.sourceDay.map(PivotDate.key), "2026-10-19")
        XCTAssertEqual(value.day.map(PivotDate.key), "2026-10-22")
        XCTAssertEqual(value.band, .afternoon)
        XCTAssertEqual(value.excludedDays.map(PivotDate.key), ["2026-10-20"])
    }

    func testDateOnlyFollowUpCannotChooseAMissingTargetOrLosePreviousBand() throws {
        var original = try request(); original.targetID = nil
        let value = try XCTUnwrap(original.refining("Preferisco dopodomani", now: now))
        XCTAssertNil(value.targetID); XCTAssertEqual(value.band, .evening)
        XCTAssertEqual(value.dayOffset, 2)
    }

    func testSuccessiveCorrectionsKeepExclusionsAndDoNotResurrectADeniedDay() throws {
        let first = try XCTUnwrap(request().refining("Non domani, meglio giovedì sera", now: now))
        let second = try XCTUnwrap(first.refining("Giovedì no, facciamo venerdì mattina", now: now))
        XCTAssertEqual(second.excludedDayOffsets, [1, 3]); XCTAssertEqual(second.dayOffset, 4)
        XCTAssertEqual(second.band, .morning); XCTAssertEqual(second.targetID, first.targetID)
        XCTAssertNil(second.refining("Meglio domani sera", now: now))
        XCTAssertNil(first.refining("Domani no, meglio domani", now: now))
    }

    func testUnparsedConditionsActivitiesTimesAndMedicalStatementsStayInConversation() throws {
        let original = try request()
        for text in ["Domani no", "Più tardi", "Meglio giovedì se sto bene", "Meglio giovedì dopo cena",
                     "Meglio giovedì per la lezione", "Meglio giovedì alle 19:30", "Meglio giovedì o venerdì",
                     "Meglio giovedì ma ho dolore", "Non meglio giovedì", "Cancella domani, meglio giovedì",
                     "Meglio il 25", "Meglio la prossima settimana", "Giovedì no, non facciamo venerdì"] {
            XCTAssertNil(original.refining(text, now: now), text)
        }
    }

    func testOnlyLatestRecoveryReplyWithinOneDayCanProvideContext() throws {
        let original = try request()
        let reply = CoachMessage(dayKey: PivotDate.key(now), role: .coach, text: "Recupero QA", createdAt: now, recoveryRequest: original)
        XCTAssertEqual(CoachRecoveryRequest.followUp("Meglio giovedì", messages: [reply], now: now)?.targetID, original.targetID)
        let unrelated = CoachMessage(dayKey: PivotDate.key(now), role: .coach, text: "Altro argomento QA", createdAt: now)
        let user = CoachMessage(dayKey: PivotDate.key(now), role: .user, text: "Altro argomento QA", createdAt: now)
        XCTAssertNil(CoachRecoveryRequest.followUp("Meglio giovedì", messages: [reply, unrelated], now: now))
        XCTAssertNil(CoachRecoveryRequest.followUp("Meglio giovedì", messages: [reply, user], now: now))
        XCTAssertNil(CoachRecoveryRequest.followUp("Meglio giovedì", messages: [reply], now: now.addingTimeInterval(86401)))
        XCTAssertNil(CoachRecoveryRequest.followUp("Meglio giovedì", messages: [reply], now: now.addingTimeInterval(-1)))
    }

    func testRefinementAcrossMidnightDoesNotMoveSourceDayOrExcludedDates() throws {
        let original = try XCTUnwrap(request().refining("Domani no, meglio giovedì", now: now))
        let nextDay = ISO8601DateFormatter().date(from: "2026-10-20T10:00:00+02:00")!
        let value = try XCTUnwrap(original.refining("Non domani, meglio venerdì sera", now: nextDay))
        XCTAssertEqual(value.excludedDays.map(PivotDate.key), ["2026-10-20", "2026-10-21"])
        XCTAssertEqual(value.day.map(PivotDate.key), "2026-10-23")
        XCTAssertEqual(value.sourceDay.map(PivotDate.key), "2026-10-19")
    }

    func testSevenDayAndExplicitThisWeekHorizonsNeverExpandSilently() throws {
        let original = try request()
        let later = now.addingTimeInterval(5 * 86400)
        XCTAssertNil(original.refining("Meglio dopodomani", now: later))
        let friday = ISO8601DateFormatter().date(from: "2026-10-23T12:00:00+02:00")!
        let thisWeek = try XCTUnwrap(CoachRecoveryRequest.parse("Recupera palestra questa settimana", now: friday))
        XCTAssertNil(thisWeek.refining("Meglio lunedì sera", now: friday))
        XCTAssertNotNil(thisWeek.refining("Meglio domenica mattina", now: friday))
        XCTAssertNil(thisWeek.refining("Meglio domani", now: friday.addingTimeInterval(-1)))
    }

    func testDSTUsesCivilDayOffsetsNotMultiplesOfTwentyFourHours() throws {
        let saturday = ISO8601DateFormatter().date(from: "2026-10-24T12:00:00+02:00")!
        let original = try XCTUnwrap(CoachRecoveryRequest.parse("Oggi non sono riuscito ad allenarmi, recuperiamo domani sera", now: saturday))
        let value = try XCTUnwrap(original.refining("Domani no, meglio lunedì mattina", now: saturday))
        XCTAssertEqual(value.dayOffset, 2); XCTAssertEqual(value.day.map(PivotDate.key), "2026-10-26")
        XCTAssertEqual(value.excludedDays.map(PivotDate.key), ["2026-10-25"])
        XCTAssertEqual(value.day!.timeIntervalSince(PivotDate.calendar.startOfDay(for: saturday)), 49 * 3600)
    }

    func testRefinementsRoundTripPrivatelyAndDoNotAddFieldsToCloudRequest() throws {
        let value = try XCTUnwrap(request().refining("Domani no, meglio giovedì pomeriggio", now: now))
        var data = AppData()
        data.coachState.messages = [.init(dayKey: PivotDate.key(now), role: .coach, text: "Recupero locale QA", createdAt: now, recoveryRequest: value)]
        XCTAssertEqual(try BackupCodec.decode(BackupCodec.encode(data)).coachState.messages[0].recoveryRequest, value)
        let snapshot = try CoachV8Snapshot.make(message: "Ciao", events: [], data: data, now: now, purpose: "conversation", protocolVersion: 3)
        let text = String(decoding: snapshot.encodedRequest, as: UTF8.self)
        for privateField in ["latestRefinement", "excludedDayOffsets", "target-qa", value.latestRefinement!] {
            XCTAssertFalse(text.contains(privateField))
        }
    }

    func testMalformedStoredExclusionsOrTextAreRejectedByBackup() throws {
        let original = try request()
        var invalids: [CoachRecoveryRequest] = []
        var value = original; value.excludedDayOffsets = [1]; invalids.append(value)
        value = original; value.excludedDayOffsets = [2, 2]; invalids.append(value)
        value = original; value.excludedDayOffsets = [-1]; invalids.append(value)
        value = original; value.excludedDayOffsets = [7]; invalids.append(value)
        value = original; value.latestRefinement = ""; invalids.append(value)
        value = original; value.latestRefinement = String(repeating: "x", count: 1501); invalids.append(value)
        for request in invalids {
            XCTAssertFalse(request.isValid)
            var data = AppData()
            data.coachState.messages = [.init(dayKey: PivotDate.key(now), role: .coach, text: "QA", createdAt: now, recoveryRequest: request)]
            XCTAssertThrowsError(try BackupCodec.decode(BackupCodec.encode(data)))
        }
    }
}

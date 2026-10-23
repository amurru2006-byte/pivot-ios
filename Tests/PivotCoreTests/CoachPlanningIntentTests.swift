import XCTest
@testable import PivotCore

final class CoachPlanningIntentTests: XCTestCase {
    private let aliases: Set<String> = ["e0", "e1", "e2", "e3", "e47"]
    private let now = ISO8601DateFormatter().date(from: "2026-10-19T12:00:00+02:00")!
    private var bytes: Data {
        Data(#"{"eventIDs":["e0"],"allowedDayOffsets":[1,3],"excludedDayOffsets":[2],"band":null,"earliestMinute":null,"latestMinute":null,"afterEventID":null}"#.utf8)
    }
    private func changed(_ change: (inout [String: Any]) -> Void) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        change(&object)
        return try JSONSerialization.data(withJSONObject: object)
    }
    private func value() throws -> CoachPlanningIntent { try .decode(bytes, knownAliases: aliases) }
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    func testStrictIntentPreservesProposedTargetOrderAndCarriesOnlyConstraints() throws {
        let data = try changed { $0["eventIDs"] = ["e2", "e0"]; $0["afterEventID"] = "e3"; $0["band"] = "evening" }
        let result = try CoachPlanningIntent.decode(data, knownAliases: aliases)
        XCTAssertEqual(result.eventIDs, ["e2", "e0"])
        XCTAssertEqual(result.allowedDayOffsets, [1, 3]); XCTAssertEqual(result.excludedDayOffsets, [2])
        XCTAssertEqual(result.band, .evening); XCTAssertEqual(result.afterEventID, "e3")
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("location"))
    }

    func testEveryNullableFieldRemainsRequiredAtTheWireBoundary() throws {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        for key in object.keys {
            let data = try changed { $0.removeValue(forKey: key) }
            XCTAssertThrowsError(try CoachPlanningIntent.decode(data, knownAliases: aliases), key)
        }
    }

    func testExtraFieldsCannotAddCalendarWritesPrivateMetadataOrCapabilities() throws {
        for key in ["title", "notes", "location", "health", "token", "calendarID", "apply", "tools", "proposedStart"] {
            let data = try changed { $0[key] = "synthetic untrusted extra" }
            XCTAssertThrowsError(try CoachPlanningIntent.decode(data, knownAliases: aliases), key)
        }
    }

    func testUnknownNativeMalformedOrOutOfRangeAliasesAreRejected() throws {
        for id in ["e10", "e48", "e99", "e00", "E0", "", "native-calendar-id-qa"] {
            let data = try changed { $0["eventIDs"] = [id] }
            XCTAssertThrowsError(try CoachPlanningIntent.decode(data, knownAliases: aliases), id)
        }
        let good = try changed { $0["eventIDs"] = ["e47"] }
        XCTAssertEqual(try CoachPlanningIntent.decode(good, knownAliases: aliases).eventIDs, ["e47"])
    }

    func testMissingDuplicateOrOversizedTargetSequencesAreRejected() throws {
        for ids in [[], ["e0", "e0"], ["e0", "e1", "e2", "e3"]] as [[String]] {
            let data = try changed { $0["eventIDs"] = ids }
            XCTAssertThrowsError(try CoachPlanningIntent.decode(data, knownAliases: aliases))
        }
    }

    func testInvalidMissingOrDuplicateDaysAreNeverClamped() throws {
        for days in [[], [-1], [7], [1, 1], [Int.max]] {
            let data = try changed { $0["allowedDayOffsets"] = days }
            XCTAssertThrowsError(try CoachPlanningIntent.decode(data, knownAliases: aliases))
        }
        for days in [[-1], [7], [2, 2], Array(0...7)] {
            let data = try changed { $0["excludedDayOffsets"] = days }
            XCTAssertThrowsError(try CoachPlanningIntent.decode(data, knownAliases: aliases))
        }
        let contradictory = try changed { $0["excludedDayOffsets"] = [1] }
        XCTAssertThrowsError(try CoachPlanningIntent.decode(contradictory, knownAliases: aliases))
    }

    func testWrongScalarTypesBooleanDaysFractionalMinutesAndNestedIDsAreRejected() throws {
        for (key, bad) in [("eventIDs", [["e0"]] as Any), ("allowedDayOffsets", [true] as Any),
                           ("earliestMinute", 30.5 as Any), ("latestMinute", "23:00" as Any),
                           ("band", ["evening"] as Any), ("afterEventID", 0 as Any)] {
            let data = try changed { $0[key] = bad }
            XCTAssertThrowsError(try CoachPlanningIntent.decode(data, knownAliases: aliases), key)
        }
    }

    func testInvalidOrContradictoryMinuteBoundsAndBandsRequireClarification() throws {
        for (key, bad) in [("earliestMinute", -1), ("earliestMinute", 1440), ("latestMinute", 0), ("latestMinute", 1441)] {
            let data = try changed { $0[key] = bad }
            XCTAssertThrowsError(try CoachPlanningIntent.decode(data, knownAliases: aliases))
        }
        for pair in [(1200, 1200), (1200, 1100)] {
            let data = try changed { $0["earliestMinute"] = pair.0; $0["latestMinute"] = pair.1 }
            XCTAssertThrowsError(try CoachPlanningIntent.decode(data, knownAliases: aliases))
        }
        let incompatible = try changed { $0["band"] = "morning"; $0["earliestMinute"] = 19 * 60 }
        XCTAssertThrowsError(try CoachPlanningIntent.decode(incompatible, knownAliases: aliases))
        let unknown = try changed { $0["band"] = "after-dinner-with-no-known-time" }
        XCTAssertThrowsError(try CoachPlanningIntent.decode(unknown, knownAliases: aliases))
    }

    func testRelativeReferenceMustExistAndCannotReferToTheActivityItself() throws {
        for id in ["e0", "e10", "private-native-id"] {
            let data = try changed { $0["afterEventID"] = id }
            XCTAssertThrowsError(try CoachPlanningIntent.decode(data, knownAliases: aliases))
        }
    }

    func testDuplicateTopLevelKeysAreRejectedBeforeJSONParserCollapsesThem() {
        let original = String(decoding: bytes, as: UTF8.self)
        for extra in [#", "band":"evening"}"#, #", "\u0062and":"evening"}"#] {
            let duplicated = Data((String(original.dropLast()) + extra).utf8)
            XCTAssertThrowsError(try CoachPlanningIntent.decode(duplicated, knownAliases: aliases))
        }
    }

    func testLegalEscapedKeysAndAliasesKeepTheSameMeaning() throws {
        let escaped = String(decoding: bytes, as: UTF8.self)
            .replacingOccurrences(of: #""band""#, with: #""\u0062and""#)
            .replacingOccurrences(of: #""e0""#, with: #""e\u0030""#)
        XCTAssertEqual(try CoachPlanningIntent.decode(Data(escaped.utf8), knownAliases: aliases), try value())
    }

    func testMalformedTopLevelArraysTruncatedAndOversizedDocumentsAreRejected() {
        for data in [Data(), Data("[]".utf8), Data("[".utf8) + bytes + Data("]".utf8), bytes.dropLast(),
                     bytes + Data(repeating: 32, count: 2048)] {
            XCTAssertThrowsError(try CoachPlanningIntent.decode(Data(data), knownAliases: aliases))
        }
    }

    func testEncodingRetainsRequiredNullsAndRoundTripsTheStrictBoundary() throws {
        let intent = try value(), encoded = try JSONEncoder().encode(intent)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(object.count, 7); XCTAssertTrue(object["band"] is NSNull)
        XCTAssertEqual(try CoachPlanningIntent.decode(encoded, knownAliases: aliases), intent)
    }

    func testKnownAliasContextIsBoundedAndCannotIntroduceAnUnsupportedAlias() {
        for known in [Set<String>(), Set((0...48).map { "e\($0)" }), ["e0", "native-id"]] as [Set<String>] {
            XCTAssertThrowsError(try CoachPlanningIntent.decode(bytes, knownAliases: known))
        }
    }

    func testIntervalsAreChronologicalAllowedWindowsNotInventedSlots() throws {
        let intent = try value()
        let intervals = try intent.intervals(knownAliases: aliases, anchor: now, now: now)
        XCTAssertEqual(intervals.map { PivotDate.key($0.start) }, ["2026-10-20", "2026-10-22"])
        XCTAssertEqual(intervals.map(\.duration), [86400, 86400])
        XCTAssertFalse(intervals.contains { PivotDate.key($0.start) == "2026-10-21" })
    }

    func testLaterReopeningNeverRebasesOriginalDaysOrResurrectsExpiredWindows() throws {
        let intent = try value()
        XCTAssertTrue(try intent.intervals(knownAliases: aliases, anchor: now, now: now.addingTimeInterval(8 * 86400)).isEmpty)
        let thursday = date("2026-10-22T15:00:00+02:00")
        let intervals = try intent.intervals(knownAliases: aliases, anchor: now, now: thursday)
        XCTAssertEqual(intervals.count, 1); XCTAssertEqual(intervals[0].start, thursday)
        XCTAssertEqual(PivotDate.key(intervals[0].end), "2026-10-23")
    }

    func testBandAndMinuteBoundsIntersectRatherThanOverwritingEachOther() throws {
        var intent = try value(); intent.band = .afternoon; intent.earliestMinute = 13 * 60 + 15; intent.latestMinute = 17 * 60 + 30
        let intervals = try intent.intervals(knownAliases: aliases, anchor: now, now: now)
        XCTAssertEqual(PivotDate.time(intervals[0].start), "13:15")
        XCTAssertEqual(PivotDate.time(intervals[0].end), "17:30")
        intent.allowedDayOffsets = [0]; intent.band = .morning; intent.earliestMinute = nil; intent.latestMinute = nil
        XCTAssertTrue(try intent.intervals(knownAliases: aliases, anchor: now, now: now).isEmpty)
    }

    func testMidnightMeansTheNextCivilDayNotAnEarlierEnd() throws {
        var intent = try value(); intent.allowedDayOffsets = [0]; intent.band = .evening; intent.earliestMinute = 22 * 60; intent.latestMinute = 1440
        let intervals = try intent.intervals(knownAliases: aliases, anchor: now, now: now)
        XCTAssertEqual(intervals.count, 1); XCTAssertEqual(intervals[0].duration, 7200)
        XCTAssertEqual(PivotDate.key(intervals[0].end), "2026-10-20")
    }

    func testWholeCivilDaysHonorBothDSTTransitions() throws {
        var intent = try value(); intent.allowedDayOffsets = [1]; intent.excludedDayOffsets = []
        let autumn = date("2026-10-24T12:00:00+02:00"), spring = date("2026-03-28T12:00:00+01:00")
        XCTAssertEqual(try intent.intervals(knownAliases: aliases, anchor: autumn, now: autumn).first?.duration, 25 * 3600)
        XCTAssertEqual(try intent.intervals(knownAliases: aliases, anchor: spring, now: spring).first?.duration, 23 * 3600)
    }

    func testAmbiguousOrNonexistentLocalClockTimesAreNotGuessed() throws {
        var intent = try value(); intent.allowedDayOffsets = [1]; intent.excludedDayOffsets = []; intent.earliestMinute = 150; intent.latestMinute = 180
        for anchor in [date("2026-10-24T12:00:00+02:00"), date("2026-03-28T12:00:00+01:00")] {
            XCTAssertThrowsError(try intent.intervals(knownAliases: aliases, anchor: anchor, now: anchor)) { error in
                XCTAssertEqual(error as? CoachPlanningIntent.Failure, .ambiguousLocalTime)
            }
        }
    }

    func testRelativeTimeRequiresExactlyTheBoundReferenceAndUsesItsActualTimestamp() throws {
        var intent = try value(); intent.afterEventID = "e3"
        XCTAssertThrowsError(try intent.intervals(knownAliases: aliases, anchor: now, now: now))
        let end = date("2026-10-20T19:30:00+02:00")
        let intervals = try intent.intervals(knownAliases: aliases, anchor: now, now: now, referenceEnds: ["e3": end])
        XCTAssertEqual(intervals[0].start, end)
        XCTAssertThrowsError(try intent.intervals(knownAliases: aliases, anchor: now, now: now, referenceEnds: ["e1": end]))
        XCTAssertThrowsError(try intent.intervals(knownAliases: aliases, anchor: now, now: now, referenceEnds: ["e3": end, "e1": end]))
        intent.afterEventID = nil
        XCTAssertThrowsError(try intent.intervals(knownAliases: aliases, anchor: now, now: now, referenceEnds: ["e3": end]))
    }

    func testInvalidDatesOrClockReversalNeverReachCalendarArithmetic() throws {
        var intent = try value(); intent.afterEventID = "e3"
        for invalid in [Date(timeIntervalSince1970: .nan), Date(timeIntervalSince1970: .infinity),
                        Date(timeIntervalSince1970: -1), Date(timeIntervalSince1970: 253_402_300_800)] {
            XCTAssertThrowsError(try intent.intervals(knownAliases: aliases, anchor: invalid, now: now))
            XCTAssertThrowsError(try intent.intervals(knownAliases: aliases, anchor: now, now: invalid))
            XCTAssertThrowsError(try intent.intervals(knownAliases: aliases, anchor: now, now: now, referenceEnds: ["e3": invalid]))
        }
        XCTAssertThrowsError(try value().intervals(knownAliases: aliases, anchor: now, now: now.addingTimeInterval(-1)))
    }
}

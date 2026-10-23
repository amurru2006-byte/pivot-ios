import XCTest
@testable import PivotCore

final class CoachV4ProtocolTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-19T12:00:00+02:00")!
    private var event: CalendarItem {
        .init(id: "private-logical-qa", eventIdentifier: "private-native-qa", calendarIdentifier: "qa-calendar",
            calendarTitle: "Private account QA", title: "Private workout QA", start: now.addingTimeInterval(-7200), end: now.addingTimeInterval(-3600),
            location: "Private address QA", notes: "Private notes QA", colorHex: "7EE6CD", isAllDay: false, writable: true, kind: .workout)
    }
    private var data: AppData {
        var value = AppData(); value.updatedAt = now
        value.rules[event.id] = .init(flexibility: .movable, minimumMinutes: 60, travelConfirmed: true)
        return value
    }
    private func snapshot(version: Int = 4) throws -> CoachV8Snapshot {
        try CoachV8Snapshot.make(message: "Recuperiamo domani pomeriggio", events: [event], data: data, now: now,
            purpose: "conversation", protocolVersion: version, calendarScope: .week)
    }
    private var intent: String {
        #"{"eventIDs":["e0"],"allowedDayOffsets":[1],"excludedDayOffsets":[2],"band":"afternoon","earliestMinute":null,"latestMinute":null,"afterEventID":null}"#
    }
    private func response(_ snapshot: CoachV8Snapshot, intent: String? = nil) -> Data {
        Data(#"{"version":4,"requestID":"\#(snapshot.request.requestID)","mode":"recover","eventIDs":[],"reply":"Proposta da verificare","draft":null,"rewrittenMessage":null,"actions":[],"planning":\#(intent ?? self.intent)}"#.utf8)
    }
    func testV4SnapshotHasBoundedEmptyPlanningContextAndStillOmitsNativeAndHealthData() throws {
        let value = try snapshot(), json = String(decoding: value.encodedRequest, as: UTF8.self)
        XCTAssertEqual(value.request.version, 4); XCTAssertEqual(value.request.planningContext, [])
        XCTAssertLessThanOrEqual(value.encodedRequest.count, 24_000)
        for secret in [event.id, event.eventIdentifier, event.calendarIdentifier, event.calendarTitle, event.title, event.location, event.notes, "health", "latitude"] {
            XCTAssertFalse(json.contains(secret))
        }
        XCTAssertEqual(value.request.historyOmittedCount, 0)
        XCTAssertEqual(value.request.events.map(\.id), ["e0"])
    }
    func testV2V3AndRewriteKeepTheirExistingWireFields() throws {
        for version in [2, 3] {
            let value = try snapshot(version: version)
            XCTAssertFalse(String(decoding: value.encodedRequest, as: UTF8.self).contains("planningContext"))
            XCTAssertEqual(value.request.version, version)
        }
        let rewrite = try CoachV8Snapshot.make(message: "Testo QA", events: [event], data: data, now: now,
            purpose: "rewrite", protocolVersion: 4, calendarScope: .week)
        XCTAssertEqual(rewrite.request.version, 2); XCTAssertTrue(rewrite.request.events.isEmpty)
        XCTAssertNil(rewrite.request.planningContext)
    }
    func testRecoveryResponseDescribesConstraintsNotCalendarMoves() throws {
        let value = try snapshot(), decoded = try CoachV8Response.decode(response(value), for: value.request)
        XCTAssertEqual(decoded.mode, .recover); XCTAssertTrue(decoded.eventIDs.isEmpty)
        XCTAssertEqual(decoded.planning?.eventIDs, ["e0"])
        XCTAssertEqual(decoded.planning?.allowedDayOffsets, [1]); XCTAssertEqual(decoded.planning?.excludedDayOffsets, [2])
        XCTAssertTrue(decoded.actions?.isEmpty == true); XCTAssertNil(decoded.draft)
        let selection = try CoachPlanningSelection.prepare(XCTUnwrap(decoded.planning), responseRequestID: decoded.requestID,
            snapshot: value, access: .init(calendar: true, online: true), events: [event], data: data, now: now)
        XCTAssertEqual(selection.sources, [event]); XCTAssertTrue(data.moves.isEmpty)
    }
    func testNestedPlanningRequiresAllSevenExactKeysAndValidUnambiguousAliases() throws {
        let value = try snapshot()
        for bad in [intent.replacingOccurrences(of: "e0", with: "e99"),
                    intent.replacingOccurrences(of: #"["e0"]"#, with: #"["e0","e0"]"#),
                    intent.replacingOccurrences(of: #""excludedDayOffsets":[2]"#, with: #""excludedDayOffsets":[1]"#),
                    intent.replacingOccurrences(of: #","afterEventID":null"#, with: ""),
                    String(intent.dropLast()) + #","nativeID":"not-allowed"}"#,
                    intent.replacingOccurrences(of: #""allowedDayOffsets":[1]"#, with: #""allowedDayOffsets":[7]"#),
                    intent.replacingOccurrences(of: #""allowedDayOffsets":[1]"#, with: #""allowedDayOffsets":[]"#),
                    intent.replacingOccurrences(of: #""allowedDayOffsets":[1]"#, with: #""allowedDayOffsets":[true]"#),
                    intent.replacingOccurrences(of: #""afterEventID":null"#, with: #""afterEventID":"e0""#),
                    intent.replacingOccurrences(of: #""latestMinute":null"#, with: #""latestMinute":600"#), "null", "[]"] {
            XCTAssertNotEqual(bad, intent, "Every negative fixture must actually change the intent")
            XCTAssertThrowsError(try CoachV8Response.decode(response(value, intent: bad), for: value.request))
        }
    }
    func testOriginalBytesRejectDuplicateTopLevelAndUnicodeEscapedNestedKeys() throws {
        let value = try snapshot()
        let duplicate = intent.replacingOccurrences(of: #""eventIDs":["e0"]"#,
            with: #""eventIDs":["e0"],"event\u0049Ds":["e0"]"#)
        XCTAssertThrowsError(try CoachV8Response.decode(response(value, intent: duplicate), for: value.request))
        let raw = String(decoding: response(value), as: UTF8.self)
            .replacingOccurrences(of: #""mode":"recover""#, with: #""mode":"conversation","mode":"recover""#)
        XCTAssertThrowsError(try CoachV8Response.decode(Data(raw.utf8), for: value.request))
    }
    func testRecoveryCannotFallThroughToLegacyPlanOrWritePipeline() throws {
        let value = try snapshot(), original = data, before = try BackupCodec.encode(original)
        let decoded = try CoachV8Response.decode(response(value), for: value.request)
        XCTAssertThrowsError(try CoachV8Planner.preview(decoded, snapshot: value, events: [event], data: original, now: now))
        XCTAssertEqual(try BackupCodec.encode(original), before)
    }
    func testRecoveryModeCannotBeInjectedIntoOldProtocol() throws {
        let value = try snapshot(version: 3)
        let raw = String(decoding: response(value), as: UTF8.self).replacingOccurrences(of: #""version":4"#, with: #""version":3"#)
        XCTAssertThrowsError(try CoachV8Response.decode(Data(raw.utf8), for: value.request))
    }
    func testNonRecoveryModeCannotCarryHiddenConstraintsOrActions() throws {
        let value = try snapshot()
        let raw = String(decoding: response(value), as: UTF8.self).replacingOccurrences(of: #""mode":"recover""#, with: #""mode":"conversation""#)
        XCTAssertThrowsError(try CoachV8Response.decode(Data(raw.utf8), for: value.request))
        let valid = raw.replacingOccurrences(of: #""planning":\#(intent)"#, with: #""planning":null"#)
        XCTAssertEqual(try CoachV8Response.decode(Data(valid.utf8), for: value.request).mode, .conversation)
    }
    func testJSONKeyIntegrityHandlesArraysQuotedPunctuationAndSeparateObjects() {
        for raw in [#"{"a":[{"x":1},{"x":2}],"b":"quoted \\\" { : , }"}"#,
                    #"{"a":{},"b":[],"c":null}"#] {
            XCTAssertTrue(CoachJSONIntegrity.hasUniqueObjectKeys(Data(raw.utf8)))
        }
        XCTAssertFalse(CoachJSONIntegrity.hasUniqueObjectKeys(Data(#"{"a":[{"x":1,"x":2}]}"#.utf8)))
        XCTAssertFalse(CoachJSONIntegrity.hasUniqueObjectKeys(Data()))
        XCTAssertFalse(CoachJSONIntegrity.hasUniqueObjectKeys(Data("{}".utf8), maximumBytes: 0))
    }
    func testJSONKeyIntegrityBoundsDepthAndBytesBeforeParsing() {
        let deep = "{\"a\":" + String(repeating: "[", count: 33) + "0" + String(repeating: "]", count: 33) + "}"
        XCTAssertFalse(CoachJSONIntegrity.hasUniqueObjectKeys(Data(deep.utf8)))
        XCTAssertFalse(CoachJSONIntegrity.hasUniqueObjectKeys(Data(("{\"a\":\"" + String(repeating: "x", count: 32_000) + "\"}").utf8)))
    }
}

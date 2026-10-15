import XCTest
@testable import PivotCore

final class WorkoutRestChimeTests: XCTestCase {
    func testCueIsExactlyTwoSecondMonoPCMNotAnAlarmLoop() throws {
        let data = try XCTUnwrap(WorkoutRestChime.waveData(volume: 0.5))
        XCTAssertEqual(data.count, 44 + 44_100 * 2 * 2)
        XCTAssertEqual(String(decoding: data[0..<4], as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: data[8..<12], as: UTF8.self), "WAVE")
        XCTAssertEqual(String(decoding: data[36..<40], as: UTF8.self), "data")
        XCTAssertEqual(u32(data, 4), UInt32(data.count - 8))
        XCTAssertEqual(u16(data, 20), 1) // PCM
        XCTAssertEqual(u16(data, 22), 1) // mono
        XCTAssertEqual(u32(data, 24), 44_100)
        XCTAssertEqual(u16(data, 34), 16)
        XCTAssertEqual(u32(data, 40), UInt32(data.count - 44))
    }
    func testZeroGainIsSilentAndInvalidGainIsRejected() throws {
        let zero = try XCTUnwrap(WorkoutRestChime.waveData(volume: 0))
        XCTAssertTrue(zero.dropFirst(44).allSatisfy { $0 == 0 })
        for value in [-0.01, 1.01, .nan, .infinity, -.infinity] {
            XCTAssertNil(WorkoutRestChime.waveData(volume: value))
        }
    }
    func testCueGainChangesOnlySamplesAndLeavesHeadroom() throws {
        let low = try XCTUnwrap(WorkoutRestChime.waveData(volume: 0.25))
        let high = try XCTUnwrap(WorkoutRestChime.waveData(volume: 1))
        XCTAssertEqual(low.prefix(44), high.prefix(44))
        var maximum = 0
        for index in stride(from: 44, to: high.count, by: 2) {
            let loud = Int(Int16(bitPattern: u16(high, index)))
            let quiet = Int(Int16(bitPattern: u16(low, index)))
            maximum = max(maximum, abs(loud))
            XCTAssertLessThanOrEqual(abs(loud - quiet * 4), 2)
        }
        XCTAssertGreaterThan(maximum, 1000)
        XCTAssertLessThan(maximum, Int(Double(Int16.max) * 0.71))
    }
    func testAllThreeTonesArePresentAndTailIsSilent() throws {
        let data = try XCTUnwrap(WorkoutRestChime.waveData(volume: 0.5))
        for onset in [0.0, 0.65, 1.30] {
            let first = 44 + Int((onset + 0.01) * 44_100) * 2
            XCTAssertTrue(data[first..<(first + 1000)].contains { $0 != 0 })
        }
        let tail = 44 + Int(1.75 * 44_100) * 2
        XCTAssertTrue(data[tail...].allSatisfy { $0 == 0 })
    }
    private func u16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }
    private func u32(_ data: Data, _ offset: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 | (UInt32(data[offset + $1]) << ($1 * 8)) }
    }
}

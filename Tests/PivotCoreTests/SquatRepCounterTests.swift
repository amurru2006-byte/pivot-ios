import XCTest
@testable import PivotCore

final class SquatRepCounterTests: XCTestCase {
    private func feed(_ angle: Double?, from start: Double, into counter: inout SquatRepCounter) {
        for index in 0...2 { counter.observe(kneeAngle: angle, at: start + Double(index) * 0.1) }
    }

    func testCountsFullCyclesOnceEvenWhenHoldingEitherPosition() {
        var counter = SquatRepCounter()
        feed(165, from: 0, into: &counter)
        feed(110, from: 0.3, into: &counter)
        feed(110, from: 0.6, into: &counter)
        XCTAssertEqual(counter.repetitions, 0)
        feed(165, from: 0.9, into: &counter)
        feed(165, from: 1.2, into: &counter)
        feed(110, from: 1.5, into: &counter)
        feed(165, from: 1.8, into: &counter)
        XCTAssertEqual(counter.repetitions, 2)
    }

    func testStartsStandingAndRejectsPartialMovementAndOneFrameNoise() {
        var counter = SquatRepCounter()
        feed(100, from: 0, into: &counter)
        feed(165, from: 0.3, into: &counter)
        feed(130, from: 0.6, into: &counter)
        counter.observe(kneeAngle: 115, at: 0.9)
        feed(165, from: 1, into: &counter)
        XCTAssertEqual(counter.repetitions, 0)
        XCTAssertEqual(counter.tracking, .ready)
    }

    func testInvalidPoseAndCaptureGapCancelOnlyTheIncompleteCycle() {
        var counter = SquatRepCounter()
        feed(165, from: 0, into: &counter)
        feed(110, from: 0.3, into: &counter)
        feed(165, from: 0.6, into: &counter)
        feed(110, from: 0.9, into: &counter)
        counter.observe(kneeAngle: nil, at: 1.2)
        XCTAssertEqual(counter.tracking, .reposition)
        feed(165, from: 1.3, into: &counter)
        feed(110, from: 1.6, into: &counter)
        feed(165, from: 2.4, into: &counter)
        XCTAssertEqual(counter.repetitions, 1)
        feed(110, from: 2.7, into: &counter)
        feed(165, from: 3, into: &counter)
        XCTAssertEqual(counter.repetitions, 2)
    }
}

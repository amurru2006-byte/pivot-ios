import Foundation

/// Counts a stable standing–bent–standing sequence in the lateral camera plane.
/// Thresholds classify movement for counting only.
struct SquatRepCounter {
    enum Tracking: Equatable { case reposition, stand, ready, rising }

    private enum Phase { case needsStanding, standing, bent }
    private var phase = Phase.needsStanding
    private var qualifyingSince: Double?
    private var lastTime: Double?
    private(set) var repetitions = 0
    private(set) var tracking = Tracking.reposition

    mutating func observe(kneeAngle: Double?, at seconds: Double) {
        guard seconds.isFinite else { loseTracking(); return }
        if let lastTime, seconds <= lastTime || seconds - lastTime > 0.45 {
            loseTracking()
        }
        lastTime = seconds
        guard let kneeAngle, (0...180).contains(kneeAngle) else { loseTracking(); return }

        let qualifies: Bool
        switch phase {
        case .needsStanding, .bent: qualifies = kneeAngle >= 155
        case .standing: qualifies = kneeAngle <= 120
        }
        guard qualifies else { qualifyingSince = nil; return }
        let start = qualifyingSince ?? seconds
        qualifyingSince = start
        guard seconds - start >= 0.18 else {
            if phase == .needsStanding { tracking = .stand }
            return
        }
        qualifyingSince = nil
        switch phase {
        case .needsStanding:
            phase = .standing
            tracking = .ready
        case .standing:
            phase = .bent
            tracking = .rising
        case .bent:
            repetitions += 1
            phase = .standing
            tracking = .ready
        }
    }

    mutating func loseTracking() {
        phase = .needsStanding
        qualifyingSince = nil
        lastTime = nil
        tracking = .reposition
    }
}

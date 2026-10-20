import Foundation

struct WorkoutRestAudioSettings: Codable, Equatable {
    var enabled = false
    var volumeStep = 5
    var isValid: Bool { (1...20).contains(volumeStep) }
    var gain: Double { Double(volumeStep) / 20 }
    var soundName: String { "PivotRest-\(volumeStep).wav" }
}

/// One system alarm owns both the cue and the system's media interruption.
/// There is no independent music-volume timer, second player or audible fallback.
enum WorkoutRestAlarm {
    enum Decision: Equatable {
        case cancel
        case keepExisting
        case schedule(Date)
    }
    enum Scheduling: Equatable { case keep, dismissedOrUncertain, replace }

    static func scheduling(sessionID: UUID, deadline: Date, volumeStep: Int,
                           receipt: WorkoutRestAlarmReceipt?, exists: Bool, force: Bool) -> Scheduling {
        if !force, receipt?.matches(sessionID: sessionID, deadline: deadline) == true {
            if !exists { return .dismissedOrUncertain }
            if receipt?.volumeStep == volumeStep { return .keep }
        }
        return .replace
    }

    static func decision(session: TrainingSession, settings: WorkoutRestAudioSettings, now: Date) -> Decision {
        guard settings.isValid, settings.enabled, session.end == nil, let rest = session.rest,
              let deadline = rest.deadline, deadline.timeIntervalSinceReferenceDate.isFinite,
              now.timeIntervalSinceReferenceDate.isFinite else { return .cancel }
        // An expired timer must NOT dismiss an alerting manual-stop alarm or
        // create a replacement. Pause/reset/next/finish remain explicit actions.
        return deadline > now ? .schedule(deadline) : .keepExisting
    }

    // Device alarm namespace is independent from the technical probe and other
    // app alarms. A collision between restored session IDs is checked before use.
    static func id(sessionID: UUID) -> UUID {
        let u = sessionID.uuid
        return UUID(uuid: (0xA8, 0x1D, 0xA1, 0x0D, u.4, u.5, u.6, u.7, u.8, u.9, u.10, u.11, u.12, u.13, u.14, u.15))
    }
    static func owns(_ id: UUID) -> Bool { id.uuidString.hasPrefix("A81DA10D-") }
    static func uniqueIDs(_ sessions: [TrainingSession]) -> Bool {
        let ids = sessions.map { id(sessionID: $0.id) }
        return Set(ids).count == ids.count
    }
}

/// Device-local scheduling acknowledgement. Not part of a portable backup:
/// restoring financial/training data cannot silently rearm a dismissed alarm.
struct WorkoutRestAlarmReceipt: Codable, Equatable {
    var sessionID: UUID
    var deadline: Date
    var volumeStep: Int
    var isValid: Bool { deadline.timeIntervalSinceReferenceDate.isFinite && (1...20).contains(volumeStep) }
    func matches(sessionID: UUID, deadline: Date) -> Bool {
        self.sessionID == sessionID && self.deadline == deadline
    }
}

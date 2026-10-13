import Foundation

struct HealthRefreshReport: Equatable {
    var readAt: Date
    var workoutSamples: Int
    var sleepDays: Int
    var workoutsApplied: Int
    var sleepDaysApplied: Int
    var sleepEventsCompleted: Int
    var pendingDecisions: Int

    var appliedChanges: Int { workoutsApplied + sleepDaysApplied + sleepEventsCompleted }

    static func make(workouts: [HealthWorkoutSummary], sleeps: [String: HealthSleepSummary],
                     before: AppData, after: AppData, readAt: Date) -> HealthRefreshReport {
        let workoutsApplied = after.records.values.filter { record in
            guard let health = record.health else { return false }
            let old = before.records[record.id]
            return old?.health != health || old?.status != record.status
                || old?.actualStart != record.actualStart || old?.actualEnd != record.actualEnd
        }.count
        let sleepDaysApplied = after.checkIns.values.filter { check in
            guard check.sleep?.importedFromHealth == true else { return false }
            let old = before.checkIns[check.id]
            return old?.sleep?.importedFromHealth != true
                || old?.sleep?.bedtime != check.sleep?.bedtime
                || old?.sleep?.durationSeconds != check.sleep?.durationSeconds
                || old?.sleep?.awakenings != check.sleep?.awakenings
                || old?.sleep?.interruptionSeconds != check.sleep?.interruptionSeconds
                || old?.healthWakeTime != check.healthWakeTime
        }.count
        let sleepEventsCompleted = after.records.values.filter { record in
            guard record.healthSleep?.importedFromHealth == true else { return false }
            let old = before.records[record.id]
            return old?.healthSleep?.importedFromHealth != true
                || old?.actualStart != record.actualStart || old?.actualEnd != record.actualEnd
                || old?.status != record.status
        }.count
        let pending = (after.workoutReviews ?? []).filter { !$0.resolved && !$0.dismissed }.count
        return .init(readAt: readAt, workoutSamples: workouts.count, sleepDays: sleeps.count,
                     workoutsApplied: workoutsApplied, sleepDaysApplied: sleepDaysApplied,
                     sleepEventsCompleted: sleepEventsCompleted, pendingDecisions: pending)
    }
}

import Foundation

/// Explicit LOCAL adoption of a comparable-workload estimate. No weights,
/// symptoms, notes or provider payload. Never shortens the Calendar duration.
struct CoachPlanningDurationChoice: Codable, Equatable {
    var sourceID: String
    var planID: UUID
    var dayID: String
    var activityMinutes: Int
    var sampleIDs: [UUID]
    var sampleMinutes: [Double]
    var workload: [TrainingDurationWorkload]
    var phase: TrainingPhase?
    var confirmedAt: Date
    var provisional: Bool { sampleIDs.count < 5 }
    var observedMedianMinutes: Int {
        let sorted = sampleMinutes.sorted(), middle = sorted.count / 2
        guard !sorted.isEmpty else { return activityMinutes }
        return Int(ceil(sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]))
    }
    var isValid: Bool {
        !sourceID.isEmpty && sourceID.count <= 2000 && !dayID.isEmpty && dayID.count <= 500
            && (1...1440).contains(activityMinutes) && CoachPlanningSession.validDate(confirmedAt)
            && (3...8).contains(sampleIDs.count) && sampleIDs.count == sampleMinutes.count
            && Set(sampleIDs).count == sampleIDs.count
            && sampleMinutes.allSatisfy { $0.isFinite && $0 > 0 && $0 <= 1440 }
            && activityMinutes >= observedMedianMinutes
            && (1...40).contains(workload.count) && Set(workload.map(\.exerciseID)).count == workload.count
            && workload.allSatisfy(\.isValid)
    }
    enum Failure: LocalizedError {
        case selection, insufficient, changed
        var errorDescription: String? {
            switch self {
            case .selection: return "Scegli esplicitamente la scheda e il giorno per questa attività palestra."
            case .insufficient: return "Non ci sono almeno tre sedute complete confrontabili. Mantengo la durata del Calendario."
            case .changed: return "La scheda o i dati della stima sono cambiati. Ricalcola e conferma la durata; non la sostituisco automaticamente."
            }
        }
    }
    static func make(source: CalendarItem, planID: UUID, dayID: String,
                     library: TrainingLibrary, now: Date) throws -> Self {
        let plans = library.plans.filter { $0.id == planID }
        guard CalendarEventBackup.valid(source), source.writable, !source.isAllDay,
              source.kind == .workout, CardioKind.suggested(source.title) == nil,
              plans.count == 1, let plan = plans.first,
              CoachPlanningSession.validDate(now), source.end > source.start,
              source.end.timeIntervalSince(source.start) <= 86400 else { throw Failure.selection }
        let days = plan.payload.days.filter { $0.id == dayID }
        guard days.count == 1, let day = days.first else { throw Failure.selection }
        let calendarMinutes = Int(ceil(source.end.timeIntervalSince(source.start) / 60))
        // Overall comparable history, not a time-band prediction silently reused
        // for a different proposed hour. The estimate remains local and visible.
        guard let estimate = TrainingDurationEstimate.make(plan: plan, day: day, library: library,
            calendarMinutes: calendarMinutes, now: now), estimate.source == .historyMedian else { throw Failure.insufficient }
        let session = library.makeSession(plan: plan, day: day, eventID: nil, now: now)
        let result = Self(sourceID: source.id, planID: planID, dayID: dayID,
            activityMinutes: max(calendarMinutes, estimate.schedulingMinutes), sampleIDs: estimate.sampleIDs,
            sampleMinutes: estimate.sampleMinutes, workload: TrainingDurationWorkload.make(session),
            phase: session.phase, confirmedAt: now)
        guard result.isValid else { throw Failure.selection }
        return result
    }
    func revalidated(source: CalendarItem, library: TrainingLibrary, now: Date) throws {
        guard isValid, sourceID == source.id, confirmedAt <= now else { throw Failure.changed }
        var current: Self
        do { current = try Self.make(source: source, planID: planID, dayID: dayID, library: library, now: now) }
        catch { throw Failure.changed }
        current.confirmedAt = confirmedAt
        guard current == self else { throw Failure.changed }
    }
}

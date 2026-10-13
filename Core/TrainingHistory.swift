import Foundation

enum TrainingHistory {
    enum HistoryError: LocalizedError {
        case changed, missing, unavailable
        var errorDescription: String? {
            switch self {
            case .changed: return "Questo allenamento è cambiato mentre confermavi. Controllalo e riprova."
            case .missing: return "Questo allenamento non è più nello storico."
            case .unavailable: return "Attendi il caricamento o il ripristino prima di eliminare un allenamento."
            }
        }
    }
    static func matches(_ session: TrainingSession, planID: UUID, dayID: String?, dayName: String, library: TrainingLibrary) -> Bool {
        guard session.planID == planID else { return false }
        if let recordedID = session.dayID, let dayID { return recordedID == dayID }
        // Old backups have no day ID. Match exact normalized names, including
        // names preserved in revisions, only when that name is unambiguous.
        let key = EventCoalescer.normalized(session.dayName)
        guard let dayID, let plan = library.plans.first(where: { $0.id == planID }) else {
            return key == EventCoalescer.normalized(dayName)
        }
        let days = plan.payload.days + (plan.revisions ?? []).flatMap { $0.payload.days }
        let candidates = Set(days.filter { EventCoalescer.normalized($0.name) == key }.map(\.id))
        return candidates == Set([dayID])
    }
    static func sessions(planID: UUID, dayID: String?, dayName: String, library: TrainingLibrary) -> [TrainingSession] {
        library.sessions.filter { matches($0, planID: planID, dayID: dayID, dayName: dayName, library: library) }
            .sorted { $0.start == $1.start ? $0.id.uuidString < $1.id.uuidString : $0.start > $1.start }
    }
    static func performedSets(_ session: TrainingSession) -> Int {
        session.exercises.filter { $0.skipped != true }.reduce(0) { total, log in
            total + log.sets.filter { $0.done && $0.canComplete(log.exercise) }.count
        }
    }
    /// Atomic copy: a stale confirmation cannot remove a newly edited workout.
    static func removing(_ expected: TrainingSession, from data: AppData, now: Date = Date()) throws -> AppData {
        guard var library = data.training, let saved = library.sessions.first(where: { $0.id == expected.id }) else { throw HistoryError.missing }
        guard saved == expected else { throw HistoryError.changed }
        var result = data
        library.sessions.removeAll { $0.id == saved.id }
        library.achievements = TrainingRecords.reconciled(library: library, profile: data.strengthProfile, now: now)
        try library.validate()
        result.training = library
        if let eventID = saved.calendarEventID, var record = result.records[eventID], record.trainingSessionID == saved.id {
            record.trainingSessionID = nil
            // Never erase manually corrected timing or independent Health/cardio
            // data. Legacy records without provenance are preserved as well.
            if record.actualStart == saved.start, record.actualEnd == saved.end,
               record.timingFromCalendar != true, record.health == nil, record.cardio == nil,
               record.status == (saved.end == nil ? .running : .completed) {
                if let other = library.sessions.filter({ $0.calendarEventID == eventID }).max(by: { $0.updatedAt < $1.updatedAt }) {
                    record = TrainingTiming.merging(other, previous: nil, into: record, now: now)
                } else {
                    record.actualStart = nil; record.actualEnd = nil; record.activeMinutes = 0
                    record.status = .pending; record.timingFromCalendar = nil
                }
            }
            record.updatedAt = now
            result.records[eventID] = record
        }
        result.updatedAt = now
        return result
    }
}

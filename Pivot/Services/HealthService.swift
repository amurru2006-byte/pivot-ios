import Foundation
import HealthKit
import Combine

@MainActor
final class HealthService: ObservableObject {
    @Published private(set) var status = "Salute non collegata"
    @Published private(set) var isRefreshing = false
    @Published private(set) var workouts: [HealthWorkoutSummary] = []
    @Published private(set) var lastRefresh: Date?
    private let healthStore = HKHealthStore()
    private var sleepSamples: [HKCategorySample] = []
    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        let identifiers: [HKQuantityTypeIdentifier] = [.activeEnergyBurned, .distanceWalkingRunning, .heartRate]
        for identifier in identifiers {
            if let type = HKObjectType.quantityType(forIdentifier: identifier) { types.insert(type) }
        }
        return types
    }
    func connect(store: PivotStore, events: [CalendarItem]) async {
        guard HKHealthStore.isHealthDataAvailable() else { status = "Salute non disponibile su questo dispositivo"; return }
        do {
            // Read only. No workouts or sleep are ever written back to Apple Health.
            try await healthStore.requestAuthorization(toShare: [], read: readTypes)
            guard store.change({ $0.settings.healthEnabled = true }) else { return }
            await refresh(store: store, events: events, force: true)
        } catch {
            status = "Collegamento non riuscito: \(error.localizedDescription). Verifica le autorizzazioni e la firma AltStore."
        }
    }
    func refresh(store: PivotStore, events: [CalendarItem], force: Bool = false) async {
        guard !PreviewMode.enabled, store.data.settings.healthEnabled == true, !store.locked, !store.isRestoring, !isRefreshing else { return }
        if !force, let lastRefresh, Date().timeIntervalSince(lastRefresh) < 300 { return }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let from = PivotDate.calendar.date(byAdding: .day, value: -7, to: PivotDate.calendar.startOfDay(for: Date()))!
            let predicate = HKQuery.predicateForSamples(withStart: from.addingTimeInterval(-86400), end: Date(), options: [])
            if let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
                sleepSamples = try await samples(type: type, predicate: predicate).compactMap { $0 as? HKCategorySample }
            }
            let values = try await samples(type: HKObjectType.workoutType(), predicate: predicate).compactMap { $0 as? HKWorkout }
            var summaries: [HealthWorkoutSummary] = []
            for value in values {
                let bpm = try? await averageHeartRate(value)
                let elevation = (value.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity)?.doubleValue(for: .meter())
                summaries.append(.init(id: value.uuid.uuidString, start: value.startDate, end: value.endDate, type: Self.kind(value),
                                       durationSeconds: Int(value.duration.rounded()), distanceKM: value.totalDistance?.doubleValue(for: .meterUnit(with: .kilo)),
                                       activeCalories: value.totalEnergyBurned?.doubleValue(for: .kilocalorie()), averageBPM: bpm, elevationM: elevation))
            }
            workouts = summaries.sorted { $0.start > $1.start }
            // Apply only unique matches. Unrelated walking remains visible as general activity.
            let planned = Planner.plannedEvents(events, data: store.data)
            let matches = summaries.map { ($0, HealthImport.candidates($0, events: planned)) }.filter { $0.1.count == 1 }
            var next = store.data
            var modified = false
            for (workout, candidates) in matches {
                guard let event = candidates.first, matches.filter({ $0.1.first?.id == event.id }).count == 1,
                      (CardioKind.suggested(event.title) == nil || WorkoutContext.significantCardio(workout, settings: next.settings)),
                      workout.durationSeconds >= event.durationMinutes * 30,
                      next.records[event.id]?.health?.id != workout.id,
                      (next.records[event.id]?.status ?? .pending) == .pending else { continue }
                HealthImport.apply(workout, to: event, data: &next); modified = true
            }
            let reviews = WorkoutContext.refreshed(summaries, events: events, data: next, now: Date())
            if reviews != next.workoutReviews { next.workoutReviews = reviews; modified = true }
            for review in reviews where !review.resolved && !review.dismissed {
                var coach = next.coachState
                let marker = "[Salute \(review.id)]"
                guard !coach.messages.contains(where: { $0.text.contains(marker) }) else { continue }
                coach.messages.append(.init(dayKey: PivotDate.key(review.workout.start), role: .coach,
                    text: "Ho trovato \(WorkoutContext.strength(review.workout) ? "un allenamento di forza" : "un’attività cardio significativa") alle \(PivotDate.time(review.workout.start)), da collegare al programma. È l’allenamento del giorno che hai anticipato o spostato? Confermalo qui sotto: sonno e colazione restano da verificare. \(marker)", healthDerived: true))
                next.coachState = coach; modified = true
            }
            for offset in -7...0 {
                guard let date = PivotDate.calendar.date(byAdding: .day, value: offset, to: Date()), let summary = sleep(on: date) else { continue }
                let key = PivotDate.key(date)
                var check = next.checkIns[key] ?? DayCheckIn(id: key)
                // Preserve manually entered/corrected sleep data.
                guard check.sleep == nil || check.sleep?.importedFromHealth == true else { continue }
                if check.sleep?.durationSeconds != summary.durationSeconds || check.healthWakeTime != summary.end {
                    check.sleep = SleepRecord(bedtime: summary.start, durationSeconds: summary.durationSeconds,
                                          awakenings: summary.awakenings, interruptionSeconds: summary.interruptionSeconds, importedFromHealth: true)
                    if check.wakeTime == nil || check.wakeTime == check.healthWakeTime { check.wakeTime = summary.end }
                    check.healthWakeTime = summary.end; next.checkIns[key] = check; modified = true
                }
                let sleepEvents = planned.filter { $0.kind == .routine && EventCoalescer.normalized($0.title).contains("sonno") && PivotDate.calendar.isDate($0.end, inSameDayAs: date) && $0.start < summary.end && $0.end > summary.start }
                if sleepEvents.count == 1, let event = sleepEvents.first, (next.records[event.id]?.status ?? .pending) == .pending {
                    var record = next.records[event.id] ?? EventRecord(id: event.id, snapshot: event)
                    record.status = .completed; record.actualStart = summary.start; record.actualEnd = summary.end
                    record.activeMinutes = summary.durationSeconds / 60; record.healthSleep = check.sleep
                    next.records[event.id] = record
                    modified = true
                }
            }
            if modified { store.change { data in data.records = next.records; data.checkIns = next.checkIns } }
            lastRefresh = Date()
            status = summaries.isEmpty && sleepSamples.isEmpty ? "Nessun dato leggibile. Potrebbero mancare dati o permessi: controlla Salute → profilo → App → Pivot." : "Aggiornato alle \(PivotDate.time(Date())) · sola lettura"
        } catch { status = "Dati non aggiornati: \(error.localizedDescription)" }
    }
    func sleep(on day: Date) -> HealthSleepSummary? {
        let asleep = sleepSamples.filter { HKCategoryValueSleepAnalysis.allAsleepValues.contains(HKCategoryValueSleepAnalysis(rawValue: $0.value) ?? .inBed) }
            .map { HealthInterval(start: $0.startDate, end: $0.endDate) }
        let awake = sleepSamples.filter { $0.value == HKCategoryValueSleepAnalysis.awake.rawValue }.map { HealthInterval(start: $0.startDate, end: $0.endDate) }
        return HealthImport.sleep(asleep: asleep, awake: awake, endingOn: day)
    }
    private func samples(type: HKSampleType, predicate: NSPredicate) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples ?? []) }
            }
            healthStore.execute(query)
        }
    }
    private func averageHeartRate(_ workout: HKWorkout) async throws -> Int? {
        guard let type = HKObjectType.quantityType(forIdentifier: .heartRate) else { return nil }
        let predicate = HKQuery.predicateForObjects(from: workout)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteAverage) { _, result, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: result?.averageQuantity().map { Int($0.doubleValue(for: HKUnit.count().unitDivided(by: .minute())).rounded()) }) }
            }
            healthStore.execute(query)
        }
    }
    private static func kind(_ workout: HKWorkout) -> String {
        switch workout.workoutActivityType {
        case .walking: return "walk"
        case .hiking: return "hike"
        case .traditionalStrengthTraining: return "strength"
        case .functionalStrengthTraining: return "functional"
        case .highIntensityIntervalTraining: return "hiit"
        case .running: return "run"
        case .cycling: return "cycle"
        case .other: return "other"
        default: return "unsupported"
        }
    }
}

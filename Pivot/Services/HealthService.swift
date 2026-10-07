import Foundation
import HealthKit
import Combine

@MainActor
final class HealthService: ObservableObject {
    static let shared = HealthService()
    @Published private(set) var status = "Salute non collegata"
    @Published private(set) var isRefreshing = false
    @Published private(set) var automaticUpdatesActive = false
    @Published private(set) var workouts: [HealthWorkoutSummary] = []
    @Published private(set) var lastRefresh: Date?
    private let healthStore = HKHealthStore()
    private var sleepByDay: [String: HealthSleepSummary] = [:]
    private var workoutCache: [String: HealthWorkoutSummary] = [:]
    private var observerQueries: [HKObserverQuery] = []
    private var pendingObserverCompletions: [HKObserverQueryCompletionHandler] = []
    private var isHandlingBackgroundUpdate = false
    private var backgroundUpdateHandler: (@MainActor () async -> Void)?
    private var automaticUpdateError: String?
    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        let identifiers: [HKQuantityTypeIdentifier] = [.activeEnergyBurned, .distanceWalkingRunning, .heartRate]
        for identifier in identifiers {
            if let type = HKObjectType.quantityType(forIdentifier: identifier) { types.insert(type) }
        }
        return types
    }
    private var backgroundTypes: [HKSampleType] {
        var types: [HKSampleType] = [HKObjectType.workoutType()]
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.append(sleep) }
        return types
    }
    func configureBackgroundUpdates(_ handler: @escaping @MainActor () async -> Void) {
        backgroundUpdateHandler = handler
    }
    func prepareBackgroundObservers() {
        guard observerQueries.isEmpty, HKHealthStore.isHealthDataAvailable() else { return }
        for type in backgroundTypes {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, error in
                Task { @MainActor in
                    guard let self else { completion(); return }
                    await self.receiveBackgroundUpdate(completion: completion, error: error)
                }
            }
            observerQueries.append(query)
            healthStore.execute(query)
        }
    }
    func setBackgroundDelivery(enabled: Bool) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        if !enabled {
            for type in backgroundTypes { try? await healthStore.disableBackgroundDelivery(for: type) }
            automaticUpdatesActive = false
            automaticUpdateError = nil
            return
        }
        prepareBackgroundObservers()
        do {
            for type in backgroundTypes {
                try await healthStore.enableBackgroundDelivery(for: type, frequency: .immediate)
            }
            automaticUpdatesActive = true
            automaticUpdateError = nil
        } catch {
            automaticUpdatesActive = false
            automaticUpdateError = Self.connectionMessage(for: error)
        }
    }
    func connect(store: PivotStore, events: [CalendarItem]) async {
        guard HKHealthStore.isHealthDataAvailable() else { status = "Salute non disponibile su questo dispositivo"; return }
        do {
            // Read only. No workouts or sleep are ever written back to Apple Health.
            try await healthStore.requestAuthorization(toShare: [], read: readTypes)
            guard store.change({ $0.settings.healthEnabled = true }) else { return }
            prepareBackgroundObservers()
            await setBackgroundDelivery(enabled: true)
            await refresh(store: store, events: events, force: true)
        } catch {
            status = Self.connectionMessage(for: error)
        }
    }
    private static func connectionMessage(for error: Error) -> String {
        let details = error.localizedDescription.lowercased()
        if details.contains("com.apple.developer.healthkit") || details.contains("missing entitlement") {
            return "Questa installazione non può accedere all’app Salute: la firma usata per installare Pivot non include HealthKit. Reinstalla Pivot con un profilo Apple che abiliti Salute."
        }
        return "Non è stato possibile collegare l’app Salute. Controlla in Salute → profilo → App → Pivot e riprova. Dettaglio: \(error.localizedDescription)"
    }
    func refresh(store: PivotStore, events: [CalendarItem], force: Bool = false) async {
        guard !PreviewMode.enabled, store.data.settings.healthEnabled == true, !store.locked, !store.isRestoring, !store.isLoading, !isRefreshing else { return }
        if !force, let lastRefresh, Date().timeIntervalSince(lastRefresh) < 300 { return }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        isRefreshing = true
        let started = ProcessInfo.processInfo.systemUptime
        defer { isRefreshing = false; store.diagnostics.record("Salute", seconds: ProcessInfo.processInfo.systemUptime - started) }
        do {
            let from = PivotDate.calendar.date(byAdding: .day, value: -7, to: PivotDate.calendar.startOfDay(for: Date()))!
            let predicate = HKQuery.predicateForSamples(withStart: from.addingTimeInterval(-86400), end: Date(), options: [])
            var sleepValues: [HKCategorySample] = []
            if let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
                sleepValues = try await samples(type: type, predicate: predicate).compactMap { $0 as? HKCategorySample }
            }
            let samplesForSleep = sleepValues, now = Date()
            sleepByDay = await Task.detached(priority: .utility) {
                let asleep = samplesForSleep.filter { HKCategoryValueSleepAnalysis.allAsleepValues.contains(HKCategoryValueSleepAnalysis(rawValue: $0.value) ?? .inBed) }
                    .map { HealthInterval(start: $0.startDate, end: $0.endDate) }
                let awake = samplesForSleep.filter { $0.value == HKCategoryValueSleepAnalysis.awake.rawValue }.map { HealthInterval(start: $0.startDate, end: $0.endDate) }
                var result: [String: HealthSleepSummary] = [:]
                for offset in -7...0 {
                    guard let day = PivotDate.calendar.date(byAdding: .day, value: offset, to: now),
                          let summary = HealthImport.sleep(asleep: asleep, awake: awake, endingOn: day) else { continue }
                    result[PivotDate.key(day)] = summary
                }
                return result
            }.value
            let values = try await samples(type: HKObjectType.workoutType(), predicate: predicate).compactMap { $0 as? HKWorkout }
            var summaries: [HealthWorkoutSummary] = []
            for value in values {
                if let cached = workoutCache[value.uuid.uuidString], cached.start == value.startDate, cached.end == value.endDate,
                   cached.durationSeconds == Int(value.duration.rounded()) {
                    summaries.append(cached); continue
                }
                let bpm = try? await averageHeartRate(value)
                let elevation = (value.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity)?.doubleValue(for: .meter())
                summaries.append(.init(id: value.uuid.uuidString, start: value.startDate, end: value.endDate, type: Self.kind(value),
                                       durationSeconds: Int(value.duration.rounded()), distanceKM: value.totalDistance?.doubleValue(for: .meterUnit(with: .kilo)),
                                       activeCalories: value.totalEnergyBurned?.doubleValue(for: .kilocalorie()), averageBPM: bpm, elevationM: elevation))
            }
            workouts = summaries.sorted { $0.start > $1.start }
            workoutCache = Dictionary(summaries.map { ($0.id, $0) }, uniquingKeysWith: { _, newer in newer })
            // Rebase if the user edited a record while reconciliation was running.
            let readWorkouts = summaries, readSleeps = sleepByDay
            var applied = false
            for _ in 0..<3 {
                let snapshot = store.data, version = snapshot.updatedAt, mergeTime = Date()
                let result = await Task.detached(priority: .utility) {
                    HealthReconciliation.merge(workouts: readWorkouts, sleeps: readSleeps, events: events, data: snapshot, now: mergeTime)
                }.value
                guard !store.isRestoring, !store.isLoading, !store.locked, store.data.settings.healthEnabled == true else { return }
                guard version == store.data.updatedAt else { continue }
                if let result {
                    store.change { data in
                        data.records = result.records; data.checkIns = result.checkIns
                        data.workoutReviews = result.workoutReviews; data.coach = result.coach
                    }
                }
                applied = true; break
            }
            guard applied else { status = "Aggiornamento rimandato mentre modifichi i dati."; return }
            lastRefresh = Date()
            let base = summaries.isEmpty && sleepValues.isEmpty
                ? "Nessun dato leggibile. Potrebbero mancare dati o permessi: controlla Salute → profilo → App → Pivot."
                : "Aggiornato alle \(PivotDate.time(Date())) · sola lettura"
            if let automaticUpdateError {
                status = "\(base) Sincronizzazione automatica non disponibile: \(automaticUpdateError)"
            } else if automaticUpdatesActive {
                status = "\(base) · automatica"
            } else {
                status = base
            }
        } catch { status = "Dati non aggiornati: \(error.localizedDescription)" }
    }
    func sleep(on day: Date) -> HealthSleepSummary? {
        sleepByDay[PivotDate.key(day)]
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
    private func receiveBackgroundUpdate(completion: @escaping HKObserverQueryCompletionHandler, error: Error?) async {
        if let error {
            automaticUpdateError = error.localizedDescription
            completion()
            return
        }
        pendingObserverCompletions.append(completion)
        guard !isHandlingBackgroundUpdate else { return }
        guard let backgroundUpdateHandler else {
            finishPendingBackgroundUpdates()
            return
        }
        isHandlingBackgroundUpdate = true
        await backgroundUpdateHandler()
        isHandlingBackgroundUpdate = false
        finishPendingBackgroundUpdates()
    }
    private func finishPendingBackgroundUpdates() {
        let completions = pendingObserverCompletions
        pendingObserverCompletions.removeAll()
        completions.forEach { $0() }
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


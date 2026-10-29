import Foundation
import HealthKit
import Combine

@MainActor
final class HealthService: ObservableObject {
    static let shared = HealthService()
    @Published private(set) var status = "Salute non collegata"
    @Published private(set) var isRefreshing = false
    @Published private(set) var automaticUpdatesActive = false
    @Published private(set) var connectionDiagnostic: String?
    @Published private(set) var isConnecting = false
    @Published private(set) var workouts: [HealthWorkoutSummary] = []
    @Published private var refreshState = HealthRefreshState()
    var lastRefresh: Date? { refreshState.lastReport?.readAt }
    var lastReport: HealthRefreshReport? { refreshState.lastReport }
    var lastAttempt: HealthRefreshAttempt? { refreshState.lastAttempt }
    private let healthStore = HKHealthStore()
    private var sleepByDay: [String: HealthSleepSummary] = [:]
    private var workoutCache: [String: HealthWorkoutCacheEntry] = [:]
    private var observerQueries: [HKObserverQuery] = []
    private var pendingObserverCompletions: [HKObserverQueryCompletionHandler] = []
    private var isHandlingBackgroundUpdate = false
    private var backgroundUpdateHandler: (@MainActor () async -> Void)?
    private var automaticUpdateError: String?
    private var authorizationRequestCompleted = false
    #if DEBUG && targetEnvironment(simulator)
    private var healthInteractionFixturePrepared = false
    static var isHealthInteractionFixtureEnabled: Bool {
        let process = ProcessInfo.processInfo
        return process.arguments.contains("--interaction-test")
            && process.arguments.contains("--health-refresh-interaction-test")
            && UUID(uuidString: process.environment["PIVOT_QA_HEALTH_ID"] ?? "") != nil
            && ["failed", "partial"].contains(process.environment["PIVOT_UI_HEALTH_STATUS"] ?? "")
    }
    private var healthInteractionNow: Date {
        let epoch = Double(ProcessInfo.processInfo.environment["PIVOT_UI_HEALTH_NOW"] ?? "") ?? 1_793_275_200
        return Date(timeIntervalSince1970: epoch.isFinite ? epoch : 1_793_275_200)
    }
    func prepareHealthInteractionFixtureIfNeeded() {
        guard Self.isHealthInteractionFixtureEnabled, !healthInteractionFixturePrepared else { return }
        healthInteractionFixturePrepared = true
        let old = healthInteractionNow.addingTimeInterval(-86_400)
        let report = HealthRefreshReport.make(workouts: [], sleeps: [:], before: AppData(), after: AppData(), readAt: old)
        _ = refreshState.begin(at: old)
        _ = refreshState.finish(.succeeded, at: old, report: report)
        status = "Dati sintetici per la verifica dell’interfaccia."
    }
    private func runHealthInteractionRefresh() {
        prepareHealthInteractionFixtureIfNeeded()
        let now = healthInteractionNow
        guard refreshState.begin(at: now) else { return }
        if ProcessInfo.processInfo.environment["PIVOT_UI_HEALTH_STATUS"] == "partial" {
            let report = HealthRefreshReport.make(workouts: [], sleeps: [:], before: AppData(), after: AppData(), readAt: now)
            _ = refreshState.finish(.partial, at: now, stage: .heartRate, cause: .deferredDetails, report: report)
        } else {
            _ = refreshState.finish(.failed, at: now, stage: .workouts, cause: .queryFailed)
        }
        status = lastAttempt?.message ?? ""
    }
    #endif
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
        #if DEBUG && targetEnvironment(simulator)
        if Self.isHealthInteractionFixtureEnabled { return }
        #endif
        guard authorizationRequestCompleted, observerQueries.isEmpty, HKHealthStore.isHealthDataAvailable() else { return }
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
        #if DEBUG && targetEnvironment(simulator)
        if Self.isHealthInteractionFixtureEnabled { return }
        #endif
        guard HKHealthStore.isHealthDataAvailable() else { return }
        if !enabled {
            workoutCache.removeAll()
            for query in observerQueries { healthStore.stop(query) }
            observerQueries.removeAll()
            finishPendingBackgroundUpdates()
            for type in backgroundTypes { try? await healthStore.disableBackgroundDelivery(for: type) }
            automaticUpdatesActive = false
            automaticUpdateError = nil
            return
        }
        // Successful presentation is not proof of read permission. iOS hides
        // that distinction, but errors here must not be reported as read failures.
        guard authorizationRequestCompleted else { return }
        prepareBackgroundObservers()
        do {
            for type in backgroundTypes {
                try await healthStore.enableBackgroundDelivery(for: type, frequency: .immediate)
            }
            automaticUpdatesActive = true
            automaticUpdateError = nil
        } catch {
            automaticUpdatesActive = false
            automaticUpdateError = "Lettura disponibile aprendo Pivot, ma aggiornamenti in background non disponibili. \(error.localizedDescription)"
            recordDiagnostic(error, phase: "Aggiornamenti in background")
        }
    }
    func connect(store: PivotStore, events: [CalendarItem]) async {
        #if DEBUG && targetEnvironment(simulator)
        if Self.isHealthInteractionFixtureEnabled { runHealthInteractionRefresh(); return }
        #endif
        guard !isConnecting, !isRefreshing else { return }
        let attemptStartedAt = Date()
        guard refreshState.begin(at: attemptStartedAt) else { return }
        guard HKHealthStore.isHealthDataAvailable() else {
            status = "Salute non disponibile su questo dispositivo"
            finishAttempt(.failed, stage: .availability, cause: .unavailable)
            return
        }
        isConnecting = true
        connectionDiagnostic = nil
        defer { isConnecting = false }
        do {
            // Read only. No workouts or sleep are ever written back to Apple Health.
            try await healthStore.requestAuthorization(toShare: [], read: readTypes)
            try Task.checkCancellation()
            authorizationRequestCompleted = true
            guard store.change({ $0.settings.healthEnabled = true }) else {
                status = "Il collegamento Salute non è stato salvato in Pivot."
                finishAttempt(.failed, stage: .persistence, cause: .persistenceFailed)
                return
            }
            prepareBackgroundObservers()
            await setBackgroundDelivery(enabled: true)
            await refresh(store: store, events: events, force: true, recheckHeartRate: true,
                          attemptStartedAt: attemptStartedAt)
        } catch is CancellationError {
            finishAttempt(.cancelled)
            status = "Collegamento Salute annullato. I dati precedenti restano disponibili."
        } catch {
            authorizationRequestCompleted = false
            recordDiagnostic(error, phase: "Richiesta dei permessi Salute")
            status = Self.connectionMessage(for: error)
            finishAttempt(.failed, stage: .authorization, cause: .authorizationFailed)
        }
    }
    @discardableResult
    private func finishAttempt(_ outcome: HealthRefreshAttempt.Outcome,
                               stage: HealthRefreshAttempt.Stage? = nil,
                               cause: HealthRefreshAttempt.Cause? = nil,
                               report: HealthRefreshReport? = nil) -> Bool {
        guard let attempt = lastAttempt, attempt.outcome == .inProgress else { return false }
        // A system-clock correction must not leave a finished attempt spinning.
        let finishedAt = max(Date(), max(attempt.startedAt, report?.readAt ?? attempt.startedAt))
        return refreshState.finish(outcome, at: finishedAt, stage: stage, cause: cause, report: report)
    }
    private static func connectionMessage(for error: Error) -> String {
        let details = error.localizedDescription.lowercased()
        // HealthKit has no public missing-entitlement error-code case. Do not
        // classify all authorization errors as signing failures: preserve the
        // original domain/code in diagnostics and use an explicit error detail.
        if details.contains("missing entitlement")
            || (details.contains("missing") && details.contains("com.apple.developer.healthkit")) {
            return "iOS ha bloccato l’accesso a Salute: nella firma di questa installazione manca un’autorizzazione HealthKit. Non è un permesso che puoi attivare in Salute. Aggiungere la sorgente o aggiornare soltanto Pivot non basta: va verificato il profilo creato dal programma di installazione. Apri i dettagli qui sotto per identificare l’errore."
        }
        return "Non è stato possibile collegare l’app Salute. Controlla in Salute → profilo → App → Pivot e riprova. Dettaglio: \(error.localizedDescription)"
    }
    private func recordDiagnostic(_ error: Error, phase: String) {
        let error = error as NSError
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        connectionDiagnostic = "Pivot \(version) (\(build))\n\(phase)\n\(error.domain) · codice \(error.code)\n\(error.localizedDescription)"
    }
    func resumeBackgroundUpdates() async {
        #if DEBUG && targetEnvironment(simulator)
        if Self.isHealthInteractionFixtureEnabled { prepareHealthInteractionFixtureIfNeeded(); return }
        #endif
        // Re-establish authorization before installing observers on a later launch.
        // Previously authorized types don't prompt again; never prompt on launch
        // if the user has not explicitly enabled the Health integration.
        guard HKHealthStore.isHealthDataAvailable(), !isConnecting, !isRefreshing else { return }
        let attemptStartedAt = Date()
        isConnecting = true
        defer { isConnecting = false }
        do {
            try await healthStore.requestAuthorization(toShare: [], read: readTypes)
            try Task.checkCancellation()
            authorizationRequestCompleted = true
            await setBackgroundDelivery(enabled: true)
        } catch is CancellationError {
            if refreshState.begin(at: attemptStartedAt) { finishAttempt(.cancelled) }
            status = "Ripristino del collegamento Salute annullato."
        } catch {
            authorizationRequestCompleted = false
            recordDiagnostic(error, phase: "Ripristino del collegamento Salute")
            status = Self.connectionMessage(for: error)
            _ = refreshState.begin(at: attemptStartedAt)
            finishAttempt(.failed, stage: .authorization, cause: .authorizationFailed)
        }
    }
    func refresh(store: PivotStore, events: [CalendarItem], force: Bool = false, recheckHeartRate: Bool = false,
                 attemptStartedAt: Date? = nil) async {
        #if DEBUG && targetEnvironment(simulator)
        if Self.isHealthInteractionFixtureEnabled {
            prepareHealthInteractionFixtureIfNeeded()
            if force { runHealthInteractionRefresh() }
            return
        }
        #endif
        // Do not start an observer read while the explicit connection is waiting
        // for authorization; both paths share one visible attempt at a time.
        guard !isConnecting || attemptStartedAt != nil else { return }
        guard !PreviewMode.enabled, store.data.settings.healthEnabled == true, !store.locked,
              !store.isRestoring, !store.isLoading, !isRefreshing else {
            if attemptStartedAt != nil { finishAttempt(.deferred, stage: .reconciliation, cause: .changed) }
            return
        }
        if !force, let lastRefresh, Date().timeIntervalSince(lastRefresh) < 300 { return }
        if attemptStartedAt == nil, !refreshState.begin(at: Date()) { return }
        guard HKHealthStore.isHealthDataAvailable() else {
            status = "Salute non disponibile su questo dispositivo"
            finishAttempt(.failed, stage: .availability, cause: .unavailable)
            return
        }
        isRefreshing = true
        let started = ProcessInfo.processInfo.systemUptime
        defer { isRefreshing = false; store.diagnostics.record("Salute", seconds: ProcessInfo.processInfo.systemUptime - started) }
        var readingStage: HealthRefreshAttempt.Stage = .sleep
        do {
            try Task.checkCancellation()
            let from = PivotDate.calendar.date(byAdding: .day, value: -7, to: PivotDate.calendar.startOfDay(for: Date()))!
            let predicate = HKQuery.predicateForSamples(withStart: from.addingTimeInterval(-86400), end: Date(), options: [])
            var sleepValues: [HKCategorySample] = []
            if let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
                sleepValues = try await samples(type: type, predicate: predicate).compactMap { $0 as? HKCategorySample }
            }
            let samplesForSleep = sleepValues, now = Date()
            let readSleepByDay = await Task.detached(priority: .utility) {
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
            try Task.checkCancellation()
            readingStage = .workouts
            let values = try await samples(type: HKObjectType.workoutType(), predicate: predicate).compactMap { $0 as? HKWorkout }
            var summaries: [HealthWorkoutSummary] = []
            var nextCache: [String: HealthWorkoutCacheEntry] = [:]
            var heartRateQueries = 0, deferredHeartRates = false
            // A bounded extra-query budget, oldest checks first, avoids both
            // unbounded background work and starvation when many workouts sync.
            let ordered = values.sorted {
                let lhs = workoutCache[$0.uuid.uuidString]?.heartRateAttemptedAt ?? .distantPast
                let rhs = workoutCache[$1.uuid.uuidString]?.heartRateAttemptedAt ?? .distantPast
                return lhs == rhs ? $0.uuid.uuidString < $1.uuid.uuidString : lhs < rhs
            }
            for value in ordered {
                try Task.checkCancellation()
                guard !store.isRestoring, !store.isLoading, !store.locked, store.data.settings.healthEnabled == true else {
                    workoutCache.removeAll()
                    finishAttempt(.cancelled)
                    status = "Aggiornamento Salute annullato. I dati precedenti restano disponibili."
                    return
                }
                let elevation = (value.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity)?.doubleValue(for: .meter())
                var summary = HealthWorkoutSummary(id: value.uuid.uuidString, start: value.startDate, end: value.endDate, type: Self.kind(value),
                    durationSeconds: Int(value.duration.rounded()), distanceKM: value.totalDistance?.doubleValue(for: .meterUnit(with: .kilo)),
                    activeCalories: value.totalEnergyBurned?.doubleValue(for: .kilocalorie()), elevationM: elevation)
                guard summary.isValid else { continue }
                let cached = workoutCache[summary.id]
                summary.averageBPM = cached?.compatibleHeartRate(for: summary)
                var checkedAt = cached?.heartRateReadAt
                var attemptedAt = cached?.heartRateAttemptedAt
                if cached?.needsHeartRate(for: summary, now: now, force: recheckHeartRate) ?? true {
                    checkedAt = nil
                    if heartRateQueries < 12 {
                        heartRateQueries += 1
                        attemptedAt = Date()
                        do {
                            summary.averageBPM = try await averageHeartRate(value)
                            checkedAt = Date()
                        } catch is CancellationError { throw CancellationError() }
                        catch {
                            // Retain the last observation on a transient query
                            // failure, but do not mark it freshly checked.
                            deferredHeartRates = true
                        }
                    } else { deferredHeartRates = true }
                }
                summaries.append(summary)
                nextCache[summary.id] = .init(summary: summary, heartRateReadAt: checkedAt, heartRateAttemptedAt: attemptedAt)
            }
            try Task.checkCancellation()
            guard !store.isRestoring, !store.isLoading, !store.locked, store.data.settings.healthEnabled == true else {
                workoutCache.removeAll()
                finishAttempt(.cancelled)
                status = "Aggiornamento Salute annullato. I dati precedenti restano disponibili."
                return
            }
            // Rebase if the user edited a record while reconciliation was running.
            let readWorkouts = summaries, readSleeps = readSleepByDay
            var completedReport: HealthRefreshReport?
            for _ in 0..<3 {
                let snapshot = store.data, version = snapshot.updatedAt, mergeTime = Date()
                let result = await Task.detached(priority: .utility) {
                    HealthReconciliation.merge(workouts: readWorkouts, sleeps: readSleeps, events: events, data: snapshot, now: mergeTime)
                }.value
                try Task.checkCancellation()
                guard !store.isRestoring, !store.isLoading, !store.locked, store.data.settings.healthEnabled == true else {
                    finishAttempt(.cancelled)
                    status = "Aggiornamento Salute annullato. I dati precedenti restano disponibili."
                    return
                }
                guard version == store.data.updatedAt else { continue }
                if let result {
                    guard store.change({ data in
                        data.records = result.records; data.checkIns = result.checkIns
                        data.workoutReviews = result.workoutReviews; data.coach = result.coach
                    }) else {
                        status = "I dati sono stati letti, ma il riepilogo locale non è stato salvato."
                        finishAttempt(.failed, stage: .persistence, cause: .persistenceFailed)
                        return
                    }
                }
                let reconciledRevision = store.data.updatedAt
                // change() queues a write; only flush confirms persistence. This
                // also retries a previous failed write when merge now returns nil.
                guard await store.flushPendingWrites() else {
                    status = "I dati sono stati letti, ma il riepilogo locale non è stato salvato."
                    finishAttempt(.failed, stage: .persistence, cause: .persistenceFailed)
                    return
                }
                try Task.checkCancellation()
                guard !store.isRestoring, !store.isLoading, !store.locked, store.data.settings.healthEnabled == true else {
                    finishAttempt(.cancelled)
                    status = "Aggiornamento Salute annullato. I dati precedenti restano disponibili."
                    return
                }
                guard reconciledRevision == store.data.updatedAt else {
                    // Health changes may already be durable. Do not merge from
                    // that mutated snapshot and falsely report zero changes.
                    status = "Dati salvati, ma il riepilogo va ricalcolato dopo le modifiche in corso."
                    finishAttempt(.deferred, stage: .reconciliation, cause: .changed)
                    return
                }
                let readAt = max(Date(), lastAttempt?.startedAt ?? now)
                completedReport = HealthRefreshReport.make(workouts: readWorkouts, sleeps: readSleeps,
                                                           before: snapshot, after: result ?? snapshot, readAt: readAt)
                break
            }
            guard let completedReport else {
                status = "Aggiornamento rimandato mentre modifichi i dati."
                finishAttempt(.deferred, stage: .reconciliation, cause: .changed)
                return
            }
            // Publish only the snapshot whose local reconciliation was saved.
            // A query, cancellation or persistence error leaves the previous
            // report and its source observations at their original date.
            guard finishAttempt(deferredHeartRates ? .partial : .succeeded,
                          stage: deferredHeartRates ? .heartRate : nil,
                          cause: deferredHeartRates ? .deferredDetails : nil,
                          report: completedReport) else { return }
            sleepByDay = readSleepByDay
            workouts = summaries.sorted { $0.start > $1.start }
            workoutCache = nextCache
            if automaticUpdateError == nil { connectionDiagnostic = nil }
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
            if deferredHeartRates { status += " Alcuni battiti saranno verificati al prossimo aggiornamento." }
        } catch is CancellationError {
            // Cancellation isn't a failed Health authorization and must not
            // replace the last successful synchronization report.
            finishAttempt(.cancelled)
            status = "Aggiornamento Salute annullato. I dati precedenti restano disponibili."
            return
        } catch {
            recordDiagnostic(error, phase: "Lettura sonno e allenamenti")
            status = Self.connectionMessage(for: error)
            finishAttempt(.failed, stage: readingStage, cause: .queryFailed)
        }
    }
    func sleep(on day: Date) -> HealthSleepSummary? {
        sleepByDay[PivotDate.key(day)]
    }

    /// Separate opt-in: do not add profile types to launch/background requests.
    /// A successful request does not establish read access; missing fields stay nil.
    func readStrengthProfile() async throws -> StrengthProfile {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw NSError(domain: "PivotHealth", code: 1, userInfo: [NSLocalizedDescriptionKey: "Salute non disponibile. Puoi compilare il profilo manualmente."])
        }
        var types = Set<HKObjectType>()
        if let date = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) { types.insert(date) }
        let identifiers: [HKQuantityTypeIdentifier] = [.bodyMass, .height]
        for identifier in identifiers {
            if let type = HKObjectType.quantityType(forIdentifier: identifier) { types.insert(type) }
        }
        try await healthStore.requestAuthorization(toShare: [], read: types)
        var profile = StrengthProfile()
        if let components = try? healthStore.dateOfBirthComponents() {
            var gregorian = Calendar(identifier: .gregorian); gregorian.timeZone = PivotDate.calendar.timeZone
            profile.birthDate = gregorian.date(from: components)
        }
        if let mass = try await latestQuantity(.bodyMass) {
            profile.bodyMassKG = mass.quantity.doubleValue(for: .gramUnit(with: .kilo))
            profile.measuredAt = mass.endDate
        }
        if let height = try await latestQuantity(.height) {
            profile.heightCM = height.quantity.doubleValue(for: .meter()) * 100
        }
        try profile.validate()
        return profile
    }
    private func latestQuantity(_ identifier: HKQuantityTypeIdentifier) async throws -> HKQuantitySample? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: HKQuery.predicateForSamples(withStart: nil, end: Date()), limit: 1,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples?.first as? HKQuantitySample) }
            }
            healthStore.execute(query)
        }
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
            automaticUpdatesActive = false
            recordDiagnostic(error, phase: "Osservazione degli aggiornamenti Salute")
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

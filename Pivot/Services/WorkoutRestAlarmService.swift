import AlarmKit
import Combine
import SwiftUI
import UIKit
import UserNotifications

/// A single system alarm, not an AVAudioSession player plus a separate ducking
/// timer. Routing and the external player's interruption remain owned by iOS.
@MainActor
final class WorkoutRestAlarmService: ObservableObject {
    static let shared = WorkoutRestAlarmService()
    @Published private(set) var message = "Attiva l’allarme recupero per usarlo negli allenamenti."
    @Published private(set) var busy = false
    @Published private(set) var authorized = false
    @Published private(set) var alerting: Set<UUID> = []
    @Published private(set) var syntheticAlarmCount = 0
    private var generations: [UUID: Int] = [:]
    private var jobs: [UUID: Task<Void, Never>] = [:]
    private var observer: Task<Void, Never>?
    private let ledger = WorkoutRestAlarmLedger()
    private var suspended = false
    private var fixturePlans: [UUID: Date] = [:]
    private var fixtureReceipts: [UUID: WorkoutRestAlarmReceipt] = [:]
    @available(iOS 26.0, *) private struct Metadata: AlarmMetadata {}

    private var isInteractionTest: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return ProcessInfo.processInfo.arguments.contains("--interaction-test")
        #else
        return false
        #endif
    }
    private var isFixture: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return isInteractionTest && ProcessInfo.processInfo.arguments.contains("--rest-alarm-test")
            && UUID(uuidString: ProcessInfo.processInfo.environment["PIVOT_QA_REST_ID"] ?? "") != nil
        #else
        return false
        #endif
    }

    func enable(store: PivotStore) async {
        guard !busy, !store.locked, !store.isRestoring else { return }
        busy = true; defer { busy = false }
        do {
            if isInteractionTest {
                guard isFixture else { message = "Gli allarmi reali non vengono attivati nel collaudo."; return }
            } else {
                guard #available(iOS 26.0, *) else { message = "Questa modalità richiede iOS 26 o successivo."; return }
                guard UIApplication.shared.applicationState == .active else { return }
                let manager = AlarmManager.shared
                let state = manager.authorizationState == .notDetermined ? try await manager.requestAuthorization() : manager.authorizationState
                guard state == .authorized else { message = "Allarmi non autorizzati. Nessun bip alternativo verrà inviato alle cuffie."; return }
            }
            var settings = store.data.settings.workoutRestAudio ?? .init(); settings.enabled = true
            authorized = true
            guard settings.isValid, store.change({ $0.settings.workoutRestAudio = settings }), await store.flushPendingWrites() else { return }
            message = "Allarme attivo · premi Ferma per interromperlo."
            observeIfAuthorized()
            for session in store.data.training?.sessions ?? [] where session.end == nil {
                await synchronize(session: session, settings: settings, force: true)
            }
        } catch { message = "Non riesco ad attivare l’allarme. Nessun avviso sonoro alternativo è stato aggiunto." }
    }

    func disable(store: PivotStore) async {
        guard !busy, !store.locked, !store.isRestoring else { return }
        busy = true; defer { busy = false }
        do {
            try await cancelAll()
            var settings = store.data.settings.workoutRestAudio ?? .init(); settings.enabled = false
            guard store.change({ $0.settings.workoutRestAudio = settings }), await store.flushPendingWrites() else {
                message = "Allarmi fermati, ma il salvataggio della preferenza non è confermato. Riprova prima di chiudere Pivot."
                return
            }
            message = "Allarme recupero disattivato. Il timer resta disponibile."
        } catch { message = "Non riesco a fermare un allarme. Usa Ferma nell’allarme di iOS e riprova." }
    }

    func synchronize(session: TrainingSession, settings: WorkoutRestAudioSettings, force: Bool = false) async {
        guard !suspended else { return }
        let live = (WorkoutRuntime.store.data.training?.sessions ?? []).filter { $0.end == nil }
        guard WorkoutRestAlarm.uniqueIDs(live), !WorkoutRestAlarm.hasOtherOwner(sessionID: session.id, activeSessions: live) else {
            message = "Identità degli allenamenti ambigue: nessun allarme è stato modificato."
            return
        }
        let id = session.id, token = (generations[session.id] ?? 0) + 1
        generations[id] = token
        let previous = jobs[id]
        let job = Task { [weak self] in
            _ = await previous?.value
            guard let self, self.generations[id] == token, !self.suspended else { return }
            await self.perform(session: session, settings: settings, token: token, force: force)
        }
        jobs[id] = job; await job.value
        if generations[id] == token { jobs[id] = nil }
    }

    func stop(sessionID: UUID) async {
        let live = (WorkoutRuntime.store.data.training?.sessions ?? []).filter { $0.end == nil }
        guard !WorkoutRestAlarm.hasOtherOwner(sessionID: sessionID, activeSessions: live) else {
            message = "Identità degli allenamenti ambigue: non fermo l’allarme di un’altra sessione."
            return
        }
        // Keep the receipt: editing a load cannot rearm a manually dismissed
        // alarm with this same deadline. A reset/new rest has a new deadline.
        generations[sessionID, default: 0] += 1
        _ = await jobs[sessionID]?.value
        do {
            if isFixture { fixturePlans[sessionID] = nil; syntheticAlarmCount = fixturePlans.count }
            else if !isInteractionTest, #available(iOS 26.0, *), AlarmManager.shared.authorizationState == .authorized {
                let id = WorkoutRestAlarm.id(sessionID: sessionID)
                if try AlarmManager.shared.alarms.contains(where: { $0.id == id }) { try AlarmManager.shared.cancel(id: id) }
            }
            alerting.remove(WorkoutRestAlarm.id(sessionID: sessionID)); message = "Allarme fermato."
        } catch { message = "Usa Ferma nell’allarme di iOS: non riesco a confermare lo stop dall’app." }
    }

    /// Called before a backup replaces device data. Never touches the probe or
    /// another alarm feature, and never rearms imported timers automatically.
    func cancelAll() async throws {
        suspended = true; defer { suspended = false }
        for id in Array(generations.keys) { generations[id, default: 0] += 1 }
        for job in Array(jobs.values) { await job.value }
        if isFixture { fixturePlans = [:]; syntheticAlarmCount = 0 }
        else if !isInteractionTest, #available(iOS 26.0, *), AlarmManager.shared.authorizationState == .authorized {
            for alarm in try AlarmManager.shared.alarms where WorkoutRestAlarm.owns(alarm.id) {
                try AlarmManager.shared.cancel(id: alarm.id)
            }
        }
        alerting = []; observer?.cancel(); observer = nil
    }

    func reconcile(store: PivotStore) async {
        guard !store.isLoading, !store.isRestoring, !store.locked, !suspended else { return }
        // Migrate already scheduled notifications from an older app version:
        // none may keep a default sound that could also play in headphones.
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        guard !store.isRestoring else { return }
        let liveRestIDs = Set((store.data.training?.sessions ?? []).filter {
            $0.end == nil && ($0.rest?.deadline.map { $0 > Date() } ?? false)
        }.map { "workout-rest-" + $0.id.uuidString })
        for request in pending where request.identifier.hasPrefix("workout-rest-") {
            if !liveRestIDs.contains(request.identifier) {
                center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
            } else if request.content.sound != nil,
                      let content = request.content.mutableCopy() as? UNMutableNotificationContent {
                content.sound = nil
                do { try await center.add(.init(identifier: request.identifier, content: content, trigger: request.trigger)) }
                catch { center.removePendingNotificationRequests(withIdentifiers: [request.identifier]) }
            }
        }
        if isInteractionTest { authorized = isFixture; return }
        guard #available(iOS 26.0, *) else { authorized = false; return }
        authorized = AlarmManager.shared.authorizationState == .authorized
        guard authorized else {
            observer?.cancel(); observer = nil; alerting = []
            if store.data.settings.workoutRestAudio?.enabled == true {
                message = "Allarmi non autorizzati in iOS. Il timer resta disponibile senza bip nelle cuffie."
            }
            return
        }
        observeIfAuthorized()
        // Wait for in-flight scheduling before deciding whether an alarm is an
        // orphan. The latest store, not a pre-await snapshot, owns the decision.
        for job in Array(jobs.values) { await job.value }
        guard !store.isRestoring else { return }
        let enabled = store.data.settings.workoutRestAudio?.enabled == true
        let sessions = (store.data.training?.sessions ?? []).filter { $0.end == nil && $0.rest?.deadline != nil }
        let wanted = enabled ? Set(sessions.map { WorkoutRestAlarm.id(sessionID: $0.id) }) : []
        do {
            for alarm in try AlarmManager.shared.alarms where WorkoutRestAlarm.owns(alarm.id) && !wanted.contains(alarm.id) {
                try AlarmManager.shared.cancel(id: alarm.id)
            }
        } catch { message = "Non riesco a verificare gli allarmi precedenti. Controlla gli allarmi di Pivot in iOS." }
    }

    private func perform(session: TrainingSession, settings: WorkoutRestAudioSettings, token: Int, force: Bool) async {
        let decision = WorkoutRestAlarm.decision(session: session, settings: settings, now: Date())
        if isInteractionTest {
            guard isFixture else { return }
            switch decision {
            case .cancel: fixturePlans[session.id] = nil; fixtureReceipts[session.id] = nil
            case .keepExisting: break
            case .schedule(let deadline):
                guard WorkoutRestAlarm.scheduling(sessionID: session.id, deadline: deadline, volumeStep: settings.volumeStep,
                    receipt: fixtureReceipts[session.id], exists: fixturePlans[session.id] != nil, force: force) == .replace else { break }
                fixturePlans[session.id] = deadline
                fixtureReceipts[session.id] = .init(sessionID: session.id, deadline: deadline, volumeStep: settings.volumeStep)
            }
            syntheticAlarmCount = fixturePlans.count
            message = "Collaudo sintetico · nessun allarme reale"
            return
        }
        guard #available(iOS 26.0, *) else { if settings.enabled { message = "Allarme non disponibile su questa versione di iOS." }; return }
        let manager = AlarmManager.shared
        guard manager.authorizationState == .authorized else {
            if settings.enabled { message = "Autorizza gli allarmi in Avviso recupero. Il timer resta attivo senza bip nelle cuffie." }
            return
        }
        let id = WorkoutRestAlarm.id(sessionID: session.id)
        do {
            let alarms = try manager.alarms
            let existing = alarms.first { $0.id == id }
            switch decision {
            case .keepExisting: return
            case .cancel:
                if existing != nil { try manager.cancel(id: id) }
                try await ledger.remove(sessionID: session.id)
            case .schedule(let deadline):
                let receipt = try await ledger.receipt(sessionID: session.id)
                guard generations[session.id] == token, !suspended else { return }
                switch WorkoutRestAlarm.scheduling(sessionID: session.id, deadline: deadline, volumeStep: settings.volumeStep,
                    receipt: receipt, exists: existing != nil, force: force) {
                case .keep: return
                case .dismissedOrUncertain:
                    message = "Allarme non presente: usa Riattiva per questo recupero, se lo desideri."; return
                case .replace: break
                }
                if existing != nil { try manager.cancel(id: id) }
                let sound = try await ledger.prepareSound(settings)
                guard generations[session.id] == token, !suspended, deadline > Date() else { return }
                try await ledger.remember(.init(sessionID: session.id, deadline: deadline, volumeStep: settings.volumeStep))
                guard generations[session.id] == token, !suspended else { return }
                let alert = AlarmPresentation.Alert(title: "Recupero terminato", stopButton: AlarmButton(text: "Ferma", textColor: .white, systemImageName: "stop.fill"))
                let attributes = AlarmAttributes(presentation: AlarmPresentation(alert: alert), metadata: Metadata(), tintColor: Color.mint)
                let configuration = AlarmManager.AlarmConfiguration<Metadata>.alarm(schedule: .fixed(deadline), attributes: attributes, sound: .named(sound))
                _ = try await manager.schedule(id: id, configuration: configuration)
                message = "Allarme recupero programmato · Ferma dall’iPhone."
            }
        } catch { message = "Allarme non confermato. Controlla iOS o usa Riattiva: non aggiungo bip alternativi alle cuffie." }
    }

    private func observeIfAuthorized() {
        guard observer == nil, !isInteractionTest else { return }
        guard #available(iOS 26.0, *), AlarmManager.shared.authorizationState == .authorized else { return }
        if let alarms = try? AlarmManager.shared.alarms {
            alerting = Set(alarms.filter { WorkoutRestAlarm.owns($0.id) && $0.state == .alerting }.map(\.id))
        }
        observer = Task { [weak self] in
            for await alarms in AlarmManager.shared.alarmUpdates {
                guard !Task.isCancelled, let self else { return }
                self.alerting = Set(alarms.filter { WorkoutRestAlarm.owns($0.id) && $0.state == .alerting }.map(\.id))
            }
        }
    }
}

private actor WorkoutRestAlarmLedger {
    private func url() throws -> URL {
        let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("PivotRestAudio", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("receipts.json")
    }
    private func load() throws -> [WorkoutRestAlarmReceipt] {
        let path = try url()
        guard FileManager.default.fileExists(atPath: path.path) else { return [] }
        let bytes = try Data(contentsOf: path)
        guard bytes.count <= 262_144 else { throw CocoaError(.fileReadCorruptFile) }
        let receipts = try JSONDecoder().decode([WorkoutRestAlarmReceipt].self, from: bytes)
        guard receipts.count <= 256, receipts.allSatisfy(\.isValid), Set(receipts.map(\.sessionID)).count == receipts.count else { throw CocoaError(.fileReadCorruptFile) }
        return receipts
    }
    private func save(_ receipts: [WorkoutRestAlarmReceipt]) throws {
        try JSONEncoder().encode(receipts).write(to: url(), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func receipt(sessionID: UUID) throws -> WorkoutRestAlarmReceipt? { try load().first { $0.sessionID == sessionID } }
    func remember(_ receipt: WorkoutRestAlarmReceipt) throws {
        guard receipt.isValid else { throw CocoaError(.fileWriteUnknown) }
        var receipts = try load().filter { $0.sessionID != receipt.sessionID }
        // Never evict a future scheduling acknowledgement to make room.
        if receipts.count >= 255 { receipts.removeAll { $0.deadline < Date().addingTimeInterval(-86400) } }
        guard receipts.count < 256 else { throw CocoaError(.fileWriteOutOfSpace) }
        receipts.append(receipt); try save(receipts)
    }
    func remove(sessionID: UUID) throws { try save(load().filter { $0.sessionID != sessionID }) }
    func prepareSound(_ settings: WorkoutRestAudioSettings) throws -> String {
        guard settings.isValid else { throw CocoaError(.fileWriteUnknown) }
        let folder = try FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Sounds", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(settings.soundName)
        if !FileManager.default.fileExists(atPath: file.path) {
            guard let wave = WorkoutRestChime.waveData(volume: settings.gain) else { throw CocoaError(.fileWriteUnknown) }
            try wave.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        return settings.soundName
    }
}

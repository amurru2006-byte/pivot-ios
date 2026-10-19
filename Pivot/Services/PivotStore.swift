import Foundation
import SwiftUI
import PDFKit
import UIKit

@MainActor
final class PivotStore: ObservableObject {
    // Memory-only: a new process/day requires an initial cloud explanation.
    @Published var onlineConversationPermission = CoachConversationPermission()
    @Published private(set) var data = AppData()
    @Published var error: String?
    @Published private(set) var locked = false
    @Published private(set) var isRestoring = false
    // Main-actor interlock: restoring another database must not replace the
    // durable originals while an external Calendar write is awaiting its ack.
    @Published private(set) var calendarMutationInProgress = false
    @Published private(set) var isLoading = !PreviewMode.enabled
    @Published private(set) var isSaving = false
    @Published private(set) var saveStatus = "Dati salvati"
    let diagnostics = PerformanceDiagnostics()
    @Published private(set) var backupStatus = "Backup esterno non configurato"
    @Published private(set) var lastExternalBackup: Date?
    @Published private(set) var backupPasswordConfigured = false
    @Published private(set) var isConfiguringBackupPassword = false
    @Published private(set) var isExportingBackup = false
    private let directory: URL
    private let file: URL
    private let documentsDirectory: URL
    private var deletedTrainingIDs = Set<UUID>()
    #if DEBUG && targetEnvironment(simulator)
    private var reportFailureInjected = false
    #endif
    private let persistence: FilePersistence
    private lazy var writer = CoalescingWriter<AppData>(write: { [persistence, diagnostics] snapshot in
        let started = ProcessInfo.processInfo.systemUptime
        try await persistence.save(snapshot)
        diagnostics.record("Scrittura dati", seconds: ProcessInfo.processInfo.systemUptime - started)
    }, onResult: { [weak self] pending, error in
        guard let self else { return }
        self.isSaving = pending
        if let error {
            self.saveStatus = "Salvataggio da riprovare"
            self.error = "I dati aggiornati sono ancora in memoria: il salvataggio su disco non è riuscito. Tieni Pivot aperto e premi Riprova nelle Impostazioni. Dettaglio: \(error.localizedDescription)"
        } else {
            self.saveStatus = pending ? "Salvataggio in corso…" : "Dati salvati"
            if !pending { self.writeExternal(self.data) }
        }
    })
    private let backupQueue = DispatchQueue(label: "app.pivot.external-backup", qos: .utility)
    private var pendingExternalBackup: AppData?
    private var externalBackupRunning = false
    private let bookmarkKey = "pivot.externalBackupFolder.v1"
    private let lastBackupKey = "pivot.lastExternalBackup.v1"
    private var backgroundSaveID: UIBackgroundTaskIdentifier = .invalid

    init() {
        var storageName = "Pivot"
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--online-coach-action-test") { storageName = "PivotCoachActionTests" }
        if ProcessInfo.processInfo.arguments.contains("--online-coach-action-test"),
           let value = ProcessInfo.processInfo.environment["PIVOT_QA_COACH_ACTION_ID"], let id = UUID(uuidString: value) {
            storageName = "PivotCoachActionQA-" + id.uuidString
        }
        if ProcessInfo.processInfo.arguments.contains("--interaction-test"), ProcessInfo.processInfo.arguments.contains("--history-test"),
           let value = ProcessInfo.processInfo.environment["PIVOT_QA_HISTORY_ID"], let id = UUID(uuidString: value) { storageName = "PivotHistoryQA-" + id.uuidString }
        if ProcessInfo.processInfo.arguments.contains("--interaction-test"), ProcessInfo.processInfo.arguments.contains("--savings-test"),
           let value = ProcessInfo.processInfo.environment["PIVOT_QA_SAVINGS_ID"], let id = UUID(uuidString: value) { storageName = "PivotSavingsQA-" + id.uuidString }
        if ProcessInfo.processInfo.arguments.contains("--interaction-test"), ProcessInfo.processInfo.arguments.contains("--backup-privacy-test"),
           let value = ProcessInfo.processInfo.environment["PIVOT_QA_BACKUP_ID"], let id = UUID(uuidString: value) { storageName = "PivotBackupQA-" + id.uuidString }
        if ProcessInfo.processInfo.arguments.contains("--student-recognition-test") { storageName = "PivotStudentTests" }
        if ProcessInfo.processInfo.arguments.contains("--payment-schedule-test") { storageName = "PivotPaymentTests" }
        if ProcessInfo.processInfo.arguments.contains("--autofill-test") { storageName = "PivotAutofillTests" }
        if ProcessInfo.processInfo.arguments.contains("--training-edit-test") { storageName = "PivotTrainingEditTests" }
        if ProcessInfo.processInfo.arguments.contains("--workout-controls-test") { storageName = "PivotWorkoutControlsTests" }
        if ProcessInfo.processInfo.arguments.contains("--training-history-test") { storageName = "PivotTrainingHistoryTests" }
        if ProcessInfo.processInfo.arguments.contains("--training-concern-test") { storageName = "PivotTrainingConcernTests" }
        if ProcessInfo.processInfo.arguments.contains("--training-phase-test") { storageName = "PivotTrainingPhaseTests" }
        if ProcessInfo.processInfo.arguments.contains("--interaction-test"), ProcessInfo.processInfo.arguments.contains("--recovery-forecast-test"),
           let id = UUID(uuidString: ProcessInfo.processInfo.environment["PIVOT_QA_RECOVERY_ID"] ?? "") { storageName = "PivotRecoveryQA-" + id.uuidString }
        if ProcessInfo.processInfo.arguments.contains("--interaction-test"), ProcessInfo.processInfo.arguments.contains("--training-forecast-test"),
           let id = UUID(uuidString: ProcessInfo.processInfo.environment["PIVOT_QA_FORECAST_ID"] ?? "") { storageName = "PivotForecastQA-" + id.uuidString }
        if ProcessInfo.processInfo.arguments.contains("--training-progression-test") { storageName = "PivotTrainingProgressionTests" }
        if ProcessInfo.processInfo.arguments.contains("--report-test") { storageName = "PivotTrainingReportTests" }
        if ProcessInfo.processInfo.arguments.contains("--interaction-test"), ProcessInfo.processInfo.arguments.contains("--financial-corrections-test"),
           let value = ProcessInfo.processInfo.environment["PIVOT_QA_FINANCE_ID"], let id = UUID(uuidString: value) { storageName = "PivotFinanceQA-" + id.uuidString }
        #endif
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(storageName, isDirectory: true)
        file = directory.appendingPathComponent("pivot-data.json")
        documentsDirectory = directory.appendingPathComponent("StudyPDFs", isDirectory: true)
        persistence = FilePersistence(directory: directory)
        lastExternalBackup = UserDefaults.standard.object(forKey: lastBackupKey) as? Date
        if UserDefaults.standard.data(forKey: bookmarkKey) != nil {
            backupStatus = "Cartella configurata; verifica della copia alla prossima modifica"
        }
        guard !PreviewMode.enabled else { return }
        Task {
            let started = ProcessInfo.processInfo.systemUptime
            do { data = try await persistence.load() }
            catch {
                locked = true
                self.error = "Non riesco a leggere lo storico. Non lo sovrascriverò. Ripristina un backup valido. Dettaglio: \(error.localizedDescription)"
            }
            isLoading = false
            refreshBackupProtection()
            if !locked, var library = data.training, TrainingIsometry.migrate(&library) {
                change { $0.training = library }
            }
            diagnostics.record("Caricamento storico", seconds: ProcessInfo.processInfo.systemUptime - started)
            if !locked { applyInitialSettings() }
            #if DEBUG && targetEnvironment(simulator)
            if !locked, ProcessInfo.processInfo.arguments.contains("--interaction-test"), ProcessInfo.processInfo.arguments.contains("--recovery-forecast-test"),
               UUID(uuidString: ProcessInfo.processInfo.environment["PIVOT_QA_RECOVERY_ID"] ?? "") != nil, data.rules["recovery-qa"] == nil {
                change { $0.rules["recovery-qa"] = .init(flexibility: .movable, minimumMinutes: 60, travelConfirmed: true) }
            }
            if !locked, ProcessInfo.processInfo.arguments.contains("--interaction-test"), ProcessInfo.processInfo.arguments.contains("--history-test"),
               UUID(uuidString: ProcessInfo.processInfo.environment["PIVOT_QA_HISTORY_ID"] ?? "") != nil, data.clients.isEmpty {
                change { data in
                    data.clients = [Client(name: "Contatto A Test", rateCents: 1200), Client(name: "Contatto B Test", rateCents: 1800)]
                    data.ledger = .init(openingCents: [String(PivotDate.calendar.component(.year, from: Date())): 2500])
                }
            }
            if !locked, ProcessInfo.processInfo.arguments.contains("--interaction-test"), ProcessInfo.processInfo.arguments.contains("--calendar-mutations-test"),
               UUID(uuidString: ProcessInfo.processInfo.environment["PIVOT_QA_COACH_ACTION_ID"] ?? "") != nil, data.clients.isEmpty {
                change { data in
                    let client = Client(name: "Contatto mutazioni QA", rateCents: 1000)
                    let income = IncomeEntry(clientID: client.id, clientName: client.name, date: Date(), minutes: 60,
                        amountCents: 1000, paidCents: 500, calendarEventID: "mutation-qa-1")
                    data.clients = [client]; data.income = [income]
                    data.payments = [.init(incomeID: income.id, clientName: client.name, date: Date(), amountCents: 500)]
                    data.ledger = .init(); data.savingsBudget = .init(openingFundsCents: 0)
                }
            }
            if !locked, ProcessInfo.processInfo.arguments.contains("--interaction-test"), ProcessInfo.processInfo.arguments.contains("--savings-test"),
               UUID(uuidString: ProcessInfo.processInfo.environment["PIVOT_QA_SAVINGS_ID"] ?? "") != nil,
               data.savingsBudget == nil, data.clients.isEmpty, data.payments.isEmpty, data.ledger?.openingCents.isEmpty != false {
                change { $0.ledger = .init(openingCents: [String(PivotDate.calendar.component(.year, from: Date())): 35_000]) }
            }
            if !locked, ProcessInfo.processInfo.arguments.contains("--interaction-test"), ProcessInfo.processInfo.arguments.contains("--financial-corrections-test"),
               UUID(uuidString: ProcessInfo.processInfo.environment["PIVOT_QA_FINANCE_ID"] ?? "") != nil, data.clients.isEmpty {
                let client = Client(id: UUID(uuidString: "55555555-5555-4555-8555-555555555551")!, name: "Marta Test", rateCents: 1500)
                let duplicate = Client(id: UUID(uuidString: "55555555-5555-4555-8555-555555555552")!, name: "Marta Test", rateCents: 0)
                let entry = IncomeEntry(id: UUID(uuidString: "55555555-5555-4555-8555-555555555553")!, clientID: duplicate.id, clientName: duplicate.name,
                                        date: Date(), minutes: 60, amountCents: 2000, paidCents: 1500)
                change { data in
                    data.clients = [client, duplicate]; data.income = [entry]
                    data.payments = [Payment(id: UUID(uuidString: "55555555-5555-4555-8555-555555555554")!, incomeID: entry.id, clientName: entry.clientName, date: entry.date, amountCents: 1500)]
                    if ProcessInfo.processInfo.arguments.contains("--receipts-list-test") {
                        for offset in 1...6 {
                            let other = IncomeEntry(clientID: client.id, clientName: client.name, date: Date().addingTimeInterval(Double(-offset * 60)), minutes: 0, amountCents: 100, paidCents: 100)
                            data.income.append(other)
                            data.payments.append(Payment(incomeID: other.id, clientName: client.name, date: other.date, amountCents: 100))
                        }
                    }
                }
            }
            if !locked, ProcessInfo.processInfo.arguments.contains("--student-recognition-test"), data.clients.isEmpty {
                change { $0.clients = [Client(name: "Giulia Rossi", rateCents: 1800)] }
            }
            if !locked, ProcessInfo.processInfo.arguments.contains("--payment-schedule-test"), data.clients.isEmpty {
                let client = Client(id: UUID(uuidString: "44444444-4444-4444-8444-444444444444")!, name: "Giulia Rossi", rateCents: 1800, paymentCadence: .weekly)
                let monday = StudentPayments.week(containing: Date()).start.addingTimeInterval(17 * 3600)
                change { data in
                    data.clients = [client]
                    data.income = [IncomeEntry(clientID: client.id, clientName: client.name, date: monday, minutes: 60, amountCents: 1800, calendarEventID: "payment-test-0")]
                    let event = CalendarItem(id: "payment-test-0", eventIdentifier: "payment-test-0", calendarIdentifier: "interaction", calendarTitle: "Lavoro", title: "Ripetizioni con Giulia Rossi", start: monday.addingTimeInterval(-3600), end: monday, location: "", notes: "", colorHex: "#7EE6CD", isAllDay: false, writable: false, kind: .tutoring)
                    var record = EventRecord(id: event.id, snapshot: event)
                    record.status = .completed; record.tutoringAnswered = true; record.incomeID = data.income[0].id
                    data.records[event.id] = record
                }
            }
            #endif
        }
    }

    private func applyInitialSettings() {
        var next = data
        if !locked {
            if data.settings.notificationPolicyVersion == nil {
                next.settings.notificationPolicyVersion = 1; next.settings.repeatMissedNotifications = false
            }
            let cents = Bundle.main.object(forInfoDictionaryKey: "PivotInitialIncomeCents") as? Int
            let year = Bundle.main.object(forInfoDictionaryKey: "PivotInitialIncomeYear") as? Int
            var ledger = data.ledger ?? AnnualLedger()
            let missingOpening = year.map { ledger.openingCents[String($0)] == nil } ?? false
            if let cents, let year, missingOpening, cents >= 0, (1900...9999).contains(year) {
                ledger.setOpeningTotal(cents, year: year, payments: data.payments)
            }
            if data.ledger == nil || missingOpening { next.ledger = ledger }
            if data.settings.notificationPolicyVersion == nil || data.ledger == nil || missingOpening { change { $0 = next } }
        }
    }

    @discardableResult
    func change(_ edit: (inout AppData) -> Void) -> Bool {
        guard !locked && !isRestoring && !isLoading else { error = "Attendi il caricamento o il ripristino prima di modificare lo storico."; return false }
        var next = data
        edit(&next)
        next.updatedAt = Date()
        data = next
        isSaving = true; saveStatus = "Salvataggio in corso…"
        writer.enqueue(next)
        return true
    }

    @discardableResult func flushPendingWrites() async -> Bool {
        let started = ProcessInfo.processInfo.systemUptime
        let ok = await writer.flush()
        diagnostics.record("Salvataggio", seconds: ProcessInfo.processInfo.systemUptime - started)
        return ok
    }

    func saveBeforeBackground() {
        guard !isLoading, backgroundSaveID == .invalid else { return }
        backgroundSaveID = UIApplication.shared.beginBackgroundTask(withName: "Salva Pivot") { [weak self] in self?.endBackgroundSave() }
        Task {
            _ = await flushPendingWrites()
            endBackgroundSave()
        }
    }
    private func endBackgroundSave() {
        guard backgroundSaveID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundSaveID)
        backgroundSaveID = .invalid
    }

    func refreshBackupProtection() {
        backupPasswordConfigured = !isLoading && BackupPasswordVault.configured(for: data.installationID)
        if !backupPasswordConfigured { backupStatus = "Imposta una password per creare copie esterne cifrate. Le copie precedenti restano intatte." }
    }

    func configureBackupPassword(_ password: String, confirmation: String) async -> Bool {
        guard !locked, !isLoading, !isRestoring, !isConfiguringBackupPassword, !isExportingBackup, !externalBackupRunning else {
            backupStatus = "Attendi il completamento del salvataggio o del ripristino prima di impostare la password."
            return false
        }
        isConfiguringBackupPassword = true
        defer { isConfiguringBackupPassword = false; startNextExternalBackup() }
        let installationID = data.installationID
        do {
            let protection = try await Task.detached(priority: .userInitiated) {
                let key = try EncryptedBackup.prepare(password: password, confirmation: confirmation)
                let probe = Data("Pivot backup verification".utf8)
                guard try EncryptedBackup.open(EncryptedBackup.seal(probe, using: key), using: key) == probe else {
                    throw EncryptedBackupError.unavailable
                }
                return key
            }.value
            try Task.checkCancellation()
            guard !locked, !isRestoring, data.installationID == installationID else { throw EncryptedBackupError.unavailable }
            try BackupPasswordVault.save(protection, for: installationID)
            backupPasswordConfigured = true
            backupStatus = "Protezione configurata. Le nuove copie saranno cifrate; conserva la password per il ripristino."
            writeExternal(data)
            return true
        } catch is CancellationError { return false }
        catch { backupStatus = error.localizedDescription; return false }
    }

    func selectBackupFolder(_ url: URL) {
        guard !isLoading, !isRestoring else { return }
        guard !locked else { error = "Prima ripristina un backup valido. Il file originale è protetto."; return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            try Self.validateExternalFolder(url)
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            writeExternal(data)
        } catch { self.error = "Cartella di backup non configurata: \(error.localizedDescription)" }
    }

    func backupNow() {
        guard !isLoading, !isRestoring else { return }
        guard !locked else { error = "Prima ripristina un backup valido. Il file originale è protetto."; return }
        writeExternal(data)
    }

    private func writeExternal(_ snapshot: AppData) {
        guard UserDefaults.standard.data(forKey: bookmarkKey) != nil else { return }
        guard backupPasswordConfigured else {
            backupStatus = "Copia esterna sospesa: imposta la password del backup. Nessuna copia in chiaro viene creata."
            return
        }
        pendingExternalBackup = snapshot
        backupStatus = "Aggiornamento della copia esterna…"
        startNextExternalBackup()
    }
    private func startNextExternalBackup() {
        guard !externalBackupRunning, !isConfiguringBackupPassword, let snapshot = pendingExternalBackup,
              let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        pendingExternalBackup = nil
        externalBackupRunning = true
        // A slow cloud folder retains at most the in-flight and latest snapshots,
        // not a growing queue of complete historical states/PDF exports.
        let pdfDirectory = documentsDirectory
        backupQueue.async { [weak self] in
            let result = Self.performExternalBackup(snapshot, bookmark: bookmark, documents: pdfDirectory)
            DispatchQueue.main.async {
                guard let self else { return }
                self.externalBackupRunning = false
                if UserDefaults.standard.data(forKey: self.bookmarkKey) == bookmark {
                    if let updatedBookmark = result.bookmark { UserDefaults.standard.set(updatedBookmark, forKey: self.bookmarkKey) }
                    if let date = result.date {
                        self.lastExternalBackup = date
                        UserDefaults.standard.set(date, forKey: self.lastBackupKey)
                    }
                    self.backupStatus = self.pendingExternalBackup == nil ? result.status : "Aggiornamento della copia esterna…"
                }
                self.startNextExternalBackup()
            }
        }
    }
    private struct BackupResult {
        var status: String
        var date: Date? = nil
        var bookmark: Data? = nil
    }
    private nonisolated static func performExternalBackup(_ snapshot: AppData, bookmark: Data, documents: URL) -> BackupResult {
        do {
            let protection = try BackupPasswordVault.load(for: snapshot.installationID)
            let clear = try BackupCodec.encode(StudyFiles.completeBackup(HealthImport.exportData(snapshot, allowHealth: false), directory: documents))
            _ = try BackupCodec.decode(clear)
            let bytes = try EncryptedBackup.seal(clear, using: protection)
            guard try EncryptedBackup.open(bytes, using: protection) == clear else { throw EncryptedBackupError.unavailable }
            var stale = false
            let folder = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
            let access = folder.startAccessingSecurityScopedResource()
            defer { if access { folder.stopAccessingSecurityScopedResource() } }
            try validateExternalFolder(folder)
            let refreshedBookmark = stale ? try folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) : nil
            let stem = "Backup Pivot-" + protection.identifier
            let destination = folder.appendingPathComponent(stem + ".pivotbackup")
            if FileManager.default.fileExists(atPath: destination.path) {
                let previous = try EncryptedBackup.read(destination)
                if let priorClear = try? EncryptedBackup.open(previous, using: protection), (try? BackupCodec.decode(priorClear)) != nil {
                    try previous.write(to: folder.appendingPathComponent(stem + " precedente.pivotbackup"), options: .atomic)
                } else {
                    // Preserve an unreadable existing archive for recovery.
                    // Never overwrite it merely because the new snapshot is valid.
                    throw EncryptedBackupError.authenticationFailed
                }
            }
            try bytes.write(to: destination, options: .atomic)
            _ = try BackupCodec.decode(EncryptedBackup.open(EncryptedBackup.read(destination), using: protection))
            return BackupResult(status: "Copia cifrata scritta e verificata. La sincronizzazione iCloud è gestita da iOS.", date: Date(), bookmark: refreshedBookmark)
        } catch {
            return BackupResult(status: "ATTENZIONE: copia esterna non aggiornata. \(error.localizedDescription)")
        }
    }

    private nonisolated static func validateExternalFolder(_ url: URL) throws {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        let container = URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().standardizedFileURL.path
        guard path != container && !path.hasPrefix(container + "/") else {
            throw NSError(domain: "PivotBackup", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Scegli una cartella in iCloud Drive o esterna a Pivot. La cartella interna sparirebbe cancellando l'app."])
        }
    }

    func exportURL() async throws -> URL {
        guard !isLoading, !isRestoring, !isConfiguringBackupPassword, !isExportingBackup else { throw EncryptedBackupError.unavailable }
        isExportingBackup = true
        defer { isExportingBackup = false }
        guard await flushPendingWrites() else { throw BackupError.invalidData }
        let snapshot = data, pdfDirectory = documentsDirectory, isLocked = locked
        return try await Task.detached(priority: .utility) {
            // A corrupted local file must not bypass the privacy filter. Recovery
            // of that original is a separate explicit operation, never a backup.
            guard !isLocked else { throw BackupError.invalidData }
            let protection = try BackupPasswordVault.load(for: snapshot.installationID)
            let clear = try BackupCodec.encode(StudyFiles.completeBackup(HealthImport.exportData(snapshot, allowHealth: false), directory: pdfDirectory))
            _ = try BackupCodec.decode(clear)
            let bytes = try EncryptedBackup.seal(clear, using: protection)
            guard try EncryptedBackup.open(bytes, using: protection) == clear else { throw EncryptedBackupError.unavailable }
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent("Backup Pivot.pivotbackup")
            try bytes.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return destination
        }.value
    }

    func beginCalendarMutation() -> Bool {
        guard !locked, !isLoading, !isRestoring, !calendarMutationInProgress else { return false }
        calendarMutationInProgress = true
        return true
    }
    func endCalendarMutation() { calendarMutationInProgress = false }

    func restore(_ url: URL, password: String? = nil) async {
        guard !calendarMutationInProgress else {
            error = "Attendi la conclusione della modifica al Calendario prima di ripristinare un backup."
            return
        }
        guard !isRestoring, !isLoading, !isConfiguringBackupPassword, !isExportingBackup else { return }
        isRestoring = true
        defer { isRestoring = false }
        guard await flushPendingWrites() else { return }
        let pdfDirectory = documentsDirectory
        do {
            var restored = try await Task.detached(priority: .utility) {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let decoded = try EncryptedBackup.decoded(EncryptedBackup.read(url), password: password)
                for bytes in (decoded.studyPDFs ?? [:]).values {
                    guard let pdf = PDFDocument(data: bytes), pdf.pageCount > 0, !pdf.isLocked else { throw StudyFileError.invalidBackup }
                }
                return try StudyFiles.installBackup(decoded, directory: pdfDirectory)
            }.value
            if var library = restored.training, TrainingIsometry.migrate(&library) {
                try library.validate(); restored.training = library
            }
            try await persistence.save(restored, restoring: true)
            data = restored
            deletedTrainingIDs.removeAll()
            locked = false
            error = nil
            refreshBackupProtection()
            writeExternal(restored)
        } catch { self.error = "Ripristino non eseguito: \(error.localizedDescription)" }
    }

    func importStudyPDF(_ url: URL) async throws -> StudyDocument {
        guard !locked && !isRestoring else { throw BackupError.invalidData }
        let destinationDirectory = documentsDirectory
        return try await Task.detached(priority: .utility) {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > StudyFiles.maximumBytes { throw StudyFileError.tooLarge }
            let bytes = try Data(contentsOf: url)
            try StudyFiles.validate(bytes)
            guard let pdf = PDFDocument(data: bytes), pdf.pageCount > 0, !pdf.isLocked else { throw StudyFileError.invalidPDF }
            let document = StudyDocument(name: url.lastPathComponent, byteCount: bytes.count)
            try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
            try bytes.write(to: StudyFiles.url(for: document.id, directory: destinationDirectory), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return document
        }.value
    }
    func studyPDFURL(_ document: StudyDocument) throws -> URL {
        let url = StudyFiles.url(for: document.id, directory: documentsDirectory)
        guard FileManager.default.fileExists(atPath: url.path) else { throw StudyFileError.missingFile }
        return url
    }

    func importTrainingPDF(_ url: URL) async throws -> TrainingPlan {
        guard !locked && !isRestoring else { throw BackupError.invalidData }
        let destinationDirectory = documentsDirectory
        return try await Task.detached(priority: .utility) {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > StudyFiles.maximumBytes { throw StudyFileError.tooLarge }
            let bytes = try Data(contentsOf: url)
            try StudyFiles.validate(bytes)
            guard let pdf = PDFDocument(data: bytes), !pdf.isLocked, (1...100).contains(pdf.pageCount) else { throw StudyFileError.invalidPDF }
            let payload = try TrainingPDFFormat.parse(pdf.string ?? "")
            let document = StudyDocument(name: url.lastPathComponent, byteCount: bytes.count)
            try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
            try bytes.write(to: StudyFiles.url(for: document.id, directory: destinationDirectory), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return TrainingPlan(payload: payload, document: document)
        }.value
    }

    func installTrainingPlan(_ plan: TrainingPlan) throws {
        var library = data.training ?? TrainingLibrary()
        guard library.plans.count < 6 else { throw TrainingError.invalidPlan }
        guard StudyFiles.documents(in: data).reduce(0, { $0 + $1.byteCount }) + (plan.document?.byteCount ?? 0) <= StudyFiles.maximumLibraryBytes else { throw StudyFileError.libraryFull }
        library.plans.append(plan); library.activePlanID = plan.id
        try library.validate()
        guard change({ $0.training = library }) else { throw BackupError.invalidData }
    }

    @discardableResult func saveTraining(_ session: TrainingSession, tips: [String: String], event: CalendarItem?, historicalEdit: Bool = false) -> Bool {
        guard !deletedTrainingIDs.contains(session.id) else { error = "Questo allenamento è stato eliminato. Le modifiche non sono state salvate."; return false }
        var library = data.training ?? TrainingLibrary()
        var session = TrainingEdits.preservingCatalogChoices(in: session, library: library)
        for index in session.exercises.indices {
            TrainingSetTemplate.rememberWarmupFractions(in: &session.exercises[index].sets)
        }
        let previous = library.sessions.first { $0.id == session.id }
        let correctingHistory = historicalEdit || previous?.end != nil
        let earned = correctingHistory ? [] : TrainingRecords.newAchievements(session: session, previous: previous, library: library, profile: data.strengthProfile)
        if !earned.isEmpty { library.achievements = TrainingRecords.retainingHistory((library.achievements ?? []) + earned) }
        if let index = library.sessions.firstIndex(where: { $0.id == session.id }) { library.sessions[index] = session }
        else { library.sessions.append(session) }
        if correctingHistory { library.achievements = TrainingRecords.reconciled(library: library, profile: data.strengthProfile) }
        for (key, value) in tips { library.tips[key] = value }
        do { try library.validate() }
        catch { self.error = "Controlla carichi e ripetizioni prima di salvare. I dati precedenti sono conservati."; return false }
        return change { data in
            data.training = library
            // A history opened from another event must never inherit that event.
            if let eventID = session.calendarEventID,
               let event = data.records[eventID]?.snapshot ?? (event?.id == eventID ? event : nil) {
                let existing = data.records[event.id]
                let record = existing ?? EventRecord(id: event.id, snapshot: event)
                data.records[event.id] = TrainingTiming.merging(session, previous: existing == nil ? nil : previous, into: record)
            }
        }
    }

    func flushWorkoutChanges() async -> Bool { await writer.flush() }

    func saveTrainingConcern(_ concern: TrainingConcern, expected: TrainingConcern?) async throws -> (concern: TrainingConcern, persisted: Bool) {
        guard !locked, !isLoading, !isRestoring else { throw TrainingConcerns.ConcernError.unavailable }
        let saved = try TrainingConcerns.saving(concern, expected: expected, in: data.training ?? .init())
        guard change({ $0.training = saved.library }) else { throw TrainingConcerns.ConcernError.unavailable }
        return (saved.concern, await flushWorkoutChanges())
    }

    func deleteTrainingConcern(_ expected: TrainingConcern) async throws -> Bool {
        guard !locked, !isLoading, !isRestoring else { throw TrainingConcerns.ConcernError.unavailable }
        let library = try TrainingConcerns.removing(expected, from: data.training ?? .init())
        guard change({ $0.training = library }) else { throw TrainingConcerns.ConcernError.unavailable }
        return await flushWorkoutChanges()
    }

    func deleteTraining(_ expected: TrainingSession) async throws -> String {
        guard !locked, !isLoading, !isRestoring else { throw TrainingHistory.HistoryError.unavailable }
        let next = try TrainingHistory.removing(expected, from: data)
        guard change({ $0 = next }) else { throw BackupError.invalidData }
        deletedTrainingIDs.insert(expected.id)
        await WorkoutRuntime.stop(sessionID: expected.id)
        guard await flushWorkoutChanges() else {
            return "Allenamento rimosso in memoria, ma il salvataggio su disco va riprovato nelle Impostazioni. Tieni Pivot aperto."
        }
        let report = TrainingReportFiles.url(for: expected.id, directory: directory.appendingPathComponent("TrainingReports", isDirectory: true))
        do {
            if FileManager.default.fileExists(atPath: report.path) { try FileManager.default.removeItem(at: report) }
        } catch {
            return "Allenamento eliminato. Non sono riuscito a rimuovere la vecchia copia PDF interna; le copie già condivise restano comunque fuori da Pivot."
        }
        return "Allenamento eliminato. Progressi e rank aggiornati; evento nel Calendario conservato. Le copie PDF già condivise non vengono cancellate."
    }

    func trainingExportURL(_ session: TrainingSession) async throws -> URL {
        guard !locked, !isRestoring else { throw BackupError.invalidData }
        let library = data.training ?? TrainingLibrary()
        guard let saved = library.sessions.first(where: { $0.id == session.id }), saved.end != nil else { throw TrainingReportPDF.ExportError.unfinished }
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--report-failure-test"), !reportFailureInjected {
            reportFailureInjected = true
            throw CocoaError(.fileWriteOutOfSpace)
        }
        #endif
        // Reports are derived from the saved session, not a stale view copy.
        // They stay on disk across launches and can be regenerated from backup.
        let destination = TrainingReportFiles.url(for: saved.id, directory: directory.appendingPathComponent("TrainingReports", isDirectory: true))
        return try TrainingReportPDF.write(sessions: [saved], library: library, title: "Diario allenamento", destination: destination)
    }
    func trainingWeekExportURL(containing date: Date) async throws -> URL {
        let library = data.training ?? TrainingLibrary()
        let interval = TrainingReports.week(containing: date)
        let sessions = TrainingReports.performed(in: interval, library: library)
        guard !sessions.isEmpty else { throw TrainingReportPDF.ExportError.empty }
        return try TrainingReportPDF.write(sessions: sessions, library: library, title: "Riepilogo settimanale", interval: interval)
    }

    func incomeExcelURL(year: Int) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Registro-Pivot-\(year).xlsx")
        let snapshot = data
        return try await Task.detached(priority: .utility) {
            try LedgerExcel.make(data: snapshot, year: year).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return url
        }.value
    }

    func record(for event: CalendarItem) -> EventRecord {
        data.records[event.id] ?? EventRecord(id: event.id, snapshot: event)
    }
    func rule(for event: CalendarItem) -> EventRule { EventRule.effective(for: event, data: data) }
    func saveRecord(_ record: EventRecord) {
        var updated = record
        updated.updatedAt = Date()
        change { $0.records[updated.id] = updated }
    }
}

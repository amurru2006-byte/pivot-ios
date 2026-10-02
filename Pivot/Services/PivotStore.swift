import Foundation
import SwiftUI

@MainActor
final class PivotStore: ObservableObject {
    @Published private(set) var data = AppData()
    @Published var error: String?
    @Published private(set) var locked = false
    @Published private(set) var backupStatus = "Backup esterno non configurato"
    @Published private(set) var lastExternalBackup: Date?
    private let directory: URL
    private let file: URL
    private let bookmarkKey = "pivot.externalBackupFolder.v1"
    private let lastBackupKey = "pivot.lastExternalBackup.v1"

    init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Pivot", isDirectory: true)
        file = directory.appendingPathComponent("pivot-data.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) {
                data = try BackupCodec.decode(Data(contentsOf: file))
            }
        } catch {
            locked = true
            self.error = "Non riesco a leggere lo storico. Non lo sovrascriverò. Esporta il file dall'app File o ripristina un backup valido. Dettaglio: \(error.localizedDescription)"
        }
        lastExternalBackup = UserDefaults.standard.object(forKey: lastBackupKey) as? Date
        if UserDefaults.standard.data(forKey: bookmarkKey) != nil {
            backupStatus = "Cartella configurata; verifica della copia alla prossima modifica"
        }
    }

    @discardableResult
    func change(_ edit: (inout AppData) -> Void) -> Bool {
        guard !locked else { error = "Salvataggio bloccato per proteggere lo storico originale."; return false }
        var next = data
        edit(&next)
        next.updatedAt = Date()
        do {
            let bytes = try BackupCodec.encode(next)
            if FileManager.default.fileExists(atPath: file.path) {
                let old = try Data(contentsOf: file)
                try old.write(to: directory.appendingPathComponent("previous.json"), options: .atomic)
            }
            try bytes.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            data = next
            writeExternal(bytes)
            return true
        } catch { self.error = "Modifica non salvata: \(error.localizedDescription)"; return false }
    }

    func selectBackupFolder(_ url: URL) {
        guard !locked else { error = "Prima ripristina un backup valido. Il file originale è protetto."; return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            try validateExternalFolder(url)
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            writeExternal(try BackupCodec.encode(data))
        } catch { self.error = "Cartella di backup non configurata: \(error.localizedDescription)" }
    }

    func backupNow() {
        guard !locked else { error = "Prima ripristina un backup valido. Il file originale è protetto."; return }
        do { writeExternal(try BackupCodec.encode(data)) }
        catch { self.error = error.localizedDescription }
    }

    private func writeExternal(_ bytes: Data) {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        do {
            var stale = false
            let folder = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
            let access = folder.startAccessingSecurityScopedResource()
            defer { if access { folder.stopAccessingSecurityScopedResource() } }
            try validateExternalFolder(folder)
            if stale {
                UserDefaults.standard.set(try folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil), forKey: bookmarkKey)
            }
            let destination = folder.appendingPathComponent("Backup Pivot.json")
            // Rotate only a readable, valid copy; never replace the older good backup with corrupt bytes.
            if FileManager.default.fileExists(atPath: destination.path) {
                let previous = try Data(contentsOf: destination)
                if (try? BackupCodec.decode(previous)) != nil {
                    try previous.write(to: folder.appendingPathComponent("Backup Pivot precedente.json"), options: .atomic)
                }
            }
            try bytes.write(to: destination, options: .atomic)
            _ = try BackupCodec.decode(Data(contentsOf: destination))
            lastExternalBackup = Date()
            UserDefaults.standard.set(lastExternalBackup, forKey: lastBackupKey)
            backupStatus = "Copia esterna scritta e verificata. La sincronizzazione iCloud è gestita da iOS."
        } catch {
            backupStatus = "ATTENZIONE: copia esterna non aggiornata. \(error.localizedDescription)"
        }
    }

    private func validateExternalFolder(_ url: URL) throws {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        let container = URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().standardizedFileURL.path
        guard path != container && !path.hasPrefix(container + "/") else {
            throw NSError(domain: "PivotBackup", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Scegli una cartella in iCloud Drive o esterna a Pivot. La cartella interna sparirebbe cancellando l'app."])
        }
    }

    func exportURL() throws -> URL {
        let bytes: Data
        if locked { bytes = try Data(contentsOf: file) }
        else { bytes = try BackupCodec.encode(data) }
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("Backup Pivot.json")
        try bytes.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return destination
    }

    func restore(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let bytes = try Data(contentsOf: url)
            let restored = try BackupCodec.decode(bytes)
            if FileManager.default.fileExists(atPath: file.path) {
                let old = try Data(contentsOf: file)
                let archive = directory.appendingPathComponent("before-restore-\(Int(Date().timeIntervalSince1970)).json")
                try old.write(to: archive, options: .atomic)
            }
            try bytes.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            data = restored
            locked = false
            error = nil
            writeExternal(bytes)
        } catch { self.error = "Ripristino non eseguito: \(error.localizedDescription)" }
    }

    func record(for event: CalendarItem) -> EventRecord {
        data.records[event.id] ?? EventRecord(id: event.id, snapshot: event)
    }
    func rule(for event: CalendarItem) -> EventRule { data.rules[event.id] ?? .defaultRule(for: event) }
    func saveRecord(_ record: EventRecord) {
        var updated = record
        updated.updatedAt = Date()
        change { $0.records[updated.id] = updated }
    }
}

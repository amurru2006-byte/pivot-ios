import SwiftUI
import UniformTypeIdentifiers
import UIKit

private struct CoachDocumentExchangePreviewText: UIViewRepresentable {
    let text: String
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView(); view.isEditable = false; view.isSelectable = true
        view.dataDetectorTypes = []; view.font = .preferredFont(forTextStyle: .caption1)
        view.adjustsFontForContentSizeCategory = true; view.backgroundColor = .secondarySystemBackground
        view.accessibilityIdentifier = "coach-exchange-preview"
        view.text = text; return view
    }
    func updateUIView(_ uiView: UITextView, context: Context) { if uiView.text != text { uiView.text = text } }
}

private struct CoachDocumentExchangeTextFile: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, data.count <= 1_000_000,
              let text = String(data: data, encoding: .utf8) else { throw CoachDocumentReplyFile.Failure.invalid }
        self.text = text
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(text.utf8)
        guard data.count <= 1_000_000 else { throw CoachDocumentReviewStore.Failure.limit }
        return FileWrapper(regularFileWithContents: data)
    }
}

struct CoachDocumentExchangeView: View {
    let batchID: UUID
    @EnvironmentObject private var store: PivotStore
    @State private var preview: CoachDocumentExchange.Preview?
    @State private var checked = false
    @State private var exportFile: CoachDocumentExchangeTextFile?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var reply = ""
    @State private var busy = false
    @State private var status: String?
    @State private var importedID: UUID?
    @FocusState private var editingReply: Bool
    private var batch: CoachDocumentReviewBatch? { store.data.coachDocumentReviews?.first { $0.id == batchID } }
    private var current: Bool {
        guard let preview, let batch else { return false }
        return preview.batch == batch && batch.packet.isCurrent(in: store.data.coachDocuments ?? [])
    }
    var body: some View {
        Form {
            Section("Come funziona") {
                Text("È un passaggio manuale: salva o condividi la richiesta, allegala personalmente a ChatGPT, poi importa qui il JSON che ti restituisce. Pivot non invia nulla da solo e non accede al tuo account.")
                Text("Modelli, allegati e limiti dipendono dal tuo account e dalla piattaforma. Il ritorno automatico da ChatGPT non è disponibile in questo percorso.")
                    .font(.caption).foregroundStyle(.secondary)
                Link("Guida ufficiale agli allegati", destination: URL(string: "https://learn.chatgpt.com/docs/use-chatgpt")!)
                if let batch {
                    Text("Questa lettura contiene \(batch.packet.sources.count) fonti e \(batch.packet.pages.count) pagine selezionate.")
                    Button(batch.exchange == nil ? "Prepara la richiesta" : "Rigenera richiesta e invalida la precedente") {
                        Task { await prepare(batch) }
                    }.disabled(busy || !batch.stagedProposalIDs.isEmpty)
                        .accessibilityIdentifier("coach-exchange-prepare")
                }
            }
            if let preview {
                Section("Controlla tutto il testo prima di condividerlo") {
                    Text("La richiesta contiene il testo delle pagine scelte, che potrebbe includere dati personali. Non allega i PDF originali. Il file TXT salvato fuori Pivot è testo leggibile; la condivisione lo consegna al destinatario che scegli.")
                        .font(.caption)
                    CoachDocumentExchangePreviewText(text: preview.text).frame(height: 220)
                        .accessibilityIdentifier("coach-exchange-preview")
                    Toggle("Ho controllato richiesta e pagine e voglio poterle salvare o condividere", isOn: $checked)
                        .disabled(busy || !current).accessibilityIdentifier("coach-exchange-approve-export")
                    Button("Salva richiesta TXT") {
                        exportFile = .init(text: preview.text); showExporter = true
                    }.disabled(!checked || !current || busy).accessibilityIdentifier("coach-exchange-save-file")
                    ShareLink(item: preview.text) { Label("Condividi richiesta…", systemImage: "square.and.arrow.up") }
                        .disabled(!checked || !current || busy).accessibilityIdentifier("coach-exchange-share")
                    Text("Se ChatGPT non compare fra le destinazioni di Condividi, salva il file e allegalo da ChatGPT. Non è necessario installare un nuovo servizio da Pivot.")
                        .font(.caption).foregroundStyle(.secondary)
                    if !current { Text("La revisione è cambiata: la vecchia anteprima non può essere esportata o usata per il ritorno.").foregroundStyle(.orange) }
                }
                Section("Riporta la risposta") {
                    Text("Chiedi soltanto il JSON, senza testo esterno. Puoi incollarlo volontariamente oppure scegliere il file della risposta. L’importazione aggiunge una revisione: non prepara bozze e non crea eventi.")
                        .font(.caption)
                    TextEditor(text: $reply).frame(minHeight: 160).focused($editingReply)
                        .accessibilityIdentifier("coach-exchange-reply")
                        .disabled(busy || !current)
                    Text("\(reply.utf8.count) di 64.000 byte")
                        .font(.caption).foregroundStyle(reply.utf8.count > 64_000 ? .orange : .secondary)
                    Button("Importa il JSON incollato") {
                        editingReply = false
                        Task { await receive(Data(reply.utf8), expected: preview.batch) }
                    }.disabled(busy || !current || reply.isEmpty || reply.utf8.count > 64_000)
                        .accessibilityIdentifier("coach-exchange-import-text")
                    Button("Scegli il file JSON della risposta") { showImporter = true }
                        .disabled(busy || !current).accessibilityIdentifier("coach-exchange-import-file")
                }
            }
            if busy { ProgressView("Verifica e salvataggio locale…") }
            if let status { Text(status).accessibilityIdentifier("coach-exchange-status") }
            if let importedID {
                NavigationLink("Rivedi le proposte importate") { CoachDocumentReviewView(batchID: importedID) }
                    .accessibilityIdentifier("coach-exchange-open-result")
            }
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--interaction-test"),
               UUID(uuidString: ProcessInfo.processInfo.environment["PIVOT_QA_DOCUMENT_ID"] ?? "") != nil {
                Text("\(store.data.coachDocumentReviews?.count ?? 0) revisioni QA")
                    .accessibilityIdentifier("coach-exchange-revisions-audit")
                if let preview {
                    Text(preview.batch.exchange?.id.uuidString ?? "")
                        .accessibilityIdentifier("coach-exchange-request-audit")
                    Button("Importa risposta inventata QA") { Task { await receiveFixture(preview) } }
                        .disabled(busy || !current).accessibilityIdentifier("coach-exchange-synthetic-reply")
                }
            }
            #endif
        }
        .navigationTitle("Scambio manuale")
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer(); Button("Fine") { editingReply = false }.accessibilityIdentifier("coach-exchange-keyboard-done")
            }
        }
        .task {
            guard batch?.exchange != nil else { return }
            busy = true; defer { busy = false }
            do { preview = try await store.loadCoachDocumentExchange(batchID) }
            catch { status = error.localizedDescription }
        }
        .onChange(of: batch?.exchange?.id) { _, _ in checked = false }
        .fileExporter(isPresented: $showExporter, document: exportFile, contentType: .plainText, defaultFilename: "Richiesta-Pivot") { result in
            switch result {
            case .success: status = "File salvato nella destinazione scelta. Allegalo personalmente a ChatGPT e riporta qui la risposta."
            case .failure(let error): status = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json, .plainText]) { result in
            guard let expected = preview?.batch else { return }
            switch result {
            case .success(let url): Task { await receiveFile(url, expected: expected) }
            case .failure(let error): status = error.localizedDescription
            }
        }
    }
    #if DEBUG && targetEnvironment(simulator)
    @MainActor private func receiveFixture(_ preview: CoachDocumentExchange.Preview) async {
        guard ProcessInfo.processInfo.arguments.contains("--interaction-test"),
              UUID(uuidString: ProcessInfo.processInfo.environment["PIVOT_QA_DOCUMENT_ID"] ?? "") != nil,
              let scope = preview.batch.exchange, let source = preview.batch.packet.sources.first,
              let page = preview.batch.packet.pages.first(where: { $0.sourceID == source.id }) else { return }
        do {
            let bytes = try JSONSerialization.data(withJSONObject: ["version": 1, "requestID": scope.id.uuidString,
                "events": [["kind": "allDay", "title": "Risposta sintetica QA", "day": "2030-01-14", "startClock": NSNull(),
                            "endDay": NSNull(), "endClock": NSNull(), "notes": "", "citations": [
                                ["document": "d1", "page": page.number, "quote": page.text]], "questions": []]], "questions": []])
            await receive(bytes, expected: preview.batch)
        } catch { status = error.localizedDescription }
    }
    #endif
    @MainActor private func prepare(_ expected: CoachDocumentReviewBatch) async {
        busy = true; status = nil; checked = false; preview = nil; importedID = nil
        defer { busy = false }
        do { preview = try await store.prepareCoachDocumentExchange(expected) }
        catch { status = error.localizedDescription }
    }
    @MainActor private func receive(_ bytes: Data, expected: CoachDocumentReviewBatch) async {
        guard !busy, current else { return }
        busy = true; status = nil; defer { busy = false }
        do {
            importedID = try await store.receiveCoachDocumentReply(bytes, expected: expected)
            checked = false; preview = nil; reply = ""
            status = "Risposta verificata e salvata come revisione separata. Controllala: nessuna bozza o evento sono stati creati."
        } catch { status = error.localizedDescription }
    }
    @MainActor private func receiveFile(_ url: URL, expected: CoachDocumentReviewBatch) async {
        guard !busy, current else { return }
        busy = true; status = nil; defer { busy = false }
        do {
            let bytes = try await Task.detached(priority: .utility) { try CoachDocumentReplyFile.read(url) }.value
            importedID = try await store.receiveCoachDocumentReply(bytes, expected: expected)
            checked = false; preview = nil; reply = ""
            status = "Risposta verificata e salvata come revisione separata. Nessuna bozza o evento sono stati creati."
        } catch { status = error.localizedDescription }
    }
}

import SwiftUI
import PDFKit

struct CoachDocumentDestination: Identifiable {
    var sourceID: UUID
    var page: Int = 1
    var id: String { sourceID.uuidString + ":" + String(page) }
}

/// A snapshot of bytes already checked against the saved source hash. PDFKit
/// never opens an arbitrary remote URL or a path supplied in a chat response.
private struct CoachVerifiedPDF: UIViewRepresentable {
    let bytes: Data
    let page: Int
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous
        view.document = PDFDocument(data: bytes)
        if let target = view.document?.page(at: page - 1) { view.go(to: target) }
        return view
    }
    func updateUIView(_ uiView: PDFView, context: Context) {}
}

struct CoachDocumentViewer: View {
    let destination: CoachDocumentDestination
    @EnvironmentObject private var store: PivotStore
    @Environment(\.dismiss) private var dismiss
    @State private var bytes: Data?
    @State private var error: String?
    private var source: CoachDocumentSource? { store.data.coachDocuments?.first { $0.id == destination.sourceID } }
    var body: some View {
        NavigationStack {
            Group {
                if let bytes {
                    CoachVerifiedPDF(bytes: bytes, page: destination.page)
                        .id(destination.id + (source?.document.id.uuidString ?? ""))
                }
                else if let error { ContentUnavailableView("Fonte non disponibile", systemImage: "doc.badge.ellipsis", description: Text(error)) }
                else { ProgressView("Verifico il documento…") }
            }
            .navigationTitle(source?.document.name ?? "Documento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } } }
            .task(id: source?.document.id) {
                bytes = nil; error = nil
                guard let source, (1...source.pageCount).contains(destination.page) else { error = "La pagina o la fonte non sono più disponibili."; return }
                do { bytes = try await store.coachDocumentBytes(source.id) }
                catch is CancellationError { }
                catch { self.error = error.localizedDescription }
            }
        }
    }
}

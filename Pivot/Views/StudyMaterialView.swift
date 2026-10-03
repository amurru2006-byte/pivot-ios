import SwiftUI
import PDFKit

struct StudyPDFPreview: View {
    let url: URL
    let title: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            PDFReader(url: url)
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } }
                    ToolbarItem(placement: .bottomBar) { ShareLink(item: url) { Label("Condividi PDF", systemImage: "square.and.arrow.up") } }
                }
        }
    }
}

private struct PDFReader: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .systemBackground
        view.document = PDFDocument(url: url)
        return view
    }
    func updateUIView(_ uiView: PDFView, context: Context) {}
}

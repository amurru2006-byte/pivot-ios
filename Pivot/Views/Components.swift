import SwiftUI
import UniformTypeIdentifiers

extension Color {
    init(pivotHex: String) {
        let hex = pivotHex.replacingOccurrences(of: "#", with: "")
        let number = UInt64(hex, radix: 16) ?? 0x70D7BD
        self.init(red: Double((number >> 16) & 255) / 255, green: Double((number >> 8) & 255) / 255, blue: Double(number & 255) / 255)
    }
}

struct RatingField: View {
    let title: String
    @Binding var value: Int?
    var body: some View {
        VStack(alignment: .leading) {
            Stepper("\(title): \(value.map(String.init) ?? "non indicato") / 10", value: Binding(get: { value ?? 0 }, set: { value = $0 }), in: 0...10)
            if value != nil { Button("Non indicare \(title.lowercased())") { value = nil }.font(.caption) }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct FolderPicker: UIViewControllerRepresentable {
    let onSelect: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: FolderPicker
        init(parent: FolderPicker) { self.parent = parent }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { parent.onSelect(url) }
            parent.dismiss()
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { parent.dismiss() }
    }
}

struct EventRow: View {
    let event: CalendarItem
    let record: EventRecord?
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3).fill(Color(pivotHex: event.colorHex)).frame(width: 5)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title).font(.headline)
                Text(event.isAllDay ? "Tutto il giorno" : "\(PivotDate.time(event.start)) – \(PivotDate.time(event.end))").font(.subheadline)
                Text(event.calendarTitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(record?.status.label ?? "Da fare").font(.caption).foregroundStyle(record?.status == .completed ? .mint : .secondary)
        }.padding(.vertical, 5)
    }
}

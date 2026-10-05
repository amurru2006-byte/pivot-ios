import SwiftUI
import UniformTypeIdentifiers
import UIKit

extension Color {
    static func readableCalendar(_ item: CalendarItem) -> Color {
        let source = UIColor(Color(calendarItem: item))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, alpha: CGFloat = 0
        source.getRed(&r, green: &g, blue: &b, alpha: &alpha)
        func linear(_ value: CGFloat) -> Double {
            let v = Double(value); return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        var blend = 0.0
        // Original color remains on the stripe; text alone is lifted for dark-mode contrast.
        while blend < 0.85 {
            let rr = Double(r) + (1 - Double(r)) * blend, gg = Double(g) + (1 - Double(g)) * blend, bb = Double(b) + (1 - Double(b)) * blend
            if (0.2126 * linear(CGFloat(rr)) + 0.7152 * linear(CGFloat(gg)) + 0.0722 * linear(CGFloat(bb)) + 0.05) / 0.062 >= 4.5 {
                return Color(.sRGB, red: rr, green: gg, blue: bb)
            }
            blend += 0.05
        }
        return PivotTheme.text
    }
    init(calendarItem: CalendarItem) {
        if let rgb = calendarItem.calendarRGB {
            self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: rgb.alpha)
        } else { self.init(pivotHex: calendarItem.colorHex) }
    }
    init(pivotHex: String) {
        let hex = pivotHex.replacingOccurrences(of: "#", with: "")
        let number = UInt64(hex, radix: 16) ?? 0x70D7BD
        self.init(red: Double((number >> 16) & 255) / 255, green: Double((number >> 8) & 255) / 255, blue: Double(number & 255) / 255)
    }
}

enum PivotTheme {
    static let background = Color(pivotHex: "0B101A")
    static let surface = Color(pivotHex: "161E2B")
    static let raised = Color(pivotHex: "202B3B")
    static let accent = Color(pivotHex: "7EE6CD")
    static let blue = Color(pivotHex: "93B7FF")
    static let amber = Color(pivotHex: "F7C783")
    static let text = Color(pivotHex: "F2F5FA")
    static let muted = Color(pivotHex: "A5B2C5")
}

extension EventKind {
    var icon: String {
        switch self {
        case .routine: return "sun.max.fill"
        case .meal: return "fork.knife"
        case .study: return "book.closed.fill"
        case .workout: return "dumbbell.fill"
        case .university: return "graduationcap.fill"
        case .tutoring: return "person.2.fill"
        case .work: return "briefcase.fill"
        case .social: return "person.3.fill"
        case .partner: return "heart.fill"
        case .friends: return "person.3.fill"
        case .exam: return "pencil.and.outline"
        case .other: return "calendar"
        }
    }
}

enum DisplayDate {
    static func label(_ date: Date, format: String = "EEEE d MMMM") -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.timeZone = PivotDate.calendar.timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}

struct PivotScreen<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) { content }
                .frame(maxWidth: 680).padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 28)
                .frame(maxWidth: .infinity)
        }
        .background(LinearGradient(colors: [Color(pivotHex: "101D2A"), PivotTheme.background], startPoint: .topLeading, endPoint: .center).ignoresSafeArea())
        .foregroundStyle(PivotTheme.text)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Fine") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(PivotTheme.background, for: .navigationBar)
    }
}

struct PivotCard<Content: View>: View {
    var tint: Color? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(LinearGradient(colors: [(tint ?? PivotTheme.surface).opacity(tint == nil ? 1 : 0.18), PivotTheme.surface], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.07)))
    }
}

struct PivotHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text(subtitle).font(.subheadline).foregroundStyle(PivotTheme.muted)
        }
    }
}

struct SectionHeading: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        HStack {
            Text(title).font(.system(.headline, design: .rounded))
            Spacer()
            if let detail { Text(detail).font(.caption).foregroundStyle(PivotTheme.muted) }
        }
    }
}

struct PivotPrimaryButton: ButtonStyle {
    var color = PivotTheme.accent
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15).padding(.horizontal, 12)
            .foregroundStyle(enabled ? PivotTheme.background : PivotTheme.muted)
            .background(enabled ? color : PivotTheme.raised, in: RoundedRectangle(cornerRadius: 16))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct PivotSecondaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(14)
            .foregroundStyle(enabled ? PivotTheme.accent : PivotTheme.muted)
            .background(PivotTheme.accent.opacity(enabled ? 0.08 : 0.02), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(PivotTheme.accent.opacity(0.16)))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct StatusPill: View {
    let status: Completion
    var color: Color {
        switch status {
        case .completed: return PivotTheme.accent
        case .running: return PivotTheme.blue
        case .partial: return PivotTheme.amber
        case .skipped: return Color(pivotHex: "F6A9BE")
        case .pending: return PivotTheme.muted
        }
    }
    var body: some View {
        Text(status == .pending ? "Da fare" : status.label).font(.caption2.weight(.semibold))
            .padding(.horizontal, 9).padding(.vertical, 5).foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let icon: String
    var color = PivotTheme.accent
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon).font(.subheadline).foregroundStyle(color)
            Text(value).font(.system(.title3, design: .rounded, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.caption).foregroundStyle(PivotTheme.muted)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(PivotTheme.surface, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct EmptyCard: View {
    let title: String
    let message: String
    let icon: String
    var body: some View {
        PivotCard {
            Image(systemName: icon).font(.title2).foregroundStyle(PivotTheme.blue)
                .frame(width: 48, height: 48).background(PivotTheme.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(PivotTheme.muted)
        }
    }
}

struct DaySelector: View {
    @Binding var day: Date
    var body: some View {
        VStack(spacing: 4) {
          HStack {
            Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("Giorno precedente")
            Spacer()
            DatePicker("Giornata", selection: $day, displayedComponents: .date).labelsHidden()
            Spacer()
            Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.accessibilityLabel("Giorno successivo")
          }
          Button("Oggi") { day = Date() }.font(.subheadline.weight(.semibold)).padding(.bottom, 10).accessibilityIdentifier("return-today")
        }.padding(.horizontal, 5).background(PivotTheme.surface, in: RoundedRectangle(cornerRadius: 16))
    }
    private func shift(_ amount: Int) { if let next = PivotDate.calendar.date(byAdding: .day, value: amount, to: day) { day = next } }
}

struct ActionRow: View {
    let title: String
    let subtitle: String
    let icon: String
    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon).font(.title3).foregroundStyle(PivotTheme.accent)
                .frame(width: 44, height: 44).background(PivotTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(PivotTheme.text)
                Text(subtitle).font(.caption).foregroundStyle(PivotTheme.muted)
            }
            Spacer(minLength: 5)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(PivotTheme.muted)
        }
    }
}

extension View {
    func pivotForm() -> some View { self.scrollContentBackground(.hidden).background(PivotTheme.background).tint(PivotTheme.accent).navigationBarTitleDisplayMode(.inline) }
}

struct RatingField: View {
    let title: String
    @Binding var value: Int?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(value.map { "\($0)/10" } ?? "Da indicare").font(.subheadline.monospacedDigit()).foregroundStyle(PivotTheme.accent)
            }
            Slider(value: Binding(get: { Double(value ?? 5) }, set: { value = Int($0.rounded()) }), in: 0...10, step: 1)
                .accessibilityLabel(title)
            HStack {
                Text("0"); Spacer()
                if value == nil { Button("Indica 5/10") { value = 5 } }
                else { Button("Cancella") { value = nil } }
                Spacer(); Text("10")
            }.font(.caption).foregroundStyle(PivotTheme.muted)
        }.padding(.vertical, 4)
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
    var day: Date = Date()
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(event.agendaStart(on: day)).font(.subheadline.weight(.semibold)).foregroundStyle(PivotTheme.text)
                if !event.isAllDay { Text(event.agendaEnd(on: day)).font(.caption).foregroundStyle(PivotTheme.muted) }
            }.frame(width: 47, alignment: .leading).padding(.top, 4)
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Label(event.kind.label, systemImage: event.kind.icon).font(.caption).foregroundStyle(Color.readableCalendar(event))
                    Spacer(minLength: 3)
                    StatusPill(status: record?.status ?? .pending)
                }
                Text(event.title).font(.system(.subheadline, design: .rounded, weight: .semibold)).foregroundStyle(PivotTheme.text).fixedSize(horizontal: false, vertical: true)
                if !event.isAllDay && !PivotDate.calendar.isDate(event.start, inSameDayAs: event.end) {
                    Text(event.timeSummary).font(.caption).foregroundStyle(PivotTheme.muted)
                }
                HStack {
                    Text(event.calendarTitle).font(.caption).foregroundStyle(PivotTheme.muted)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(PivotTheme.muted)
                }
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [Color(calendarItem: event).opacity(0.08), PivotTheme.surface], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 18))
                .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 3).fill(Color(calendarItem: event)).frame(width: 5).padding(.vertical, 14) }
        }.opacity([Completion.completed, .partial].contains(record?.status ?? .pending) ? 0.52 : 1)
    }
}

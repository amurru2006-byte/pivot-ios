import SwiftUI

struct ClockField: View {
    let title: String
    @Binding var value: Date?
    let fallback: Date
    @State private var editing = false
    @State private var draft = Date()
    var body: some View {
        Button {
            draft = value ?? fallback; editing = true
        } label: {
            HStack {
                Text(title).foregroundStyle(PivotTheme.text)
                Spacer()
                Text(value.map { "\(PivotDate.shortDate($0)) · \(PivotDate.time($0))" } ?? "Da indicare").foregroundStyle(PivotTheme.accent)
                Image(systemName: "chevron.right").font(.caption)
            }.font(.subheadline).padding(.vertical, 8)
        }.buttonStyle(.plain)
        .sheet(isPresented: $editing) {
            NavigationStack {
                VStack(spacing: 18) {
                    DatePicker("Data", selection: $draft, displayedComponents: .date).datePickerStyle(.compact)
                    DatePicker(title, selection: $draft, displayedComponents: .hourAndMinute).datePickerStyle(.wheel).labelsHidden()
                    Button("Conferma orario") { value = draft; editing = false }.buttonStyle(PivotPrimaryButton())
                    if value != nil { Button("Cancella orario", role: .destructive) { value = nil; editing = false } }
                }.padding(24).navigationTitle(title)
                    .toolbar { Button("Annulla") { editing = false } }
                    .background(PivotTheme.background.ignoresSafeArea())
            }.presentationDetents([.medium, .large])
        }
    }
}

struct DurationField: View {
    let title: String
    @Binding var seconds: Int?
    var maxHours: Int = 48
    var showSeconds = false
    @State private var editing = false
    @State private var hours = 0
    @State private var minutes = 0
    @State private var remainder = 0
    var body: some View {
        Button {
            let value = max(0, seconds ?? 0)
            hours = min(maxHours, value / 3600); minutes = value % 3600 / 60; remainder = value % 60
            editing = true
        } label: {
            HStack {
                Text(title).foregroundStyle(PivotTheme.text)
                Spacer()
                Text(seconds.map(ActivityTiming.duration) ?? "Da indicare").foregroundStyle(PivotTheme.accent).monospacedDigit()
            }.font(.subheadline).padding(.vertical, 8)
        }.buttonStyle(.plain)
        .sheet(isPresented: $editing) {
            NavigationStack {
                VStack(spacing: 20) {
                    HStack(spacing: 0) {
                        Picker("Ore", selection: $hours) { ForEach(0...maxHours, id: \.self) { Text("\($0) h").tag($0) } }.pickerStyle(.wheel)
                        Picker("Minuti", selection: $minutes) { ForEach(0...59, id: \.self) { Text("\($0) min").tag($0) } }.pickerStyle(.wheel)
                        if showSeconds { Picker("Secondi", selection: $remainder) { ForEach(0...59, id: \.self) { Text("\($0) s").tag($0) } }.pickerStyle(.wheel) }
                    }
                    Button("Conferma durata") { seconds = hours * 3600 + minutes * 60 + (showSeconds ? remainder : 0); editing = false }.buttonStyle(PivotPrimaryButton())
                    if seconds != nil { Button("Cancella durata", role: .destructive) { seconds = nil; editing = false } }
                }.padding(20).navigationTitle(title).toolbar { Button("Annulla") { editing = false } }
                    .background(PivotTheme.background.ignoresSafeArea())
            }.presentationDetents([.medium, .large])
        }
    }
}

struct DecimalField: View {
    let title: String
    let unit: String
    @Binding var value: Double?
    var identifier: String = ""
    @State private var input = ""
    var body: some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            TextField("—", text: $input).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 100).accessibilityIdentifier(identifier)
            Text(unit).font(.caption).foregroundStyle(PivotTheme.muted)
        }
        .onAppear { input = value.map { String($0).replacingOccurrences(of: ".", with: ",") } ?? "" }
        .onChange(of: input) { _, text in
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            value = trimmed.isEmpty ? nil : Double(trimmed.replacingOccurrences(of: ",", with: ".")) ?? .nan
        }
    }
}

struct IntegerField: View {
    let title: String
    @Binding var value: Int?
    var identifier: String = ""
    @State private var input = ""
    var body: some View {
        HStack {
            Text(title).font(.subheadline); Spacer()
            TextField("—", text: $input).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(maxWidth: 80).accessibilityIdentifier(identifier)
        }.onAppear { input = value.map(String.init) ?? "" }
            .onChange(of: input) { _, text in value = text.isEmpty ? nil : Int(text) ?? -1 }
    }
}

import SwiftUI

struct DiaryView: View {
    @EnvironmentObject var store: PivotStore
    @EnvironmentObject var calendar: CalendarService
    @State private var day = Date()
    @State private var sharing = false
    var history: [CalendarItem] {
        var map = Dictionary(store.data.records.values.map { ($0.id, $0.snapshot) }, uniquingKeysWith: { _, newest in newest })
        for item in Planner.effectiveEvents(calendar.events, data: store.data) { map[item.id] = item }
        return Array(map.values)
    }
    var report: String { Report.day(day, events: history, data: store.data) }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker("Giornata", selection: $day, displayedComponents: .date)
                    NavigationLink("Completa sveglia, energia e umore") { DayCheckInView(day: day, initial: store.data.checkIns[PivotDate.key(day)]) }
                    Button("Condividi resoconto") { sharing = true }
                }
                Section("Resoconto") { Text(report).font(.callout).textSelection(.enabled) }
                Section("Recuperi approvati") {
                    ForEach(store.data.moves.filter { PivotDate.calendar.isDate($0.createdAt, inSameDayAs: day) }) { move in
                        VStack(alignment: .leading) {
                            Text(move.source.title)
                            Text("\(PivotDate.key(move.proposedStart)) · \(PivotDate.time(move.proposedStart))–\(PivotDate.time(move.proposedEnd))").font(.caption)
                            Text(move.syncedToCalendar ? "Modificato anche nel Calendario" : "Solo in Pivot").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }.navigationTitle("Diario")
                .sheet(isPresented: $sharing) { ShareSheet(items: [report]) }
        }
    }
}

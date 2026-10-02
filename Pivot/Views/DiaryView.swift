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
    var items: [CalendarItem] { history.filter { PivotDate.calendar.isDate($0.start, inSameDayAs: day) }.sorted { $0.start < $1.start } }
    var answered: Int { items.filter { [.completed, .partial, .skipped].contains(store.data.records[$0.id]?.status ?? .pending) }.count }
    var completed: Int { items.filter { store.data.records[$0.id]?.status == .completed }.count }
    var check: DayCheckIn? { store.data.checkIns[PivotDate.key(day)] }
    var report: String { Report.day(day, events: history, data: store.data) }
    var body: some View {
        NavigationStack {
            PivotScreen {
                PivotHeader(title: "Il tuo ritmo", subtitle: "Una giornata alla volta, anche quando cambia il piano.")
                DaySelector(day: $day)
                summary
                HStack(alignment: .top, spacing: 9) {
                    MetricTile(title: "Sveglia", value: check?.wakeTime.map(PivotDate.time) ?? "—", icon: "sun.max.fill", color: PivotTheme.amber)
                    MetricTile(title: "Energia sera", value: check?.energyEvening.map { "\($0)/10" } ?? "—", icon: "bolt.fill", color: PivotTheme.blue)
                    MetricTile(title: "Registrati", value: "\(items.reduce(0) { $0 + (store.data.records[$1.id]?.activeMinutes ?? 0) }) min", icon: "clock.fill")
                }
                NavigationLink { DayCheckInView(day: day, initial: check) } label: {
                    PivotCard { ActionRow(title: "Completa il tuo check-in", subtitle: "Sveglia, energia, umore e note della giornata.", icon: "heart.text.square") }
                }.buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeading(title: "La giornata, in breve", detail: DisplayDate.label(day, format: "d MMM"))
                    if items.isEmpty { EmptyCard(title: "Il diario parte da qui", message: "Registra un'attività o il tuo check-in: ritroverai qui il riepilogo.", icon: "book.closed") }
                    ForEach(items) { item in
                        NavigationLink { EventDetailView(event: item, initial: store.record(for: item), rule: store.rule(for: item)) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                EventRow(event: item, record: store.data.records[item.id])
                                if let record = store.data.records[item.id] {
                                    if !record.reason.isEmpty { Text(record.reason).font(.caption).foregroundStyle(PivotTheme.amber).padding(.leading, 59) }
                                    if !record.notes.isEmpty { Text(record.notes).font(.caption).foregroundStyle(PivotTheme.muted).lineLimit(3).padding(.leading, 59) }
                                }
                            }
                        }.buttonStyle(.plain)
                    }
                }
                if let check, !check.notes.isEmpty { PivotCard { SectionHeading(title: "Le tue parole"); Text(check.notes).font(.subheadline).textSelection(.enabled) } }
                let moves = store.data.moves.filter { PivotDate.calendar.isDate($0.createdAt, inSameDayAs: day) }
                if !moves.isEmpty {
                    PivotCard {
                        SectionHeading(title: "Recuperi approvati")
                        ForEach(moves) { move in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(move.source.title).font(.subheadline.weight(.semibold))
                                Text("\(DisplayDate.label(move.proposedStart, format: "d MMM")) · \(PivotDate.time(move.proposedStart))–\(PivotDate.time(move.proposedEnd))").font(.caption).foregroundStyle(PivotTheme.muted)
                                Label(move.syncedToCalendar ? "Anche nel Calendario" : "Solo in Pivot", systemImage: move.syncedToCalendar ? "calendar.badge.checkmark" : "arrow.triangle.2.circlepath").font(.caption).foregroundStyle(PivotTheme.accent)
                            }
                        }
                    }
                }
                PivotCard {
                    DisclosureGroup("Resoconto completo") { Text(report).font(.callout).foregroundStyle(PivotTheme.muted).textSelection(.enabled).padding(.top, 12) }
                }
            }.navigationTitle("Diario")
                .sheet(isPresented: $sharing) { ShareSheet(items: [report]) }
        }
    }
    private var summary: some View {
        PivotCard(tint: PivotTheme.accent) {
            HStack(spacing: 20) {
                ZStack {
                    Circle().stroke(PivotTheme.accent.opacity(0.12), lineWidth: 7)
                    Circle().trim(from: 0, to: items.isEmpty ? 0 : CGFloat(answered) / CGFloat(items.count)).stroke(PivotTheme.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(-90))
                    Text("\(answered)/\(items.count)").font(.system(.title3, design: .rounded, weight: .bold))
                }.frame(width: 78, height: 78).accessibilityLabel("\(answered) attività compilate su \(items.count)")
                VStack(alignment: .leading, spacing: 7) {
                    Text("La tua giornata raccontata").font(.headline)
                    Text("\(completed) completate · \(items.count - answered) da compilare").font(.subheadline).foregroundStyle(PivotTheme.muted)
                    Text("Anche ciò che salta ci aiuta a capire.").font(.caption).foregroundStyle(PivotTheme.muted)
                }
            }
            Button { sharing = true } label: { Label("Condividi resoconto", systemImage: "square.and.arrow.up") }.buttonStyle(PivotPrimaryButton())
        }
    }
}

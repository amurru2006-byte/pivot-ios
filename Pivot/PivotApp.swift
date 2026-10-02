import SwiftUI
import EventKit

@main
struct PivotApp: App {
    @StateObject private var store = PivotStore()
    @StateObject private var calendar = CalendarService()
    @StateObject private var notifications = NotificationService()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(calendar)
                .environmentObject(notifications)
                .preferredColorScheme(.dark)
                .tint(PivotTheme.accent)
                .environment(\.locale, Locale(identifier: "it_IT"))
                .environment(\.timeZone, PivotDate.calendar.timeZone)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: PivotStore
    @EnvironmentObject var calendar: CalendarService
    @EnvironmentObject var notifications: NotificationService
    @Environment(\.scenePhase) var scene
    @State private var selectedTab = PreviewMode.enabled ? PreviewMode.tab : 0
    var body: some View {
        Group {
            if PreviewMode.enabled && PreviewMode.screen == "detail", let event = calendar.events.first(where: { $0.id == "study" }) {
                NavigationStack { EventDetailView(event: event, initial: store.record(for: event), rule: store.rule(for: event)) }
            } else if PreviewMode.enabled && PreviewMode.screen == "client" {
                ClientForm()
            } else if PreviewMode.enabled && PreviewMode.screen == "lesson" && !store.data.clients.isEmpty {
                LessonForm(clients: store.data.clients)
            } else if PreviewMode.enabled && PreviewMode.screen == "payment", let entry = store.data.income.first(where: { $0.outstandingCents > 0 }) {
                NavigationStack { IncomeDetailView(entryID: entry.id) }
            } else if PreviewMode.enabled && PreviewMode.screen == "checkin" {
                NavigationStack { DayCheckInView(day: Date(), initial: store.data.checkIns[PivotDate.key(Date())]) }
            } else { tabs }
        }
        .task {
            if PreviewMode.enabled { PreviewMode.prepare(store: store, calendar: calendar) }
            else { await refresh() }
        }
        .onChange(of: scene) { _, value in if value == .active { Task { await refresh() } } }
        .onChange(of: store.data.updatedAt) { _, _ in Task { await refresh() } }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in Task { await refresh() } }
        .alert("Pivot", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
    private var tabs: some View {
        TabView(selection: $selectedTab) {
            TodayView().tag(0).tabItem { Label("Oggi", systemImage: "calendar") }
            DiaryView().tag(1).tabItem { Label("Diario", systemImage: "book.closed.fill") }
            IncomeView().tag(2).tabItem { Label("Entrate", systemImage: "eurosign.circle.fill") }
            SettingsView().tag(3).tabItem { Label("Impostazioni", systemImage: "gearshape.fill") }
        }
        .toolbarBackground(PivotTheme.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
    private func refresh() async {
        guard !PreviewMode.enabled else { return }
        calendar.refresh(settings: store.data.settings)
        await notifications.schedule(events: Planner.effectiveEvents(calendar.events, data: store.data), data: store.data)
    }
}

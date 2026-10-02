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
                .tint(.mint)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: PivotStore
    @EnvironmentObject var calendar: CalendarService
    @EnvironmentObject var notifications: NotificationService
    @Environment(\.scenePhase) var scene
    var body: some View {
        TabView {
            TodayView().tabItem { Label("Oggi", systemImage: "calendar") }
            DiaryView().tabItem { Label("Diario", systemImage: "text.book.closed") }
            IncomeView().tabItem { Label("Entrate", systemImage: "eurosign.circle") }
            SettingsView().tabItem { Label("Impostazioni", systemImage: "gearshape") }
        }
        .task { await refresh() }
        .onChange(of: scene) { _, value in if value == .active { Task { await refresh() } } }
        .onChange(of: store.data.updatedAt) { _, _ in Task { await refresh() } }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in Task { await refresh() } }
        .alert("Pivot", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
    private func refresh() async {
        calendar.refresh(settings: store.data.settings)
        await notifications.schedule(events: Planner.effectiveEvents(calendar.events, data: store.data), data: store.data)
    }
}

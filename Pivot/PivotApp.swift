import SwiftUI
import EventKit
import UIKit

final class PivotAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        return true
    }
}

@main
struct PivotApp: App {
    @UIApplicationDelegateAdaptor(PivotAppDelegate.self) private var appDelegate
    @StateObject private var store = WorkoutRuntime.store
    @StateObject private var calendar = CalendarService()
    @StateObject private var notifications = NotificationService()
    @StateObject private var coachModel = LocalCoachService()
    @StateObject private var health = HealthService.shared
    @StateObject private var agenda = AgendaService()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(calendar)
                .environmentObject(notifications)
                .environmentObject(coachModel)
                .environmentObject(health)
                .environmentObject(agenda)
                .environmentObject(store.diagnostics)
                .preferredColorScheme(.dark)
                .tint(PivotTheme.accent)
                .environment(\.locale, Locale(identifier: "it_IT"))
                .environment(\.timeZone, PivotDate.calendar.timeZone)
        }
    }
}

@MainActor
struct RootView: View {
    @EnvironmentObject var store: PivotStore
    @EnvironmentObject var calendar: CalendarService
    @EnvironmentObject var notifications: NotificationService
    @EnvironmentObject var health: HealthService
    @EnvironmentObject var coachModel: LocalCoachService
    @EnvironmentObject var agenda: AgendaService
    @Environment(\.scenePhase) var scene
    @State private var selectedTab = PreviewMode.enabled ? PreviewMode.tab : 0
    @State private var previewReady = !PreviewMode.enabled
    @State private var refreshGate = RefreshGate()
    @State private var notificationGate = RefreshGate()
    @State private var workoutLink: WorkoutDeepLink?
    @State private var workoutPath: [WorkoutRoute] = []
    // EventKit normally pushes changes immediately. This short safety refresh
    // also catches delayed iCloud deletions/moves without blocking the UI.
    private let refreshClock = Timer.publish(every: 20, on: .main, in: .common).autoconnect()
    var body: some View {
        Group {
            if !previewReady {
                ProgressView("Anteprima…")
            } else if PreviewMode.enabled && PreviewMode.screen == "launch" { PivotLaunchView()
            } else if PreviewMode.enabled && PreviewMode.screen == "coach" {
                NavigationStack { CoachView() }
            } else if PreviewMode.enabled && PreviewMode.screen == "tutoring", let event = calendar.events.first(where: { $0.kind == .tutoring }) {
                NavigationStack { EventDetailView(event: event, initial: store.record(for: event), rule: store.rule(for: event)) }
            } else if PreviewMode.enabled && PreviewMode.screen == "detail", let event = calendar.events.first(where: { $0.id == "study" }) {
                NavigationStack { EventDetailView(event: event, initial: store.record(for: event), rule: store.rule(for: event)) }
            } else if PreviewMode.enabled && PreviewMode.screen == "client" {
                ClientForm()
            } else if PreviewMode.enabled && PreviewMode.screen == "lesson" && !store.data.clients.isEmpty {
                LessonForm(clients: store.data.clients)
            } else if PreviewMode.enabled && PreviewMode.screen == "payment", let entry = store.data.income.first(where: { $0.outstandingCents > 0 }) {
                NavigationStack { IncomeDetailView(entryID: entry.id) }
            } else if PreviewMode.enabled && PreviewMode.screen == "checkin" {
                NavigationStack { DayCheckInView(day: Date(), initial: store.data.checkIns[PivotDate.key(Date())]) }
            } else if PreviewMode.enabled && ["duplicates", "overnight"].contains(PreviewMode.screen) {
                NavigationStack {
                    PivotScreen {
                        let day = PreviewMode.screen == "overnight" ? PivotDate.calendar.date(byAdding: .day, value: 1, to: Date())! : Date()
                        PivotHeader(title: "La tua agenda", subtitle: DisplayDate.label(day).capitalized)
                        ForEach(Planner.plannedEvents(calendar.events, data: store.data).filter { $0.occurs(on: day) }) { event in
                            EventRow(event: event, record: store.data.records[event.id], day: day)
                        }
                    }.navigationTitle("Pivot")
                }
            } else if PreviewMode.enabled && ["friends", "partner", "allday", "birthday"].contains(PreviewMode.screen), let event = Planner.effectiveEvents(calendar.events, data: store.data).first(where: { $0.id == PreviewMode.screen }) {
                NavigationStack { EventDetailView(event: event, initial: store.record(for: event), rule: store.rule(for: event)) }
            } else { tabs }
        }
        .task {
            if PreviewMode.enabled {
                if !previewReady { PreviewMode.prepare(store: store, calendar: calendar); rebuildAgenda(); previewReady = true }
            }
            else {
                health.configureBackgroundUpdates { [weak health, weak store, weak calendar, weak agenda] in
                    guard let health, let store, let calendar, let agenda else { return }
                    await calendar.refresh(settings: store.data.settings, force: true)
                    agenda.rebuild(events: calendar.events, hasAccess: calendar.hasAccess, store: store, diagnostics: store.diagnostics)
                    await health.refresh(store: store, events: calendar.events, force: true)
                }
                if !store.isLoading, store.data.settings.healthEnabled == true { await health.resumeBackgroundUpdates() }
                requestRefresh()
                #if DEBUG && targetEnvironment(simulator)
                if ProcessInfo.processInfo.arguments.contains("--interaction-test") {
                    Task {
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        for _ in 0..<25 { NotificationCenter.default.post(name: .EKEventStoreChanged, object: nil) }
                    }
                }
                #endif
            }
        }
        .onReceive(refreshClock) { _ in if scene == .active { requestRefresh(); rebuildAgenda() } }
        .onOpenURL { url in
            if let link = WorkoutDeepLink.parse(url) { workoutLink = link; openPendingWorkout() }
        }
        .onChange(of: scene) { _, value in
            if value == .active { requestRefresh(force: true) }
            else { coachModel.pauseAndUnload() }
            if value == .background { store.saveBeforeBackground() }
        }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
            if ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical { coachModel.pauseAndUnload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            if ProcessInfo.processInfo.isLowPowerModeEnabled { coachModel.pauseAndUnload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in coachModel.pauseAndUnload() }
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { note in
            if let field = note.object as? UITextField {
                DispatchQueue.main.async { field.selectedTextRange = field.textRange(from: field.endOfDocument, to: field.endOfDocument) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UITextView.textDidBeginEditingNotification)) { note in
            if let field = note.object as? UITextView {
                DispatchQueue.main.async { field.selectedTextRange = field.textRange(from: field.endOfDocument, to: field.endOfDocument) }
            }
        }
        .onChange(of: store.isLoading) { _, loading in
            if !loading {
                if store.data.settings.healthEnabled == true {
                    Task { await health.resumeBackgroundUpdates() }
                }
                requestRefresh(); rebuildAgenda()
                openPendingWorkout()
            }
        }
        .onChange(of: store.isRestoring) { _, restoring in if !restoring { requestRefresh(); rebuildAgenda() } }
        .onChange(of: store.data.updatedAt) { _, _ in rebuildAgenda(); openPendingWorkout() }
        .onChange(of: store.data.settings) { old, new in
            if old.excludedCalendarIDs != new.excludedCalendarIDs || old.excludedCalendarTitles != new.excludedCalendarTitles || old.excludeHolidays != new.excludeHolidays { requestRefresh(force: true) }
            if old.healthEnabled != new.healthEnabled {
                if !store.isLoading {
                    Task {
                        if new.healthEnabled == true { await health.resumeBackgroundUpdates() }
                        else { await health.setBackgroundDelivery(enabled: false) }
                    }
                }
                requestRefresh()
            }
        }
        .onChange(of: calendar.events) { _, _ in rebuildAgenda() }
        .onChange(of: calendar.hasAccess) { _, _ in rebuildAgenda() }
        .onChange(of: agenda.revision) { _, _ in
            guard !PreviewMode.enabled, !store.isLoading, !store.isRestoring else { return }
            notificationGate.request {
                let started = ProcessInfo.processInfo.systemUptime
                await notifications.schedule(events: agenda.planned, data: store.data)
                store.diagnostics.record("Notifiche", seconds: ProcessInfo.processInfo.systemUptime - started)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged).debounce(for: .milliseconds(400), scheduler: RunLoop.main)) { _ in requestRefresh(force: true) }
        .sheet(item: $notifications.route) { route in
            NavigationStack {
                if let id = route.eventID, let event = agenda.planned.first(where: { $0.id == id }) {
                    EventDetailView(event: event, initial: notificationRecord(event, outcome: route.outcome), rule: store.rule(for: event), onSaved: { selectedTab = 0 })
                } else if route.destination == "checkin" {
                    DayCheckInView(day: Date(), initial: store.data.checkIns[PivotDate.key(Date())])
                } else if route.destination == "diary" { DiaryView() }
                else if route.destination == "payment", let id = route.clientID, let client = store.data.clients.first(where: { $0.id.uuidString == id }) { ClientDetailView(client: client) }
                else if route.destination == "payment" { IncomeView() }
                else if route.destination == "coach" { CoachView() }
                else if route.destination == "workout", let session = store.data.training?.sessions.first(where: { $0.id.uuidString == route.sessionID }) {
                    TrainingSessionView(session: session, tips: store.data.training?.tips ?? [:], event: nil)
                }
                else { Text("Questo evento è cambiato. Apri la giornata aggiornata.").padding() }
            }.presentationDragIndicator(.visible)
        }
        .alert("Pivot", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
    private var tabs: some View {
        TabView(selection: $selectedTab) {
            TodayView().tag(0).tabItem { Label("Oggi", systemImage: "calendar") }
            DiaryView().tag(1).tabItem { Label("Diario", systemImage: "book.closed.fill") }
            IncomeView().tag(2).tabItem { Label("Entrate", systemImage: "eurosign.circle.fill") }
            NavigationStack(path: $workoutPath) {
                TrainingView()
            }.tag(4).tabItem { Label("Palestra", systemImage: "dumbbell.fill") }
            SettingsView().tag(3).tabItem { Label("Impostazioni", systemImage: "gearshape.fill") }
        }
        .toolbarBackground(PivotTheme.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
    private func openPendingWorkout() {
        guard let link = workoutLink, !store.isLoading, !store.isRestoring, !store.locked else { return }
        selectedTab = 4
        if store.data.training?.sessions.contains(where: { $0.id == link.id }) == true {
            // Replace rather than append: repeated taps cannot stack copies.
            if workoutPath != [.session(link)] { workoutPath = [.session(link)] }
        }
        workoutLink = nil
    }
    private func rebuildAgenda() {
        agenda.rebuild(events: calendar.events, hasAccess: calendar.hasAccess, store: store, diagnostics: store.diagnostics)
    }
    private func requestRefresh(force: Bool = false) {
        guard !PreviewMode.enabled, !store.isLoading, !store.isRestoring else { return }
        if force { calendar.invalidateSnapshot() }
        refreshGate.request {
            let started = ProcessInfo.processInfo.systemUptime
            await calendar.refresh(settings: store.data.settings, force: force)
            store.diagnostics.record("Calendario", seconds: ProcessInfo.processInfo.systemUptime - started)
            rebuildAgenda()
            await health.refresh(store: store, events: calendar.events)
        }
    }
    private func notificationRecord(_ event: CalendarItem, outcome: Completion?) -> EventRecord {
        var record = store.record(for: event)
        if let outcome { record.status = outcome }
        return record
    }
}

struct PivotLaunchView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image("PivotMonogramV3").resizable().scaledToFit().frame(width: 128, height: 128)
            Text("Pivot").font(.system(size: 36, weight: .bold))
            Text("Trova il tuo ritmo.").font(.system(size: 17)).foregroundStyle(PivotTheme.muted)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black.ignoresSafeArea())
    }
}

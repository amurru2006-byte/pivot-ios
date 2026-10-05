import SwiftUI
import EventKit

@main
struct PivotApp: App {
    @StateObject private var store = PivotStore()
    @StateObject private var calendar = CalendarService()
    @StateObject private var notifications = NotificationService()
    @StateObject private var coachModel = LocalCoachService()
    @StateObject private var health = HealthService()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(calendar)
                .environmentObject(notifications)
                .environmentObject(coachModel)
                .environmentObject(health)
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
    @Environment(\.scenePhase) var scene
    @State private var selectedTab = PreviewMode.enabled ? PreviewMode.tab : 0
    @State private var previewReady = !PreviewMode.enabled
    @State private var refreshGate = RefreshGate()
    @State private var lessonToConfirm: CalendarItem?
    @State private var deferredLessonIDs: Set<String> = []
    @State private var question: EventDecision?
    @State private var offeredQuestion = false
    @State private var offeredWorkoutIDs: Set<String> = []
    private let refreshClock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
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
                if !previewReady { PreviewMode.prepare(store: store, calendar: calendar); previewReady = true }
            }
            else {
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
        .onReceive(refreshClock) { _ in if scene == .active { requestRefresh() } }
        .onChange(of: scene) { _, value in if value == .active { requestRefresh() } else { coachModel.stop() } }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
            if ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical { coachModel.stop() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            if ProcessInfo.processInfo.isLowPowerModeEnabled { coachModel.stop() }
        }
        .onChange(of: store.data.updatedAt) { _, _ in requestRefresh() }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged).debounce(for: .milliseconds(400), scheduler: RunLoop.main)) { _ in requestRefresh() }
        .sheet(item: $lessonToConfirm, onDismiss: { promptForLesson() }) { event in
            LessonLogisticsView(event: event, onDefer: { deferredLessonIDs.insert(event.id) })
        }
        .sheet(item: $question) { value in DecisionInboxView(initialID: value.id) }
        .sheet(item: Binding(get: { lessonToConfirm == nil && question == nil ? notifications.route : nil }, set: { notifications.route = $0 })) { route in
            NavigationStack {
                if let id = route.eventID, let event = Planner.plannedEvents(calendar.events, data: store.data).first(where: { $0.id == id }) {
                    EventDetailView(event: event, initial: notificationRecord(event, outcome: route.outcome), rule: store.rule(for: event), onSaved: { selectedTab = 0 })
                } else if route.destination == "checkin" {
                    DayCheckInView(day: Date(), initial: store.data.checkIns[PivotDate.key(Date())])
                } else if route.destination == "diary" { DiaryView() }
                else if route.destination == "coach" { CoachView() }
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
            NavigationStack { TrainingView() }.tag(4).tabItem { Label("Palestra", systemImage: "dumbbell.fill") }
            SettingsView().tag(3).tabItem { Label("Impostazioni", systemImage: "gearshape.fill") }
        }
        .toolbarBackground(PivotTheme.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
    private func requestRefresh() {
        guard !PreviewMode.enabled else { return }
        refreshGate.request { await refresh() }
    }
    private func refresh() async {
        guard !PreviewMode.enabled else { return }
        await calendar.refresh(settings: store.data.settings)
        if calendar.hasAccess && !store.locked && !store.isRestoring {
            let prompts = LessonPromptState.observed(calendar.events, data: store.data, now: Date())
            if prompts != store.data.lessonPrompts {
                store.change { $0.lessonPrompts = prompts }
            }
        }
        if calendar.hasAccess && !store.locked && !store.isRestoring {
            let decisions = EventContext.refreshed(events: calendar.events, data: store.data, now: Date())
            if decisions != store.data.decisions { store.change { $0.decisions = decisions } }
        }
        await health.refresh(store: store, events: calendar.events)
        promptForLesson()
        let pendingWorkouts = store.data.workoutReviews?.filter { !$0.resolved && !$0.dismissed } ?? []
        if scene == .active, !store.locked, !store.isRestoring,
           lessonToConfirm == nil, question == nil, notifications.route == nil,
           pendingWorkouts.contains(where: { !offeredWorkoutIDs.contains($0.id) }) {
            offeredWorkoutIDs.formUnion(pendingWorkouts.map(\.id))
            notifications.route = .init(eventID: nil, destination: "coach", outcome: nil)
        }
        if !offeredQuestion, lessonToConfirm == nil, notifications.route == nil, scene == .active,
           let value = store.data.decisions?.first(where: { !$0.deferred && $0.relation == .uncertain && $0.date < Date().addingTimeInterval(86400) }) {
            offeredQuestion = true; question = value
        }
        await notifications.schedule(events: Planner.plannedEvents(calendar.events, data: store.data), data: store.data)
    }
    private func promptForLesson() {
        guard !PreviewMode.enabled, scene == .active, !store.locked, !store.isRestoring, lessonToConfirm == nil, question == nil, notifications.route == nil else { return }
        lessonToConfirm = LessonLogistics.pending(events: calendar.events, data: store.data, now: Date()).first { !deferredLessonIDs.contains($0.id) }
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

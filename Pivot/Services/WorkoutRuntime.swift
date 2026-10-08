import ActivityKit
import Foundation
import UserNotifications
import UIKit

@MainActor
enum WorkoutRuntime {
    // LiveActivityIntent executes in the app process, including headless launches.
    // Both the UI and intents use the same disk owner; no second writer or App Group.
    static let store = PivotStore()
    static var focusedSet: [UUID: UUID] = [:]
    static var status = ""
    static var restGeneration: [UUID: Int] = [:]
    static func perform(sessionID: String, setID: String, action: String) async throws {
        for _ in 0..<100 {
            if !store.isLoading { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        guard !store.locked, !store.isLoading, !store.isRestoring,
              var session = store.data.training?.sessions.first(where: { $0.id.uuidString == sessionID }), session.end == nil else { throw TrainingError.invalidPlan }
        status = ""
        if ["pause", "reset", "next"].contains(action) {
            if action == "pause" { session.rest?.togglePause() }
            if action == "reset" { session.rest?.resetCountdown() }
            if action == "next" { finishRest(&session) }
        } else {
            guard let ei = session.exercises.firstIndex(where: { $0.sets.contains { $0.id.uuidString == setID } }),
                  let si = session.exercises[ei].sets.firstIndex(where: { $0.id.uuidString == setID }), !session.exercises[ei].sets[si].done else { return }
            let exercise = session.exercises[ei].exercise
            var set = session.exercises[ei].sets[si]
            switch action {
            case "kg+": set.kg = min(2000, (set.kg ?? 0) + 2.5)
            case "kg-": set.kg = max(0, (set.kg ?? 0) - 2.5)
            case "reps+": set.reps = min(1000, (set.reps ?? 0) + 1)
            case "reps-": set.reps = max(0, (set.reps ?? 0) - 1)
            case "seconds+": set.durationSeconds = min(86400, (set.durationSeconds ?? 0) + 1)
            case "seconds-": set.durationSeconds = max(0, (set.durationSeconds ?? 0) - 1)
            case "left+": set.leftSeconds = min(86400, (set.leftSeconds ?? 0) + 1)
            case "left-": set.leftSeconds = max(0, (set.leftSeconds ?? 0) - 1)
            case "right+": set.rightSeconds = min(86400, (set.rightSeconds ?? 0) + 1)
            case "right-": set.rightSeconds = max(0, (set.rightSeconds ?? 0) - 1)
            case "done":
                guard set.canComplete(exercise) else { status = "Inserisci i valori prima di confermare"; await update(session); return }
                // Without an explicit next-set start, elapsed time also includes
                // the next set. Do not misreport it as an actual rest duration.
                set.done = true; set.completedAt = Date()
                let seconds = set.restSeconds ?? exercise.restSeconds
                session.rest = seconds > 0 ? .init(exerciseID: exercise.id, setID: set.id, seconds: seconds) : nil
                focusedSet[session.id] = nil
            default: return
            }
            session.exercises[ei].sets[si] = set
            if ["kg+", "kg-"].contains(action) {
                let target = TrainingSetTemplate.workingLoad(session.exercises[ei].sets)
                if set.resolvedKind == .warmup {
                    // A manual warm-up edit sets the new ratio; do not overwrite
                    // that edit by immediately applying its previous ratio.
                    if let target, target > 0, let kg = set.kg, kg > 0 {
                        session.exercises[ei].sets[si].loadFraction = kg / target
                    } else { session.exercises[ei].sets[si].loadFraction = nil }
                } else if [.working, .superset].contains(set.resolvedKind) {
                    TrainingSetTemplate.rescaleWarmups(in: &session.exercises[ei].sets, workingLoad: target)
                }
            }
        }
        session.updatedAt = Date()
        guard store.saveTraining(session, tips: store.data.training?.tips ?? [:], event: nil) else { throw TrainingError.invalidPlan }
        guard await store.flushWorkoutChanges() else { throw TrainingError.invalidPlan }
        await scheduleRest(session)
        await update(session)
    }
    static func finishRest(_ session: inout TrainingSession) {
        guard let rest = session.rest else { return }
        if let ei = session.exercises.firstIndex(where: { $0.id == rest.exerciseID }), let si = session.exercises[ei].sets.firstIndex(where: { $0.id == rest.setID }) {
            session.exercises[ei].sets[si].actualRestSeconds = rest.elapsed(at: Date())
        }
        session.rest = nil
    }
    static func scheduleRest(_ session: TrainingSession) async {
        if let latest = store.data.training?.sessions.first(where: { $0.id == session.id }), latest.updatedAt > session.updatedAt { return }
        let generation = (restGeneration[session.id] ?? 0) + 1; restGeneration[session.id] = generation
        let center = UNUserNotificationCenter.current(), key = "workout-rest-" + session.id.uuidString
        center.removePendingNotificationRequests(withIdentifiers: [key])
        guard session.end == nil, let rest = session.rest, let deadline = rest.deadline, deadline > Date() else { return }
        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined, UIApplication.shared.applicationState == .active {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            settings = await center.notificationSettings()
        }
        guard restGeneration[session.id] == generation else { return }
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = "Recupero terminato"
        content.body = "Riprendi quando sei pronto · " + session.dayName
        content.sound = .default
        content.userInfo = ["destination": "workout", "sessionID": session.id.uuidString]
        try? await center.add(.init(identifier: key, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, deadline.timeIntervalSinceNow), repeats: false)))
    }
    static func update(_ session: TrainingSession, start: Bool = false) async {
        if let latest = store.data.training?.sessions.first(where: { $0.id == session.id }), latest.updatedAt > session.updatedAt { return }
        let activities = Activity<WorkoutAttributes>.activities.filter { $0.attributes.sessionID == session.id.uuidString }
        guard session.end == nil else {
            for activity in activities { await activity.end(nil, dismissalPolicy: .immediate) }
            await scheduleRest(session); return
        }
        let logs = session.exercises
        let candidates = logs.flatMap { log in log.sets.filter { !$0.done }.map { (log.exercise, $0) } }
        let fallback = logs.reversed().compactMap { log in log.sets.last.map { (log.exercise, $0) } }.first
        let current = candidates.first { $0.1.id == focusedSet[session.id] } ?? candidates.first ?? fallback
        guard let (exercise, set) = current else {
            for activity in activities { await activity.end(nil, dismissalPolicy: .immediate) }; return
        }
        let state = WorkoutAttributes.ContentState(exercise: exercise.name, setID: set.id.uuidString, number: set.number, kind: set.resolvedKind.label,
            kg: set.kg, reps: set.reps, seconds: set.durationSeconds, left: set.leftSeconds, right: set.rightSeconds,
            isometric: exercise.usesDuration, weighted: exercise.weightedHold == true, separateSides: exercise.separateSides == true,
            deadline: session.rest?.deadline, pausedSeconds: session.rest?.remainingWhenPaused,
            status: set.done ? "Serie completate · termina nell'app" : status.isEmpty ? "Compila, poi segna Fatta" : status, isDone: set.done)
        let content = ActivityContent(state: state, staleDate: nil)
        if activities.isEmpty && start {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { status = "Abilita Attività live nelle impostazioni di iOS"; return }
            do { _ = try Activity.request(attributes: WorkoutAttributes(sessionID: session.id.uuidString), content: content, pushType: nil); status = "" }
            catch { status = "Attività live non disponibile: " + error.localizedDescription }
        } else { for activity in activities { await activity.update(content) } }
    }
}

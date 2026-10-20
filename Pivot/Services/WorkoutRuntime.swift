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
            if action == "next" {
                focusedSet[session.id] = TrainingWorkoutContext.next(in: session, focusedSetID: focusedSet[session.id])?.set.id
                finishRest(&session)
            }
        } else {
            guard let ei = session.exercises.firstIndex(where: { $0.sets.contains { $0.id.uuidString == setID } }),
                  let si = session.exercises[ei].sets.firstIndex(where: { $0.id.uuidString == setID }),
                  session.exercises[ei].skipped != true, !session.exercises[ei].sets[si].isResolved else { return }
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
                let outcome = TrainingCompletion.toggle(in: &session, exerciseIndex: ei, setIndex: si)
                guard outcome != .invalid else { status = "Inserisci i valori prima di confermare"; await update(session); return }
                set = session.exercises[ei].sets[si]
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
        TrainingCompletion.finishRest(in: &session)
    }
    static func scheduleRest(_ session: TrainingSession, forceAlarm: Bool = false) async {
        guard !store.isRestoring, !store.isLoading,
              let latest = store.data.training?.sessions.first(where: { $0.id == session.id }), latest.updatedAt <= session.updatedAt else { return }
        let generation = (restGeneration[session.id] ?? 0) + 1; restGeneration[session.id] = generation
        let center = UNUserNotificationCenter.current(), key = "workout-rest-" + session.id.uuidString
        center.removePendingNotificationRequests(withIdentifiers: [key])
        if session.end != nil || session.rest == nil { center.removeDeliveredNotifications(withIdentifiers: [key]) }
        await WorkoutRestAlarmService.shared.synchronize(session: session, settings: store.data.settings.workoutRestAudio ?? .init(), force: forceAlarm)
        guard session.end == nil, let rest = session.rest, let deadline = rest.deadline, deadline > Date() else { return }
        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined, UIApplication.shared.applicationState == .active {
            _ = try? await center.requestAuthorization(options: [.alert])
            settings = await center.notificationSettings()
        }
        guard restGeneration[session.id] == generation else { return }
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = "Recupero terminato"
        content.body = "Riprendi quando sei pronto · " + session.dayName
        // Visual deep-link only. AlarmKit owns the only audible cue and the
        // system media interruption: no duplicate notification in headphones.
        content.sound = nil
        content.userInfo = ["destination": "workout", "sessionID": session.id.uuidString]
        try? await center.add(.init(identifier: key, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, deadline.timeIntervalSinceNow), repeats: false)))
    }
    static func update(_ session: TrainingSession, start: Bool = false) async {
        if start { status = "" }
        guard let latest = store.data.training?.sessions.first(where: { $0.id == session.id }), latest.updatedAt <= session.updatedAt else { return }
        let activities = Activity<WorkoutAttributes>.activities.filter { $0.attributes.sessionID == session.id.uuidString }
        guard session.end == nil else {
            for activity in activities { await activity.end(nil, dismissalPolicy: .immediate) }
            await scheduleRest(session); return
        }
        let next = TrainingWorkoutContext.next(in: session, focusedSetID: focusedSet[session.id])
        let origin = TrainingWorkoutContext.restOrigin(in: session)
        guard let current = next ?? origin ?? TrainingWorkoutContext.last(in: session) else {
            for activity in activities { await activity.end(nil, dismissalPolicy: .immediate) }; return
        }
        let exercise = current.exercise, set = current.set
        let state = WorkoutAttributes.ContentState(exercise: exercise.name, setID: set.id.uuidString, number: set.number, kind: set.resolvedKind.label,
            kg: set.kg, reps: set.reps, seconds: set.durationSeconds, left: set.leftSeconds, right: set.rightSeconds,
            isometric: exercise.usesDuration, weighted: exercise.weightedHold == true, separateSides: exercise.separateSides == true,
            deadline: session.rest?.deadline, pausedSeconds: session.rest?.remainingWhenPaused,
            status: next == nil ? "Serie registrate" : status, isDone: next == nil,
            targetSets: exercise.sets, targetReps: exercise.reps,
            workingNumber: current.workingNumber, restExercise: origin?.exercise.name)
        let content = ActivityContent(state: state, staleDate: nil)
        if activities.isEmpty && start {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { status = "Abilita Attività live nelle impostazioni di iOS"; return }
            do { _ = try Activity.request(attributes: WorkoutAttributes(sessionID: session.id.uuidString), content: content, pushType: nil); status = "" }
            catch { status = "Attività live non disponibile: " + error.localizedDescription }
        } else { for activity in activities { await activity.update(content) } }
    }
    static func stop(sessionID: UUID) async {
        await WorkoutRestAlarmService.shared.stop(sessionID: sessionID)
        focusedSet[sessionID] = nil
        restGeneration[sessionID] = (restGeneration[sessionID] ?? 0) + 1
        let key = "workout-rest-" + sessionID.uuidString
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [key])
        center.removeDeliveredNotifications(withIdentifiers: [key])
        for activity in Activity<WorkoutAttributes>.activities where activity.attributes.sessionID == sessionID.uuidString {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}

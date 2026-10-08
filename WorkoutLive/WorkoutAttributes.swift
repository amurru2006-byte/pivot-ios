import ActivityKit
import AppIntents
import Foundation

struct WorkoutAttributes: ActivityAttributes {
    var sessionID: String
    struct ContentState: Codable, Hashable {
        var exercise: String
        var setID: String
        var number: Int
        var kind: String
        var kg: Double?
        var reps: Int?
        var seconds: Int?
        var left: Int?
        var right: Int?
        var isometric: Bool
        var weighted: Bool
        var separateSides: Bool
        var deadline: Date?
        var pausedSeconds: Int?
        var status: String
        var isDone: Bool
        var targetSets: Int? = nil
        var targetReps: String? = nil
        var workingNumber: Int? = nil
    }
}

struct WorkoutActionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Aggiorna allenamento Pivot"
    static var openAppWhenRun: Bool = false
    @Parameter(title: "Allenamento") var sessionID: String
    @Parameter(title: "Serie") var setID: String
    @Parameter(title: "Azione") var action: String
    init() {}
    init(sessionID: String, setID: String, action: String) {
        self.sessionID = sessionID; self.setID = setID; self.action = action
    }
    func perform() async throws -> some IntentResult {
        #if !PIVOT_WIDGET
        try await WorkoutRuntime.perform(sessionID: sessionID, setID: setID, action: action)
        #endif
        return .result()
    }
}

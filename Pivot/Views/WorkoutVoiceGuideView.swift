import AVFoundation
import SwiftUI

struct WorkoutVoiceGuideView: View {
    private enum Phase { case ready, preparing, counting, paused, finished }

    @Environment(\.scenePhase) private var scenePhase
    @State private var phase = Phase.ready
    @State private var target: Int
    @State private var interval = 3
    @State private var announced = 0
    @State private var task: Task<Void, Never>?
    @State private var speaker = AVSpeechSynthesizer()

    let exercise: String
    let setNumber: Int

    init(exercise: String, setNumber: Int, suggestedReps: Int?) {
        self.exercise = exercise
        self.setNumber = setNumber
        _target = State(initialValue: min(60, max(1, suggestedReps ?? 10)))
    }

    var body: some View {
        Form {
            Section {
                Text("\(exercise) · Serie \(setNumber)").font(.headline)
                Stepper("Ripetizioni da scandire: \(target)", value: $target, in: 1...60)
                    .accessibilityIdentifier("workout-voice-target")
                    .disabled(phase != .ready && phase != .finished)
                Picker("Secondi tra i conteggi", selection: $interval) {
                    ForEach(2...8, id: \.self) { Text("\($0) s").tag($0) }
                }
                .disabled(phase != .ready && phase != .finished)
            } footer: {
                Text("La voce scandisce il ritmo. Segna le ripetizioni che hai eseguito nei campi della serie.")
            }
            Section {
                LabeledContent("Conteggio vocale", value: status)
                    .accessibilityIdentifier("workout-voice-status")
                switch phase {
                case .ready, .finished:
                    Button(phase == .ready ? "Avvia guida" : "Ricomincia") { start(resuming: false) }
                        .accessibilityIdentifier("workout-voice-start")
                case .preparing, .counting:
                    Button("Pausa") { pause() }.accessibilityIdentifier("workout-voice-pause")
                case .paused:
                    Button("Riprendi") { start(resuming: true) }
                        .accessibilityIdentifier("workout-voice-resume")
                }
                if phase != .ready {
                    Button("Azzera") { reset() }.accessibilityIdentifier("workout-voice-reset")
                }
            }
        }
        .navigationTitle("Guida vocale")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase) { _, phase in if phase != .active { pause() } }
        .onDisappear { reset() }
    }

    private var status: String {
        switch phase {
        case .ready: "Pronta"
        case .preparing: "Preparazione"
        case .counting: "\(announced) di \(target)"
        case .paused: "In pausa · \(announced) di \(target)"
        case .finished: "Conclusa · \(announced) di \(target)"
        }
    }

    @MainActor private func start(resuming: Bool) {
        guard scenePhase == .active, task == nil else { return }
        if !resuming { announced = 0 }
        let goal = target
        let seconds = interval
        phase = resuming ? .counting : .preparing
        speaker.usesApplicationAudioSession = false
        if !resuming { say("Preparati") }
        task = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(resuming ? seconds : 3))
                try Task.checkCancellation()
                phase = .counting
                while announced < goal {
                    announced += 1
                    say(String(announced))
                    if announced == goal { break }
                    try await Task.sleep(for: .seconds(seconds))
                    try Task.checkCancellation()
                }
                phase = .finished
                task = nil
            } catch is CancellationError {
                // Pause or reset already owns the state of this run.
            } catch {
                reset()
            }
        }
    }

    @MainActor private func say(_ text: String) {
        if speaker.isSpeaking { speaker.stopSpeaking(at: .immediate) }
        let cue = AVSpeechUtterance(string: text)
        cue.voice = AVSpeechSynthesisVoice(language: "it-IT")
        speaker.speak(cue)
    }

    @MainActor private func pause() {
        guard phase == .preparing || phase == .counting else {
            speaker.stopSpeaking(at: .immediate)
            return
        }
        stop()
        phase = .paused
    }

    @MainActor private func reset() {
        stop()
        announced = 0
        phase = .ready
    }

    @MainActor private func stop() {
        task?.cancel()
        task = nil
        speaker.stopSpeaking(at: .immediate)
    }
}

import Foundation
import Speech
import AVFoundation
import Combine

@MainActor
final class DictationService: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var transcript = ""
    @Published private(set) var message: String?
    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var timeout: Task<Void, Never>?
    private var installedTap = false
    private var starting = false
    private var generation = 0
    private var segmentGeneration = 0
    private var transcriptBuffer = SpeechTranscriptBuffer()
    private var contextualPhrases: [String] = []

    func start(contextualPhrases: [String] = []) async {
        guard !isListening, !starting else { return }
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--dictation-pause-test") {
            startInteractionFixture(); return
        }
        #endif
        starting = true; defer { starting = false }
        let permissionToken = generation
        let permission = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard permissionToken == generation else { return }
        guard permission == .authorized else {
            message = "Consenti il riconoscimento vocale nelle impostazioni di iOS, oppure usa il microfono della tastiera."
            return
        }
        let mic = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard permissionToken == generation else { return }
        guard mic else { message = "Consenti il microfono nelle impostazioni di iOS."; return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "it_IT")), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            message = "Dettatura locale italiana non disponibile. Puoi usare il microfono della tastiera di iPhone."
            return
        }
        do {
            stop()
            message = nil
            transcript = ""
            transcriptBuffer = SpeechTranscriptBuffer()
            self.contextualPhrases = Array(contextualPhrases.prefix(100))
            self.recognizer = recognizer
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true)
            isListening = true
            let recordingToken = generation
            try beginRecognitionSegment(recordingToken: recordingToken)
            timeout = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 900_000_000_000) } catch { return }
                guard !Task.isCancelled else { return }
                self?.message = "Dettatura terminata dopo 15 minuti. Il testo è conservato: puoi continuare premendo Detta."
                self?.stop()
            }
        } catch {
            stop()
            message = error.localizedDescription
        }
    }

    func stop() {
        generation += 1
        segmentGeneration += 1
        isListening = false
        timeout?.cancel(); timeout = nil
        stopCurrentSegment(cancelTask: true)
        recognizer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func beginRecognitionSegment(recordingToken: Int) throws {
        guard isListening, generation == recordingToken, let recognizer else { return }
        stopCurrentSegment(cancelTask: true)
        segmentGeneration += 1
        let segmentToken = segmentGeneration
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.contextualStrings = contextualPhrases
        if #available(iOS 16.0, *) { request.addsPunctuation = true }
        self.request = request
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "PivotVoice", code: 1, userInfo: [NSLocalizedDescriptionKey: "Microfono non disponibile."])
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        installedTap = true
        engine.prepare()
        try engine.start()
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.isListening, self.generation == recordingToken, self.segmentGeneration == segmentToken else { return }
                if let result {
                    let segment = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                    let segments = result.bestTranscription.segments
                    let first = segments.first?.timestamp
                    let end = segments.last.map { $0.timestamp + $0.duration }
                    let utteranceFinished = result.isFinal || (result.speechRecognitionMetadata?.speechDuration ?? 0) > 0
                    self.publishHypothesis(segment, start: first, end: end, utteranceFinished: utteranceFinished)
                    if result.isFinal {
                        self.transcriptBuffer.finishSegment()
                        do { try self.beginRecognitionSegment(recordingToken: recordingToken) }
                        catch { self.message = "La dettatura si è interrotta: \(error.localizedDescription)"; self.stop() }
                        return
                    }
                }
                if let error {
                    if self.transcript.isEmpty { self.message = "Dettatura interrotta. Riprova oppure usa la tastiera." }
                    else { self.message = "Dettatura fermata: \(error.localizedDescription)" }
                    self.stop()
                }
            }
        }
    }

    private func stopCurrentSegment(cancelTask: Bool) {
        engine.stop()
        if installedTap { engine.inputNode.removeTap(onBus: 0); installedTap = false }
        request?.endAudio()
        if cancelTask { task?.cancel() }
        task = nil
        request = nil
    }

    private func publishHypothesis(_ text: String, start: TimeInterval?, end: TimeInterval?, utteranceFinished: Bool) {
        transcript = transcriptBuffer.update(text, start: start, end: end, utteranceFinished: utteranceFinished)
    }

    #if DEBUG && targetEnvironment(simulator)
    private func startInteractionFixture() {
        stop(); message = nil; transcript = ""; transcriptBuffer = SpeechTranscriptBuffer()
        isListening = true
        publishHypothesis("Prima devo studiare.", start: 0, end: 2, utteranceFinished: true)
        timeout = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 3_000_000_000) } catch { return }
            guard let self, self.isListening, !Task.isCancelled else { return }
            self.publishHypothesis("Poi fare la", start: 0, end: 1, utteranceFinished: false)
            do { try await Task.sleep(nanoseconds: 500_000_000) } catch { return }
            guard self.isListening, !Task.isCancelled else { return }
            self.publishHypothesis("Poi fare la spesa.", start: 0, end: 2, utteranceFinished: true)
        }
    }
    #endif

}

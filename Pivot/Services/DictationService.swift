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
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var timeout: Task<Void, Never>?
    private var installedTap = false
    private var starting = false
    func start() async {
        guard !isListening, !starting else { return }
        starting = true; defer { starting = false }
        let permission = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard permission == .authorized else { message = "Consenti il riconoscimento vocale nelle impostazioni di iOS, oppure usa il microfono della tastiera."; return }
        let mic = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard mic else { message = "Consenti il microfono nelle impostazioni di iOS."; return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "it_IT")), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            message = "Dettatura locale italiana non disponibile. Puoi usare il microfono della tastiera di iPhone."; return
        }
        do {
            stop(); message = nil; transcript = ""
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = true
            self.request = request
            let input = engine.inputNode, format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0 && format.channelCount > 0 else { throw NSError(domain: "PivotVoice", code: 1, userInfo: [NSLocalizedDescriptionKey: "Microfono non disponibile."]) }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
            installedTap = true; engine.prepare(); try engine.start(); isListening = true
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self, self.isListening else { return }
                    if let result { self.transcript = result.bestTranscription.formattedString }
                    if error != nil || result?.isFinal == true {
                        if error != nil && self.transcript.isEmpty { self.message = "Dettatura interrotta. Riprova oppure usa la tastiera." }
                        self.stop()
                    }
                }
            }
            timeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                if !Task.isCancelled { self?.stop() }
            }
        } catch { stop(); message = error.localizedDescription }
    }
    func stop() {
        isListening = false; timeout?.cancel(); timeout = nil
        engine.stop()
        if installedTap { engine.inputNode.removeTap(onBus: 0); installedTap = false }
        request?.endAudio(); task?.cancel(); task = nil; request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

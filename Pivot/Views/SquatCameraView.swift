import AVFoundation
import SwiftUI
import UIKit

struct SquatCameraView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var camera: SquatCamera?
    @State private var attempt: UUID?
    @State private var count = 0
    @State private var tracking = SquatRepCounter.Tracking.reposition
    @State private var message: String?
    @State private var review: Int?

    let apply: (Int) -> Bool

    var body: some View {
        PivotScreen {
            Text("Posiziona l’iPhone in verticale e riprenditi di lato, con anca, ginocchio e caviglia visibili. Inizia in piedi.").font(.subheadline)
            Text("Una sola persona nell’inquadratura. Le immagini sono analizzate sul dispositivo e non vengono salvate.").font(.caption)
            if let camera {
                Preview(session: camera.session)
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .frame(maxHeight: 440)
                    .background(.black)
                    .accessibilityHidden(true)
                Text("\(count) ripetizioni rilevate").font(.title2.monospacedDigit())
                Text(trackingMessage).font(.subheadline)
                Button("Termina rilevazione") { stop(showReview: true) }.buttonStyle(PivotPrimaryButton())
            } else if let review {
                Stepper("Ripetizioni da riportare: \(review)", value: Binding(
                    get: { self.review ?? 0 }, set: { self.review = $0 }
                ), in: 0...999)
                Button("Riporta nella serie") {
                    if apply(review) { dismiss() }
                    else { message = "La serie è cambiata. Riaprila prima di aggiornare le ripetizioni." }
                }.buttonStyle(PivotPrimaryButton()).disabled(review == 0)
                Button("Nuova rilevazione") { attempt = UUID() }.buttonStyle(PivotSecondaryButton())
                    .disabled(attempt != nil)
            } else {
                Button("Avvia fotocamera") { attempt = UUID() }.buttonStyle(PivotPrimaryButton())
                    .disabled(attempt != nil)
            }
            if let message { Text(message).font(.caption).foregroundStyle(PivotTheme.amber) }
        }
        .navigationTitle("Conta squat")
        .task(id: attempt) {
            if let attempt { await run(attempt) }
        }
        .onDisappear { stop(showReview: false) }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                stop(showReview: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureSession.wasInterruptedNotification)) { notification in
            if let camera, (notification.object as? AVCaptureSession) === camera.session {
                stop(showReview: true)
                message = "Fotocamera interrotta."
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureSession.runtimeErrorNotification)) { notification in
            if let camera, (notification.object as? AVCaptureSession) === camera.session {
                stop(showReview: true)
                message = "Fotocamera non disponibile."
            }
        }
    }

    private var trackingMessage: String {
        switch tracking {
        case .reposition: "Inquadra la gamba di lato e torna in piedi."
        case .stand: "Resta in piedi per iniziare."
        case .ready: "Pronto a rilevare la discesa."
        case .rising: "Torna in piedi per completare il conteggio."
        }
    }

    @MainActor private func run(_ id: UUID) async {
        message = nil
        let allowed: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: allowed = true
        case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .video)
        default: allowed = false
        }
        guard !Task.isCancelled, attempt == id else { return }
        guard allowed, scenePhase == .active else {
            attempt = nil
            if !allowed { message = "Per usare il conteggio, consenti la fotocamera nelle Impostazioni di Pivot." }
            return
        }
        let capture = SquatCamera()
        count = 0
        tracking = .reposition
        review = nil
        camera = capture
        capture.start()
        defer {
            if camera === capture { stop(showReview: true) }
        }
        for await update in capture.updates {
            guard !Task.isCancelled, camera === capture else { break }
            switch update {
            case let .count(value, state):
                count = min(value, 999)
                tracking = state
            case .unavailable:
                message = "Fotocamera non disponibile."
                stop(showReview: false)
            }
        }
    }

    @MainActor private func stop(showReview: Bool) {
        // An initial permission prompt can temporarily make the scene inactive.
        guard let camera else {
            if !showReview { attempt = nil }
            return
        }
        camera.stop()
        self.camera = nil
        attempt = nil
        if showReview, count > 0 { review = count }
    }

    private struct Preview: UIViewRepresentable {
        let session: AVCaptureSession

        func makeUIView(context: Context) -> Surface {
            let view = Surface()
            view.preview.session = session
            view.preview.videoGravity = .resizeAspect
            return view
        }

        func updateUIView(_ view: Surface, context: Context) {}

        final class Surface: UIView {
            override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
            var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

            override func layoutSubviews() {
                super.layoutSubviews()
                if let connection = preview.connection, connection.isVideoRotationAngleSupported(90),
                   connection.videoRotationAngle != 90 {
                    connection.videoRotationAngle = 90
                }
            }
        }
    }
}

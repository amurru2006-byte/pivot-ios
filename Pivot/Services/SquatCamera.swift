import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import Vision

/// Camera configuration, Vision and the counter run on one serial queue.
/// Only the count and tracking state cross into the UI.
final class SquatCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    enum Update {
        case count(Int, SquatRepCounter.Tracking)
        case unavailable
    }

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "app.pivot.squat-camera")
    private let output = AVCaptureVideoDataOutput()
    private let request = VNDetectHumanBodyPoseRequest()
    private let continuation: AsyncStream<Update>.Continuation
    let updates: AsyncStream<Update>
    private var counter = SquatRepCounter()
    private var lastFrame: Double?
    private var side: Int?

    override init() {
        let stream = AsyncStream<Update>.makeStream(bufferingPolicy: .bufferingNewest(1))
        updates = stream.stream
        continuation = stream.continuation
        super.init()
    }

    func start() {
        queue.async { [self] in
            guard configure() else {
                continuation.yield(.unavailable)
                continuation.finish()
                return
            }
            session.startRunning()
            if !session.isRunning {
                continuation.yield(.unavailable)
                continuation.finish()
            }
        }
    }

    func stop() {
        queue.async { [self] in
            output.setSampleBufferDelegate(nil, queue: nil)
            if session.isRunning { session.stopRunning() }
            continuation.finish()
        }
    }

    private func configure() -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.vga640x480) { session.sessionPreset = .vga640x480 }
        guard session.canAddInput(input) else { return false }
        session.addInput(input)
        guard session.canAddOutput(output) else { return false }
        output.alwaysDiscardsLateVideoFrames = true
        session.addOutput(output)
        guard let connection = output.connection(with: .video),
              connection.isVideoRotationAngleSupported(90) else { return false }
        connection.videoRotationAngle = 90
        output.setSampleBufferDelegate(self, queue: queue)
        return true
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard time.isFinite,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        if let lastFrame, time >= lastFrame, time - lastFrame < 0.09 { return }
        if let lastFrame, time < lastFrame || time - lastFrame > 0.45 { observeLost(at: time) }
        lastFrame = time
        let aspect = Double(CVPixelBufferGetWidth(buffer)) / Double(CVPixelBufferGetHeight(buffer))
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up)
        do {
            try handler.perform([request])
            let poses = request.results ?? []
            if poses.count == 1, let pose = poses.first,
               let points = try? pose.recognizedPoints(.all) {
                observe(points, aspect: aspect, time: time)
            } else {
                observeLost(at: time)
            }
        } catch {
            observeLost(at: time)
        }
        continuation.yield(.count(counter.repetitions, counter.tracking))
    }

    private func observe(_ points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint],
                         aspect: Double, time: Double) {
        let legs: [[VNHumanBodyPoseObservation.JointName]] = [
            [.leftHip, .leftKnee, .leftAnkle], [.rightHip, .rightKnee, .rightAnkle]
        ]
        let candidates = legs.map { leg -> (Double, Float)? in
            let joints = leg.compactMap { points[$0] }
            guard joints.count == 3, joints.allSatisfy({
                $0.confidence >= 0.45 && (0.03...0.97).contains($0.location.x)
                    && (0.03...0.97).contains($0.location.y)
            }) else { return nil }
            let hip = joints[0].location, knee = joints[1].location, ankle = joints[2].location
            let ax = Double(hip.x - knee.x) * aspect, ay = Double(hip.y - knee.y)
            let bx = Double(ankle.x - knee.x) * aspect, by = Double(ankle.y - knee.y)
            let scale = hypot(ax, ay) * hypot(bx, by)
            guard scale > 0.003 else { return nil }
            let cosine = max(-1, min(1, (ax * bx + ay * by) / scale))
            return (acos(cosine) * 180 / .pi, min(joints[0].confidence, min(joints[1].confidence, joints[2].confidence)))
        }
        if side == nil {
            let leftConfidence = candidates[0]?.1 ?? 0
            let rightConfidence = candidates[1]?.1 ?? 0
            side = leftConfidence >= rightConfidence ? 0 : 1
        }
        guard let side, let candidate = candidates[side] else { observeLost(at: time); return }
        counter.observe(kneeAngle: candidate.0, at: time)
    }

    private func observeLost(at time: Double) {
        side = nil
        counter.observe(kneeAngle: nil, at: time)
    }
}

import Foundation

/// A finite, generated PCM cue: no microphone, downloaded sound, or silent
/// playback loop. Its length is not a guarantee that a system alarm won't
/// repeat it; that behavior must be checked separately on physical hardware.
enum WorkoutRestChime {
    static let sampleRate = 44_100
    static let durationSeconds = 2

    static func waveData(volume: Double) -> Data? {
        guard volume.isFinite, (0...1).contains(volume) else { return nil }
        let frames = sampleRate * durationSeconds
        let payloadBytes = frames * 2
        var data = Data(capacity: 44 + payloadBytes)
        func ascii(_ value: String) { data.append(contentsOf: value.utf8) }
        func u16(_ value: UInt16) {
            data.append(UInt8(truncatingIfNeeded: value))
            data.append(UInt8(truncatingIfNeeded: value >> 8))
        }
        func u32(_ value: UInt32) {
            for shift in stride(from: 0, to: 32, by: 8) { data.append(UInt8(truncatingIfNeeded: value >> shift)) }
        }
        ascii("RIFF"); u32(UInt32(36 + payloadBytes)); ascii("WAVE")
        ascii("fmt "); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        ascii("data"); u32(UInt32(payloadBytes))
        for frame in 0..<frames {
            let time = Double(frame) / Double(sampleRate)
            var signal = 0.0
            for onset in [0.0, 0.65, 1.30] {
                let t = time - onset
                if (0..<0.4).contains(t) {
                    let attack = min(1, t / 0.008)
                    let release = min(1, (0.4 - t) / 0.03)
                    let tone = (sin(2 * .pi * 880 * t) + 0.3 * sin(2 * .pi * 1320 * t)) / 1.3
                    signal += tone * attack * release * exp(-5 * t)
                }
            }
            // Leave headroom even at maximum cue gain. Never change the
            // device's output volume to make this sound louder.
            let sample = Int16((max(-1, min(1, signal)) * volume * 0.7 * Double(Int16.max)).rounded())
            u16(UInt16(bitPattern: sample))
        }
        return data
    }
}

import AVFoundation
import Foundation

/// Phase 0: fixed-sample-rate PCM helpers and sine generation.
public enum AudioFormatDefaults {
    public static let sampleRate: Double = 44_100
    public static let channelCount: AVAudioChannelCount = 1
}

public struct PCMBufferFactory: Sendable {
    public init() {}

    public func makeMonoFloatFormat(sampleRate: Double = AudioFormatDefaults.sampleRate) -> AVAudioFormat {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: AudioFormatDefaults.channelCount,
            interleaved: false
        ) else {
            preconditionFailure("Failed to create mono float AVAudioFormat")
        }
        return format
    }

    /// Creates a mono float32 buffer filled by `writer` (sample index → sample value in -1...1).
    public func makeBuffer(
        frameCount: AVAudioFrameCount,
        sampleRate: Double = AudioFormatDefaults.sampleRate,
        writer: (_ frame: Int) -> Float
    ) -> AVAudioPCMBuffer {
        let format = makeMonoFloatFormat(sampleRate: sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            preconditionFailure("Failed to allocate AVAudioPCMBuffer")
        }
        buffer.frameLength = frameCount
        guard let channel = buffer.floatChannelData?[0] else {
            preconditionFailure("Missing float channel data")
        }
        for frame in 0..<Int(frameCount) {
            channel[frame] = writer(frame)
        }
        return buffer
    }
}

public struct SineWaveGenerator: Sendable {
    public var frequencyHz: Double
    public var amplitude: Float
    public var durationSeconds: Double
    public var sampleRate: Double

    public init(
        frequencyHz: Double = 440,
        amplitude: Float = 0.25,
        durationSeconds: Double = 1.0,
        sampleRate: Double = AudioFormatDefaults.sampleRate
    ) {
        self.frequencyHz = frequencyHz
        self.amplitude = amplitude
        self.durationSeconds = durationSeconds
        self.sampleRate = sampleRate
    }

    public func generate() -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount((durationSeconds * sampleRate).rounded(.down))
        let twoPiF = 2.0 * Double.pi * frequencyHz
        return PCMBufferFactory().makeBuffer(frameCount: frameCount, sampleRate: sampleRate) { frame in
            let t = Double(frame) / sampleRate
            return amplitude * Float(sin(twoPiF * t))
        }
    }
}

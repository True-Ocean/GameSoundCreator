import AVFoundation
import Foundation

public enum AudioPlayerError: Error, LocalizedError, Sendable {
    case engineStartFailed(String)
    case emptyBuffer

    public var errorDescription: String? {
        switch self {
        case .engineStartFailed(let message):
            return "オーディオエンジンの起動に失敗: \(message)"
        case .emptyBuffer:
            return "再生するバッファが空です"
        }
    }
}

/// One-shot or looping playback via AVAudioEngine + player node.
///
/// Looping is done by chaining buffer schedules (not `.loops`), so `setLooping`
/// can flip mid-playback without stopping or seeking the audio.
@MainActor
public final class BufferAudioPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var connectedFormat: AVAudioFormat?
    private var isAttached = false
    private var currentBuffer: AVAudioPCMBuffer?
    private var isLooping = false
    /// Invalidates in-flight completion handlers after `stop()` / new `play()`.
    private var playGeneration = 0

    public init() {}

    public func play(_ buffer: AVAudioPCMBuffer, loop: Bool = false) throws {
        guard buffer.frameLength > 0 else { throw AudioPlayerError.emptyBuffer }
        playGeneration += 1
        let generation = playGeneration
        currentBuffer = buffer
        isLooping = loop
        try prepareEngine(for: buffer)
        scheduleSegment(generation: generation)
        player.play()
    }

    /// Change looping without stopping or restarting playback.
    public func setLooping(_ loop: Bool) {
        isLooping = loop
    }

    public func stop() {
        playGeneration += 1
        player.stop()
        currentBuffer = nil
        isLooping = false
        if engine.isRunning {
            engine.stop()
        }
    }

    private func prepareEngine(for buffer: AVAudioPCMBuffer) throws {
        if !isAttached {
            engine.attach(player)
            isAttached = true
        }

        if connectedFormat != buffer.format {
            if connectedFormat != nil {
                engine.disconnectNodeOutput(player)
            }
            engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
            connectedFormat = buffer.format
        }

        if engine.isRunning {
            player.stop()
        } else {
            do {
                try engine.start()
            } catch {
                throw AudioPlayerError.engineStartFailed(error.localizedDescription)
            }
        }
    }

    private func scheduleSegment(generation: Int) {
        guard generation == playGeneration, let buffer = currentBuffer else { return }
        player.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
            Task { @MainActor in
                self?.handleSegmentEnd(generation: generation)
            }
        }
    }

    private func handleSegmentEnd(generation: Int) {
        guard generation == playGeneration else { return }
        guard isLooping, currentBuffer != nil else { return }
        scheduleSegment(generation: generation)
        if !player.isPlaying {
            player.play()
        }
    }
}

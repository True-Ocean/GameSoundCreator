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
@MainActor
public final class BufferAudioPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var connectedFormat: AVAudioFormat?
    private var isAttached = false

    public init() {}

    public func play(_ buffer: AVAudioPCMBuffer, loop: Bool = false) throws {
        guard buffer.frameLength > 0 else { throw AudioPlayerError.emptyBuffer }

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

        let options: AVAudioPlayerNodeBufferOptions = loop ? [.loops] : []
        player.scheduleBuffer(buffer, at: nil, options: options, completionHandler: nil)
        player.play()
    }

    public func stop() {
        player.stop()
        if engine.isRunning {
            engine.stop()
        }
    }
}

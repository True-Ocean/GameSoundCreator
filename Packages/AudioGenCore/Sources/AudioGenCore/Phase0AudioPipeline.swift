import AVFoundation
import Foundation

/// Phase 0 facade: generate sine → play and/or export.
@MainActor
public final class Phase0AudioPipeline {
    private let player = BufferAudioPlayer()
    private let exporter = WAVExporter()

    public private(set) var lastBuffer: AVAudioPCMBuffer?
    public private(set) var lastExportURL: URL?

    public init() {}

    @discardableResult
    public func generateSine(
        frequencyHz: Double = 440,
        durationSeconds: Double = 1.0
    ) -> AVAudioPCMBuffer {
        let buffer = SineWaveGenerator(
            frequencyHz: frequencyHz,
            durationSeconds: durationSeconds
        ).generate()
        lastBuffer = buffer
        return buffer
    }

    public func playLast() throws {
        guard let buffer = lastBuffer else {
            throw AudioPlayerError.emptyBuffer
        }
        try activatePlaybackSession()
        try player.play(buffer)
    }

    public func generateAndPlay(
        frequencyHz: Double = 440,
        durationSeconds: Double = 1.0
    ) throws -> AVAudioPCMBuffer {
        let buffer = generateSine(frequencyHz: frequencyHz, durationSeconds: durationSeconds)
        try activatePlaybackSession()
        try player.play(buffer)
        return buffer
    }

    @discardableResult
    public func exportLastToDocuments(fileName: String = "phase0_sine_440hz.wav") throws -> URL {
        guard let buffer = lastBuffer else {
            throw AudioPlayerError.emptyBuffer
        }
        let url = try WAVExporter.documentsDirectory().appendingPathComponent(fileName)
        let written = try exporter.export(buffer: buffer, to: url)
        lastExportURL = written
        return written
    }

    public func stop() {
        player.stop()
    }

    private func activatePlaybackSession() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)
        #endif
    }
}

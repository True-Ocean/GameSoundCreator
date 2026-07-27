import AVFoundation
import Foundation

/// High-level Phase 1 facade for generate / play / export.
@MainActor
public final class SFXStudioController {
    private let engine = SFXEngine()
    private let player = BufferAudioPlayer()
    private let exporter = WAVExporter()

    public private(set) var lastRecipe: SFXRecipe?
    public private(set) var lastBuffer: AVAudioPCMBuffer?
    public private(set) var lastExportURL: URL?

    public init() {}

    @discardableResult
    public func generate(_ recipe: SFXRecipe) -> AVAudioPCMBuffer {
        let buffer = engine.generate(recipe)
        lastRecipe = recipe
        lastBuffer = buffer
        return buffer
    }

    public func play(_ recipe: SFXRecipe) throws {
        let buffer = generate(recipe)
        try activatePlaybackSession()
        try player.play(buffer)
    }

    public func playLast() throws {
        guard let buffer = lastBuffer else {
            throw AudioPlayerError.emptyBuffer
        }
        try activatePlaybackSession()
        try player.play(buffer)
    }

    @discardableResult
    public func exportLastToDocuments() throws -> URL {
        guard let recipe = lastRecipe, let buffer = lastBuffer else {
            throw AudioPlayerError.emptyBuffer
        }
        let url = try WAVExporter.documentsDirectory().appendingPathComponent(recipe.exportFileName)
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

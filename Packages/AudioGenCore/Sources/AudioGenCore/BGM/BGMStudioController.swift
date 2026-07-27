import AVFoundation
import Foundation

@MainActor
public final class BGMStudioController {
    private let engine = BGMEngine()
    private let player = BufferAudioPlayer()
    private let exporter = WAVExporter()

    public private(set) var lastRecipe: BGMRecipe?
    public private(set) var lastBuffer: AVAudioPCMBuffer?
    public private(set) var lastExportURL: URL?
    public private(set) var lastGenerationSeconds: Double = 0

    public init() {}

    @discardableResult
    public func generate(_ recipe: BGMRecipe) -> AVAudioPCMBuffer {
        let started = Date()
        let buffer = engine.generate(recipe)
        lastGenerationSeconds = Date().timeIntervalSince(started)
        lastRecipe = recipe
        lastBuffer = buffer
        return buffer
    }

    public func play(_ recipe: BGMRecipe, loop: Bool = true) throws {
        let buffer = generate(recipe)
        try activatePlaybackSession()
        try player.play(buffer, loop: loop)
    }

    public func playLast(loop: Bool = true) throws {
        guard let buffer = lastBuffer else {
            throw AudioPlayerError.emptyBuffer
        }
        try activatePlaybackSession()
        try player.play(buffer, loop: loop)
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

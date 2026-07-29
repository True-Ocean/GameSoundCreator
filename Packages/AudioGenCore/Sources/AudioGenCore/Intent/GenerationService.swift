import AVFoundation
import Foundation

/// Generates audio from Intent and plays/exports via existing engines.
/// Use `shared` so only one playback engine exists across screens.
@MainActor
public final class GenerationService {
    public static let shared = GenerationService()

    private let mapper = IntentMapper()
    private let sfxEngine = SFXEngine()
    private let bgmEngine = BGMEngine()
    private let player = BufferAudioPlayer()
    private let exporter = WAVExporter()

    public private(set) var lastIntent: SoundIntent?
    public private(set) var lastMapped: MappedRecipe?
    public private(set) var lastBuffer: AVAudioPCMBuffer?
    public private(set) var lastExportURL: URL?
    public private(set) var lastGenerationSeconds: Double = 0

    public init() {}

    @discardableResult
    public func generate(_ intent: SoundIntent) throws -> (MappedRecipe, AVAudioPCMBuffer) {
        let mapped = try mapper.map(intent)
        let buffer = generate(mapped: mapped, intent: intent)
        return (mapped, buffer)
    }

    @discardableResult
    public func generate(mapped: MappedRecipe, intent: SoundIntent? = nil) -> AVAudioPCMBuffer {
        let started = Date()
        let buffer: AVAudioPCMBuffer
        switch mapped {
        case .sfx(let recipe):
            buffer = sfxEngine.generate(recipe)
        case .bgm(let recipe):
            buffer = bgmEngine.generate(recipe)
        }
        lastGenerationSeconds = Date().timeIntervalSince(started)
        if let intent { lastIntent = intent }
        lastMapped = mapped
        lastBuffer = buffer
        return buffer
    }

    public func play(_ intent: SoundIntent, loop: Bool) throws {
        let (_, buffer) = try generate(intent)
        try activatePlaybackSession()
        try player.play(buffer, loop: loop)
    }

    public func play(mapped: MappedRecipe, intent: SoundIntent? = nil, loop: Bool) throws {
        let buffer = generate(mapped: mapped, intent: intent)
        try activatePlaybackSession()
        try player.play(buffer, loop: loop)
    }

    public func playLast(loop: Bool) throws {
        guard let buffer = lastBuffer else { throw AudioPlayerError.emptyBuffer }
        try activatePlaybackSession()
        try player.play(buffer, loop: loop)
    }

    public func stop() {
        player.stop()
    }

    /// Initializes engines and audio session so the first studio open is snappy.
    /// Synthesis probe runs off the main actor; safe during launch UI.
    public func warmup() async {
        await Self.warmupEnginesInBackground()
        await Task.yield()
        try? activatePlaybackSession()
        stop()
        lastBuffer = nil
        lastMapped = nil
        lastIntent = nil
        lastExportURL = nil
    }

    /// Probe synthesis fully off the main actor (does not touch `shared` state).
    nonisolated private static func warmupEnginesInBackground() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let recipe = SFXRecipe.make(category: .uiTap, seed: 1, durationMs: 80)
                _ = SFXEngine().generate(recipe)
                continuation.resume()
            }
        }
    }

    /// Maps on the caller (main actor), synthesizes off the main actor.
    public func generateAsync(_ intent: SoundIntent) async throws -> (MappedRecipe, AVAudioPCMBuffer) {
        let started = Date()
        let mapped = try mapper.map(intent)
        let buffer = await synthesizeAsync(mapped)
        lastGenerationSeconds = Date().timeIntervalSince(started)
        lastIntent = intent
        lastMapped = mapped
        lastBuffer = buffer
        return (mapped, buffer)
    }

    /// Synthesizes a resolved recipe off the main actor, then stores it for play/export.
    public func generateMappedAsync(_ mapped: MappedRecipe, intent: SoundIntent? = nil) async -> AVAudioPCMBuffer {
        let started = Date()
        let buffer = await synthesizeAsync(mapped)
        lastGenerationSeconds = Date().timeIntervalSince(started)
        if let intent { lastIntent = intent }
        lastMapped = mapped
        lastBuffer = buffer
        return buffer
    }

    private func synthesizeAsync(_ mapped: MappedRecipe) async -> AVAudioPCMBuffer {
        // AVAudioPCMBuffer is not Sendable; hop via a global queue + continuation.
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let buffer: AVAudioPCMBuffer
                switch mapped {
                case .sfx(let recipe):
                    buffer = SFXEngine().generate(recipe)
                case .bgm(let recipe):
                    buffer = BGMEngine().generate(recipe)
                }
                continuation.resume(returning: buffer)
            }
        }
    }

    @discardableResult
    public func exportLastToDocuments() throws -> URL {
        guard let mapped = lastMapped, let buffer = lastBuffer else {
            throw AudioPlayerError.emptyBuffer
        }
        let url = try WAVExporter.documentsDirectory().appendingPathComponent(mapped.exportFileName)
        let written = try exporter.export(buffer: buffer, to: url)
        lastExportURL = written
        return written
    }

    public func withNewSeed(_ intent: SoundIntent) -> SoundIntent {
        var next = intent
        next.seed = UInt64.random(in: 1...999_999)
        return next
    }

    private func activatePlaybackSession() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)
        #endif
    }
}

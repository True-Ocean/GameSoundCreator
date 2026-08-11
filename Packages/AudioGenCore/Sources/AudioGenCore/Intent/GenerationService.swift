import AVFoundation
import Foundation

public enum PlaybackStopReason: String, Sendable {
    case interruption
    case outputDeviceDisconnected
}

public enum AudioPlaybackNotification {
    /// Posted on the main actor when system audio conditions stop playback.
    public static let stopped = Notification.Name("AudioGenCore.playbackStopped")
    public static let reasonKey = "reason"
}

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
    /// Monotonically increasing request token. A completed background synthesis may
    /// only publish its result when it is still the newest request.
    private var latestGenerationRequest = 0

    #if os(iOS)
    private var interruptionMonitorTask: Task<Void, Never>?
    private var routeChangeMonitorTask: Task<Void, Never>?
    #endif

    public init() {
        #if os(iOS)
        interruptionMonitorTask = Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(
                named: AVAudioSession.interruptionNotification
            ) {
                guard let self, !Task.isCancelled else { break }
                self.handleAudioInterruption(notification)
            }
        }
        routeChangeMonitorTask = Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(
                named: AVAudioSession.routeChangeNotification
            ) {
                guard let self, !Task.isCancelled else { break }
                self.handleAudioRouteChange(notification)
            }
        }
        #endif
    }

    deinit {
        #if os(iOS)
        interruptionMonitorTask?.cancel()
        routeChangeMonitorTask?.cancel()
        #endif
    }

    /// Resolves an intent without synthesizing audio. Callers that need to adjust a
    /// mapped recipe can therefore do so before paying for a single synthesis pass.
    public func map(_ intent: SoundIntent) throws -> MappedRecipe {
        try mapper.map(intent)
    }

    @discardableResult
    public func generate(_ intent: SoundIntent) throws -> (MappedRecipe, AVAudioPCMBuffer) {
        let mapped = try map(intent)
        let buffer = generate(mapped: mapped, intent: intent)
        return (mapped, buffer)
    }

    @discardableResult
    public func generate(mapped: MappedRecipe, intent: SoundIntent? = nil) -> AVAudioPCMBuffer {
        let request = beginGenerationRequest()
        let started = Date()
        let buffer: AVAudioPCMBuffer
        switch mapped {
        case .sfx(let recipe):
            buffer = sfxEngine.generate(recipe)
        case .bgm(let recipe):
            buffer = bgmEngine.generate(recipe)
        }
        publish(buffer, mapped: mapped, intent: intent, started: started, request: request)
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

    /// Toggle loop without stopping or restarting the current buffer.
    public func setLooping(_ loop: Bool) {
        player.setLooping(loop)
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
        let request = beginGenerationRequest()
        let mapped = try map(intent)
        let buffer = await synthesizeAsync(mapped)
        try Task.checkCancellation()
        guard request == latestGenerationRequest else { throw CancellationError() }
        publish(buffer, mapped: mapped, intent: intent, started: started, request: request)
        return (mapped, buffer)
    }

    /// Synthesizes a resolved recipe off the main actor, then stores it for play/export.
    public func generateMappedAsync(_ mapped: MappedRecipe, intent: SoundIntent? = nil) async throws -> AVAudioPCMBuffer {
        let started = Date()
        let request = beginGenerationRequest()
        let buffer = await synthesizeAsync(mapped)
        try Task.checkCancellation()
        guard request == latestGenerationRequest else { throw CancellationError() }
        publish(buffer, mapped: mapped, intent: intent, started: started, request: request)
        return buffer
    }

    private func beginGenerationRequest() -> Int {
        latestGenerationRequest &+= 1
        return latestGenerationRequest
    }

    private func publish(
        _ buffer: AVAudioPCMBuffer,
        mapped: MappedRecipe,
        intent: SoundIntent?,
        started: Date,
        request: Int
    ) {
        // Synchronous generation cannot be superseded while this main-actor method
        // is running, but keep the guard so all generation paths have one policy.
        guard request == latestGenerationRequest else { return }
        lastGenerationSeconds = Date().timeIntervalSince(started)
        if let intent { lastIntent = intent }
        lastMapped = mapped
        lastBuffer = buffer
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
        let documents = try WAVExporter.documentsDirectory()
        let requestedURL = documents.appendingPathComponent(mapped.exportFileName)
        let url: URL
        if FileManager.default.fileExists(atPath: requestedURL.path) {
            let stem = requestedURL.deletingPathExtension().lastPathComponent
            url = documents.appendingPathComponent("\(stem)_\(UUID().uuidString.prefix(8)).wav")
        } else {
            url = requestedURL
        }
        let written = try exporter.export(buffer: buffer, to: url)
        lastExportURL = written
        return written
    }

    public func withNewSeed(_ intent: SoundIntent) -> SoundIntent {
        var next = intent
        next.seed = UInt64.random(in: 1...999_999)
        return next
    }

    /// Keeps the studio UI settings intact while selecting a BGM seed whose
    /// harmony, motif, and accompaniment profile is furthest from the current one.
    public func withDistinctBGMSeed(_ intent: SoundIntent, avoiding current: BGMRecipe?) -> SoundIntent {
        guard intent.soundType == .bgm, let current else {
            return withNewSeed(intent)
        }

        var candidates = Set<UInt64>()
        while candidates.count < 12 {
            let candidate = UInt64.random(in: 1...999_999)
            if candidate != current.params.seed {
                candidates.insert(candidate)
            }
        }

        var next = intent
        next.seed = bgmEngine.distinctSeed(from: Array(candidates), comparedTo: current)
            ?? UInt64.random(in: 1...999_999)
        return next
    }

    /// Keeps the studio controls intact while choosing a natural SFX profile that is
    /// structurally distinct from the one currently being previewed.
    public func withDistinctSFXSeed(_ intent: SoundIntent, avoiding current: SFXRecipe?) -> SoundIntent {
        guard intent.soundType == .sfx, let current else {
            return withNewSeed(intent)
        }

        var candidates = Set<UInt64>()
        while candidates.count < 12 {
            let candidate = UInt64.random(in: 1...999_999)
            if candidate != current.params.seed {
                candidates.insert(candidate)
            }
        }

        guard let seed = sfxEngine.distinctSeed(from: Array(candidates), comparedTo: current) else {
            return withNewSeed(intent)
        }
        var next = intent
        next.seed = seed
        return next
    }

    private func activatePlaybackSession() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)
        #endif
    }

    #if os(iOS)
    private func handleAudioInterruption(_ notification: Notification) {
        guard let rawValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: rawValue) == .began else {
            return
        }
        stopForSystemReason(.interruption)
    }

    private func handleAudioRouteChange(_ notification: Notification) {
        guard let rawValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: rawValue) == .oldDeviceUnavailable else {
            return
        }
        stopForSystemReason(.outputDeviceDisconnected)
    }

    private func stopForSystemReason(_ reason: PlaybackStopReason) {
        player.stop()
        NotificationCenter.default.post(
            name: AudioPlaybackNotification.stopped,
            object: self,
            userInfo: [AudioPlaybackNotification.reasonKey: reason.rawValue]
        )
    }
    #endif
}

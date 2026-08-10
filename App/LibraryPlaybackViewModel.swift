import AudioGenCore
import Foundation
import Observation

/// Owns playback work initiated from the saved-sound library.
@Observable
@MainActor
final class LibraryPlaybackViewModel {
    private let service: GenerationService
    let operationState = StudioOperationState()
    private var playbackTask: Task<Void, Never>?

    private(set) var playingID: UUID?
    /// Tracks the entry while its audio is still being generated. `playingID` is
    /// set only once playback actually starts.
    private var generatingID: UUID?
    private var playbackRequestID: UUID?

    var isBusy: Bool { operationState.isBusy }

    init(service: GenerationService? = nil) {
        self.service = service ?? GenerationService.shared
    }

    func isPlaying(_ entry: LibraryEntry) -> Bool {
        playingID == entry.id
    }

    func toggle(
        _ entry: LibraryEntry,
        onError: @escaping @MainActor (Error) -> Void
    ) {
        guard playingID != entry.id else {
            stop()
            return
        }

        playbackTask?.cancel()
        let requestID = UUID()
        playbackRequestID = requestID
        generatingID = entry.id
        playbackTask = Task { [weak self] in
            guard let self else { return }
            let operationID = operationState.begin(kind: .playback)
            defer {
                operationState.end(operationID)
                if playbackRequestID == requestID {
                    playbackTask = nil
                    playbackRequestID = nil
                    generatingID = nil
                }
            }

            do {
                _ = try await service.generateAsync(entry.intent)
                try Task.checkCancellation()
                guard playbackRequestID == requestID else { throw CancellationError() }
                try service.playLast(loop: entry.intent.soundType == .bgm)
                playingID = entry.id
            } catch is CancellationError {
                // A newer library playback request superseded this one.
            } catch {
                guard playbackRequestID == requestID else { return }
                onError(error)
            }
        }
    }

    func stop() {
        playbackTask?.cancel()
        playbackTask = nil
        service.stop()
        playingID = nil
        generatingID = nil
        playbackRequestID = nil
        operationState.cancelPlayback()
    }

    /// Cancels only the playback work associated with the entry being removed.
    /// This covers both already-playing audio and audio still being generated.
    func stopIfActive(_ entry: LibraryEntry) {
        guard generatingID == entry.id || playingID == entry.id else { return }
        stop()
    }

    func handleSystemStop() {
        playbackTask?.cancel()
        playbackTask = nil
        playingID = nil
        generatingID = nil
        playbackRequestID = nil
        operationState.cancelPlayback()
    }
}

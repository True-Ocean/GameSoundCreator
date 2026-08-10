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
        playbackTask = Task { [weak self] in
            guard let self else { return }
            let operationID = operationState.begin(kind: .playback)
            defer { operationState.end(operationID) }

            do {
                _ = try await service.generateAsync(entry.intent)
                try Task.checkCancellation()
                try service.playLast(loop: entry.intent.soundType == .bgm)
                playingID = entry.id
            } catch is CancellationError {
                // A newer library playback request superseded this one.
            } catch {
                onError(error)
            }
        }
    }

    func stop() {
        playbackTask?.cancel()
        playbackTask = nil
        service.stop()
        playingID = nil
        operationState.cancelPlayback()
    }

    func handleSystemStop() {
        playbackTask?.cancel()
        playbackTask = nil
        playingID = nil
        operationState.cancelPlayback()
    }
}

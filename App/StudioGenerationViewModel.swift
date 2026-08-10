import AudioGenCore
import Foundation
import Observation

/// Performs audio generation actions that do not depend on SwiftUI presentation.
///
/// The studio view remains responsible for translating its visible controls into
/// a recipe. This type owns the service-facing part of each action so additional
/// generation and playback actions can move here incrementally.
@Observable
@MainActor
final class StudioGenerationViewModel {
    private let service: GenerationService
    let operationState = StudioOperationState()
    private var playbackTask: Task<Void, Never>?

    init(service: GenerationService? = nil) {
        self.service = service ?? GenerationService.shared
    }

    func startPlayback(
        showsGeneratingOverlay: Bool,
        work: @escaping @MainActor () async throws -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) {
        playbackTask?.cancel()
        playbackTask = Task { [weak self] in
            guard let self else { return }
            let operationID = operationState.begin(
                kind: .playback,
                showsGeneratingOverlay: showsGeneratingOverlay
            )
            if showsGeneratingOverlay {
                await Task.yield()
            }
            defer { operationState.end(operationID) }

            do {
                try await work()
            } catch is CancellationError {
                // A newer playback request superseded this one.
            } catch {
                onError(error)
            }
        }
    }

    func cancelPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        operationState.cancelPlayback()
    }

    func generateAndPlay(
        recipe: MappedRecipe,
        intent: SoundIntent,
        loopEnabled: Bool
    ) async throws {
        switch recipe {
        case .bgm:
            _ = try await service.generateMappedAsync(recipe, intent: intent)
        case .sfx:
            _ = service.generate(mapped: recipe, intent: intent)
        }
        try Task.checkCancellation()
        try service.playLast(loop: loopEnabled)
    }

    func export(recipe: MappedRecipe, intent: SoundIntent) async throws -> URL {
        switch recipe {
        case .bgm:
            _ = try await service.generateMappedAsync(recipe, intent: intent)
        case .sfx:
            _ = service.generate(mapped: recipe, intent: intent)
        }
        try Task.checkCancellation()
        return try service.exportLastToDocuments()
    }
}

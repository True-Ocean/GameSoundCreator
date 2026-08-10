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

    init(service: GenerationService = .shared) {
        self.service = service
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

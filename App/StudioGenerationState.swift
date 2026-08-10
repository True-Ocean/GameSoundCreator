import AudioGenCore
import Foundation
import Observation

/// Mutable generation state owned by one studio screen.
/// Keeping it separate from the view makes the generation workflow movable to a
/// dedicated view model without changing the UI in the same step.
@Observable
@MainActor
final class StudioGenerationState {
    var mapped: MappedRecipe?
    var catalogDirty = true
    var exportURL: URL?
}

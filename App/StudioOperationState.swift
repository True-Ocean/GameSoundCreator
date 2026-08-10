import Foundation
import Observation

enum StudioOperationKind {
    case playback
    case export
    case librarySave
}

/// Owns the loading state for one studio screen.
///
/// Every asynchronous action gets an ID. A superseded action may finish, but it
/// cannot clear the busy UI belonging to the newer action.
@Observable
@MainActor
final class StudioOperationState {
    private(set) var isBusy = false
    private(set) var showsGeneratingOverlay = false
    private var activeOperationID: UUID?
    private var activeOperationKind: StudioOperationKind?

    func begin(
        kind: StudioOperationKind,
        showsGeneratingOverlay: Bool = false
    ) -> UUID {
        let id = UUID()
        activeOperationID = id
        activeOperationKind = kind
        isBusy = true
        self.showsGeneratingOverlay = showsGeneratingOverlay
        return id
    }

    func end(_ id: UUID) {
        guard activeOperationID == id else { return }
        activeOperationID = nil
        activeOperationKind = nil
        isBusy = false
        showsGeneratingOverlay = false
    }

    /// System audio events only cancel work that will start or alter playback.
    /// Export and save work must remain visibly busy until their own task finishes.
    func cancelPlayback() {
        guard activeOperationKind == .playback else { return }
        cancel()
    }

    func cancel() {
        activeOperationID = nil
        activeOperationKind = nil
        isBusy = false
        showsGeneratingOverlay = false
    }
}

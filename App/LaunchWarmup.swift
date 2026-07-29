import AudioGenCore
import Foundation

/// Keeps AudioGenCore out of the `@main` file so first UI can paint sooner.
enum LaunchWarmup {
    static func run() async {
        await GenerationService.shared.warmup()
    }
}

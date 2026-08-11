import Foundation

/// Public endpoints registered for the App Store release.
///
/// Replace the `nil` values with the final HTTPS URLs after the policy and
/// support pages have been published. Keeping this configuration in one place
/// prevents release builds from shipping a guessed or placeholder URL.
enum AppStoreLinks {
    static let privacyPolicy: URL? = nil
    static let termsOfUse: URL? = nil
    static let support: URL? = nil
}

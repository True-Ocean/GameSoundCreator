import Foundation

/// Public endpoints registered for the App Store release.
///
/// Keeping these URLs in one place ensures that the app and App Store metadata
/// always point people to the same public documentation.
enum AppStoreLinks {
    static let website = URL(string: "https://chatnoirstudio.jp/GameSoundCreator/")
    static let privacyPolicy = URL(string: "https://chatnoirstudio.jp/GameSoundCreator/privacy/")
    static let termsOfUse = URL(string: "https://chatnoirstudio.jp/GameSoundCreator/terms/")
    static let support = URL(string: "https://chatnoirstudio.jp/GameSoundCreator/support/")
}

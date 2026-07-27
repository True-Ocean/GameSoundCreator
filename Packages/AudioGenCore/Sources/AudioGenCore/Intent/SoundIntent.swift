import Foundation

public enum SoundType: String, Codable, Sendable, CaseIterable, Identifiable {
    case bgm
    case sfx

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .bgm: return "BGM"
        case .sfx: return "効果音"
        }
    }
}

public struct SoundIntent: Codable, Equatable, Sendable, Identifiable {
    public var version: Int
    public var soundType: SoundType
    public var genreId: String
    public var sceneId: String?
    public var purposeId: String?
    public var moodId: String
    public var lengthId: String
    public var seed: UInt64?

    public var id: String {
        [
            soundType.rawValue,
            genreId,
            sceneId ?? purposeId ?? "",
            moodId,
            lengthId,
            seed.map(String.init) ?? "nil",
        ].joined(separator: "|")
    }

    public init(
        soundType: SoundType,
        genreId: String = Catalog.Genre.cardBattle.rawValue,
        sceneId: String? = nil,
        purposeId: String? = nil,
        moodId: String = Catalog.Mood.neutral.rawValue,
        lengthId: String = "",
        seed: UInt64? = nil
    ) {
        self.version = 1
        self.soundType = soundType
        self.genreId = genreId
        self.sceneId = sceneId
        self.purposeId = purposeId
        self.moodId = moodId
        self.lengthId = lengthId.isEmpty
            ? (soundType == .bgm ? Catalog.BGMLength.bars16.rawValue : Catalog.SFXLength.medium.rawValue)
            : lengthId
        self.seed = seed
    }

    public var title: String {
        switch soundType {
        case .bgm:
            let scene = Catalog.BGMScene(rawValue: sceneId ?? "")?.displayName ?? (sceneId ?? "BGM")
            return "\(scene)"
        case .sfx:
            let purpose = Catalog.SFXPurpose(rawValue: purposeId ?? "")?.displayName ?? (purposeId ?? "SE")
            return "\(purpose)"
        }
    }

    public func jsonString(pretty: Bool = true) throws -> String {
        let encoder = JSONEncoder()
        if pretty { encoder.outputFormatting = [.prettyPrinted, .sortedKeys] }
        let data = try encoder.encode(self)
        guard let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return string
    }

    public static func from(json: String) throws -> SoundIntent {
        guard let data = json.data(using: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return try JSONDecoder().decode(SoundIntent.self, from: data)
    }
}

public enum MappedRecipe: Equatable, Sendable {
    case sfx(SFXRecipe)
    case bgm(BGMRecipe)

    public var exportFileName: String {
        switch self {
        case .sfx(let recipe): return recipe.exportFileName
        case .bgm(let recipe): return recipe.exportFileName
        }
    }

    public var durationSeconds: Double {
        switch self {
        case .sfx(let recipe):
            return Double(recipe.params.durationMs) / 1000.0
        case .bgm(let recipe):
            return recipe.estimatedDurationSeconds
        }
    }
}

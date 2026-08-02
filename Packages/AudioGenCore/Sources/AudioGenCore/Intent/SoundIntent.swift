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
    /// BGM only. Ignored for SFX. Defaults by scene when empty.
    public var instrumentId: String?
    public var seed: UInt64?

    public var id: String {
        [
            soundType.rawValue,
            genreId,
            sceneId ?? purposeId ?? "",
            moodId,
            lengthId,
            instrumentId ?? "",
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
        instrumentId: String? = nil,
        seed: UInt64? = nil
    ) {
        self.version = 1
        self.soundType = soundType
        self.genreId = genreId
        self.sceneId = sceneId
        self.purposeId = purposeId
        self.moodId = moodId
        self.lengthId = lengthId.isEmpty
            ? (soundType == .bgm ? Catalog.BGMLength.bars8.rawValue : Catalog.SFXLength.medium.rawValue)
            : lengthId
        self.instrumentId = instrumentId
        self.seed = seed
    }

    enum CodingKeys: String, CodingKey {
        case version, soundType, genreId, sceneId, purposeId, moodId, lengthId, instrumentId, seed
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        soundType = try c.decode(SoundType.self, forKey: .soundType)
        genreId = try c.decode(String.self, forKey: .genreId)
        sceneId = try c.decodeIfPresent(String.self, forKey: .sceneId)
        purposeId = try c.decodeIfPresent(String.self, forKey: .purposeId)
        moodId = try c.decode(String.self, forKey: .moodId)
        lengthId = try c.decode(String.self, forKey: .lengthId)
        instrumentId = try c.decodeIfPresent(String.self, forKey: .instrumentId)
        seed = try c.decodeIfPresent(UInt64.self, forKey: .seed)
    }

    public var title: String {
        switch soundType {
        case .bgm:
            let scene = Catalog.BGMScene.resolve(sceneId)?.displayName ?? (sceneId ?? "BGM")
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

import Foundation

public enum IntentMappingError: Error, LocalizedError, Sendable {
    case unsupportedGenre(String)
    case missingScene
    case missingPurpose
    case unknownScene(String)
    case unknownPurpose(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedGenre(let id):
            return "未対応のジャンルです: \(id)"
        case .missingScene:
            return "BGMのシーンが選ばれていません"
        case .missingPurpose:
            return "効果音の用途が選ばれていません"
        case .unknownScene(let id):
            return "不明なシーンです: \(id)"
        case .unknownPurpose(let id):
            return "不明な用途です: \(id)"
        }
    }
}

public struct IntentMapper: Sendable {
    public init() {}

    public func map(_ intent: SoundIntent) throws -> MappedRecipe {
        guard intent.genreId == Catalog.Genre.cardBattle.rawValue else {
            throw IntentMappingError.unsupportedGenre(intent.genreId)
        }

        let seed = intent.seed ?? 1
        switch intent.soundType {
        case .sfx:
            return .sfx(try mapSFX(intent, seed: seed))
        case .bgm:
            return .bgm(try mapBGM(intent, seed: seed))
        }
    }

    private func mapSFX(_ intent: SoundIntent, seed: UInt64) throws -> SFXRecipe {
        guard let purposeId = intent.purposeId else { throw IntentMappingError.missingPurpose }
        guard let purpose = Catalog.SFXPurpose(rawValue: purposeId) else {
            throw IntentMappingError.unknownPurpose(purposeId)
        }

        let length = Catalog.SFXLength(rawValue: intent.lengthId) ?? purpose.defaultLength
        let mood = Catalog.Mood(rawValue: intent.moodId) ?? .neutral

        var pitch: Float = 1.0
        var timbre: Float = 0.5
        var intensity: Float = 0.7
        switch mood {
        case .bright:
            pitch = 1.18
            timbre = 0.35
            intensity = 0.65
        case .neutral:
            break
        case .tense:
            pitch = 1.05
            timbre = 0.65
            intensity = 0.85
        case .dark:
            pitch = 0.82
            timbre = 0.7
            intensity = 0.75
        }

        return SFXRecipe.make(
            category: purpose.category,
            seed: seed,
            pitch: pitch,
            timbre: timbre,
            intensity: intensity,
            variation: Int(seed % 8),
            durationMs: length.durationMs
        )
    }

    private func mapBGM(_ intent: SoundIntent, seed: UInt64) throws -> BGMRecipe {
        guard let sceneId = intent.sceneId else { throw IntentMappingError.missingScene }
        guard let scene = Catalog.BGMScene(rawValue: sceneId) else {
            throw IntentMappingError.unknownScene(sceneId)
        }

        let mood = Catalog.Mood(rawValue: intent.moodId) ?? scene.defaultMood
        let length = Catalog.BGMLength.resolve(intent.lengthId)

        var recipe: BGMRecipe
        switch scene {
        case .menuMain:
            recipe = BGMPreset.menuMain.makeRecipe(seed: seed)
        case .battleNormal, .battleBoss:
            recipe = BGMPreset.battleNormal.makeRecipe(seed: seed)
            if scene == .battleBoss {
                recipe.params.energy = min(1, recipe.params.energy + 0.15)
                recipe.params.tempoBpm = min(160, recipe.params.tempoBpm + 8)
            }
        case .resultWin:
            recipe = BGMPreset.menuMain.makeRecipe(seed: seed)
            recipe.params.key = MusicalKey(root: 0, mode: .major)
            recipe.params.energy = 0.55
            recipe.params.density = 0.7
        case .resultLose:
            recipe = BGMPreset.battleNormal.makeRecipe(seed: seed)
            recipe.params.key = MusicalKey(root: 9, mode: .minor)
            recipe.params.energy = 0.35
            recipe.params.tempoBpm = 88
            recipe.params.density = 0.3
        }

        switch mood {
        case .bright:
            recipe.params.key = MusicalKey(root: recipe.params.key.root, mode: .major)
            recipe.params.energy = max(0.25, recipe.params.energy - 0.1)
        case .neutral:
            break
        case .tense:
            recipe.params.key = MusicalKey(root: recipe.params.key.root, mode: .minor)
            recipe.params.energy = min(1, recipe.params.energy + 0.15)
        case .dark:
            recipe.params.key = MusicalKey(root: recipe.params.key.root, mode: .minor)
            recipe.params.energy = max(0.2, recipe.params.energy - 0.2)
            recipe.params.melody = true
        }

        // Loop length is an exact bar count (multiple of 4-bar chord cycle), not wall-clock seconds.
        recipe.params.bars = length.barCount
        recipe.params.seed = seed
        return recipe
    }
}

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

        // Strong, audible mood differences (not subtle nudges).
        var pitch: Float = 1.0
        var timbre: Float = 0.45
        var intensity: Float = 0.7
        switch mood {
        case .bright:
            pitch = 1.35
            timbre = 0.15
            intensity = 0.55
        case .neutral:
            pitch = 1.0
            timbre = 0.45
            intensity = 0.7
        case .tense:
            pitch = 1.12
            timbre = 0.85
            intensity = 0.95
        case .dark:
            pitch = 0.68
            timbre = 0.9
            intensity = 0.8
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
            recipe.params.energy = 0.55
            recipe.params.density = 0.75
        case .resultLose:
            recipe = BGMPreset.battleNormal.makeRecipe(seed: seed)
            recipe.params.tempoBpm = 88
            recipe.params.density = 0.3
            recipe.params.energy = 0.35
        }

        // Mood owns tonality, tempo feel, brightness, and arrangement weight.
        switch mood {
        case .bright:
            recipe.params.key = MusicalKey(root: scene == .battleNormal || scene == .battleBoss ? 0 : recipe.params.key.root, mode: .major)
            recipe.params.tempoBpm = min(160, recipe.params.tempoBpm + 10)
            recipe.params.energy = max(0.3, recipe.params.energy - 0.15)
            recipe.params.density = min(1, recipe.params.density + 0.15)
            recipe.params.brightness = 0.9
            recipe.params.melody = true
        case .neutral:
            // Keep scene defaults but ensure mode matches a readable center.
            if scene == .menuMain || scene == .resultWin {
                recipe.params.key = MusicalKey(root: recipe.params.key.root, mode: .major)
                recipe.params.brightness = 0.55
            } else {
                recipe.params.key = MusicalKey(root: recipe.params.key.root, mode: .minor)
                recipe.params.brightness = 0.45
            }
        case .tense:
            recipe.params.key = MusicalKey(root: 9, mode: .minor) // A minor center
            recipe.params.tempoBpm = min(160, recipe.params.tempoBpm + 6)
            recipe.params.energy = min(1, max(0.7, recipe.params.energy + 0.2))
            recipe.params.density = min(1, recipe.params.density + 0.1)
            recipe.params.brightness = 0.35
            recipe.params.melody = true
        case .dark:
            recipe.params.key = MusicalKey(root: 4, mode: .minor) // E minor, darker center
            recipe.params.tempoBpm = max(80, recipe.params.tempoBpm - 14)
            recipe.params.energy = max(0.25, recipe.params.energy - 0.15)
            recipe.params.density = max(0.15, recipe.params.density - 0.15)
            recipe.params.brightness = 0.12
            recipe.params.melody = true
        }

        recipe.params.moodId = mood.rawValue
        recipe.params.bars = length.barCount
        recipe.params.seed = seed

        let instrument: Catalog.Instrument
        if let id = intent.instrumentId, !id.isEmpty {
            instrument = Catalog.Instrument.resolve(id)
        } else {
            instrument = Catalog.Instrument.defaultFor(scene: scene)
        }
        recipe.params.instrumentId = instrument.rawValue

        return recipe
    }
}

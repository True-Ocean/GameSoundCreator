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
            return "未対応のゲームタイプです: \(id)"
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
        guard let genre = Catalog.Genre(rawValue: intent.genreId), genre.isAvailable else {
            throw IntentMappingError.unsupportedGenre(intent.genreId)
        }

        let seed = intent.seed ?? 1
        switch intent.soundType {
        case .sfx:
            return .sfx(try mapSFX(intent, seed: seed))
        case .bgm:
            return .bgm(try mapBGM(intent, genre: genre, seed: seed))
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

    private func mapBGM(_ intent: SoundIntent, genre: Catalog.Genre, seed: UInt64) throws -> BGMRecipe {
        guard let sceneId = intent.sceneId else { throw IntentMappingError.missingScene }
        guard let scene = Catalog.BGMScene(rawValue: sceneId) else {
            throw IntentMappingError.unknownScene(sceneId)
        }

        let mood = Catalog.Mood(rawValue: intent.moodId) ?? scene.defaultMood
        let length = Catalog.BGMLength.resolve(intent.lengthId)

        var recipe = baseRecipe(for: scene, seed: seed)
        applyMood(&recipe, mood: mood, scene: scene)
        applyGenre(&recipe, genre: genre, scene: scene)

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

    private func baseRecipe(for scene: Catalog.BGMScene, seed: UInt64) -> BGMRecipe {
        switch scene {
        case .opening, .title, .menuMain, .settings, .shop, .story:
            var recipe = BGMPreset.menuMain.makeRecipe(seed: seed)
            switch scene {
            case .opening:
                recipe.params.energy = 0.48
                recipe.params.density = 0.5
                recipe.params.tempoBpm = 108
                recipe.params.brightness = 0.75
            case .title:
                recipe.params.energy = 0.5
                recipe.params.density = 0.55
                recipe.params.tempoBpm = 112
            case .settings:
                recipe.params.energy = 0.3
                recipe.params.density = 0.35
                recipe.params.tempoBpm = 100
            case .shop:
                recipe.params.energy = 0.45
                recipe.params.density = 0.6
                recipe.params.tempoBpm = 118
                recipe.params.brightness = 0.7
            case .story:
                recipe.params.energy = 0.35
                recipe.params.density = 0.4
                recipe.params.tempoBpm = 96
                recipe.params.brightness = 0.4
            default:
                break
            }
            return recipe

        case .adventure:
            var recipe = BGMPreset.menuMain.makeRecipe(seed: seed)
            recipe.params.tempoBpm = 108
            recipe.params.energy = 0.5
            recipe.params.density = 0.5
            recipe.params.key = MusicalKey(root: 7, mode: .major) // G major
            return recipe

        case .explore:
            // Dungeon-leaning pulse; pairs with bass instrument default.
            var recipe = BGMPreset.menuMain.makeRecipe(seed: seed)
            recipe.params.tempoBpm = 96
            recipe.params.energy = 0.38
            recipe.params.density = 0.4
            recipe.params.brightness = 0.35
            recipe.params.key = MusicalKey(root: 4, mode: .minor) // E minor
            return recipe

        case .battleNormal, .battleBoss, .battlePinch, .battleEasy, .battleHard, .battleExtra:
            var recipe = BGMPreset.battleNormal.makeRecipe(seed: seed)
            switch scene {
            case .battleBoss:
                recipe.params.energy = min(1, recipe.params.energy + 0.15)
                recipe.params.tempoBpm = min(160, recipe.params.tempoBpm + 8)
            case .battlePinch, .battleHard:
                recipe.params.energy = min(1, recipe.params.energy + 0.22)
                recipe.params.tempoBpm = min(160, recipe.params.tempoBpm + 14)
                recipe.params.density = min(1, recipe.params.density + 0.12)
                recipe.params.brightness = 0.28
            case .battleEasy:
                recipe.params.energy = max(0.35, recipe.params.energy - 0.18)
                recipe.params.tempoBpm = max(90, recipe.params.tempoBpm - 10)
                recipe.params.density = max(0.35, recipe.params.density - 0.1)
                recipe.params.brightness = 0.55
            case .battleExtra:
                recipe.params.energy = min(1, recipe.params.energy + 0.28)
                recipe.params.tempoBpm = min(160, recipe.params.tempoBpm + 18)
                recipe.params.density = min(1, recipe.params.density + 0.18)
                recipe.params.brightness = 0.4
            default:
                break
            }
            return recipe

        case .gachaOrReward:
            var recipe = BGMPreset.menuMain.makeRecipe(seed: seed)
            recipe.params.tempoBpm = 126
            recipe.params.energy = 0.55
            recipe.params.density = 0.7
            recipe.params.brightness = 0.85
            recipe.params.key = MusicalKey(root: 0, mode: .major)
            return recipe

        case .resultWin, .resultHappyEnd:
            var recipe = BGMPreset.menuMain.makeRecipe(seed: seed)
            recipe.params.energy = scene == .resultHappyEnd ? 0.62 : 0.55
            recipe.params.density = scene == .resultHappyEnd ? 0.82 : 0.75
            recipe.params.brightness = scene == .resultHappyEnd ? 0.92 : 0.8
            recipe.params.tempoBpm = scene == .resultHappyEnd ? 120 : 112
            return recipe

        case .resultLose, .resultBadEnd:
            var recipe = BGMPreset.battleNormal.makeRecipe(seed: seed)
            recipe.params.tempoBpm = scene == .resultBadEnd ? 78 : 88
            recipe.params.density = scene == .resultBadEnd ? 0.28 : 0.38
            recipe.params.energy = scene == .resultBadEnd ? 0.3 : 0.38
            // Keep somber, but not so dark that phone speakers bury the bed.
            recipe.params.brightness = scene == .resultBadEnd ? 0.22 : 0.3
            return recipe
        }
    }

    private func applyMood(_ recipe: inout BGMRecipe, mood: Catalog.Mood, scene: Catalog.BGMScene) {
        let isBattle = [
            Catalog.BGMScene.battleNormal, .battleBoss, .battlePinch,
            .battleEasy, .battleHard, .battleExtra
        ].contains(scene)
        switch mood {
        case .bright:
            recipe.params.key = MusicalKey(root: isBattle ? 0 : recipe.params.key.root, mode: .major)
            recipe.params.tempoBpm = min(160, recipe.params.tempoBpm + 10)
            recipe.params.energy = max(0.3, recipe.params.energy - 0.15)
            recipe.params.density = min(1, recipe.params.density + 0.15)
            recipe.params.brightness = 0.9
            recipe.params.melody = true
        case .neutral:
            if [.menuMain, .title, .opening, .resultWin, .resultHappyEnd, .shop, .gachaOrReward].contains(scene) {
                recipe.params.key = MusicalKey(root: recipe.params.key.root, mode: .major)
                recipe.params.brightness = max(recipe.params.brightness, 0.55)
            } else if isBattle || scene == .resultLose || scene == .resultBadEnd || scene == .explore {
                recipe.params.key = MusicalKey(root: recipe.params.key.root, mode: .minor)
                recipe.params.brightness = min(recipe.params.brightness, scene == .explore ? 0.38 : 0.45)
            } else {
                recipe.params.brightness = 0.5
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
            recipe.params.density = max(0.2, recipe.params.density - 0.1)
            // Dim, not buried — phone speakers need midrange energy.
            recipe.params.brightness = max(0.22, min(0.35, recipe.params.brightness))
            recipe.params.melody = true
        }
    }

    private func applyGenre(_ recipe: inout BGMRecipe, genre: Catalog.Genre, scene: Catalog.BGMScene) {
        switch genre {
        case .cardBattle:
            break
        case .rpg:
            recipe.params.tempoBpm = max(80, recipe.params.tempoBpm - 8)
            recipe.params.energy = max(0.2, recipe.params.energy - 0.08)
            if scene == .adventure || scene == .explore || scene == .story {
                recipe.params.brightness = min(1, recipe.params.brightness + 0.08)
            }
        case .puzzle:
            recipe.params.tempoBpm = min(160, recipe.params.tempoBpm + 6)
            recipe.params.density = min(1, recipe.params.density + 0.1)
            recipe.params.energy = max(0.25, recipe.params.energy - 0.12)
            recipe.params.brightness = min(1, recipe.params.brightness + 0.12)
            recipe.params.key = MusicalKey(root: recipe.params.key.root, mode: .major)
        case .action, .casual:
            break
        }
    }
}

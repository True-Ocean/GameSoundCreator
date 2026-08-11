import Foundation

/// Internal engine category IDs (SPEC §5.1). One purpose → one category for distinct sound design.
public enum SFXCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case uiTap = "sfx.ui.tap"
    case uiConfirm = "sfx.ui.confirm"
    case uiCancel = "sfx.ui.cancel"
    case uiBack = "sfx.ui.back"
    case uiSwipe = "sfx.ui.swipe"
    case uiWarning = "sfx.ui.warning"
    case uiError = "sfx.ui.error"
    case uiUnlock = "sfx.ui.unlock"
    case uiText = "sfx.ui.text"

    case cardDraw = "sfx.card.draw"
    case cardPlay = "sfx.card.play"
    case cardShuffle = "sfx.card.shuffle"
    case cardFlip = "sfx.card.flip"
    case cardDiscard = "sfx.card.discard"

    case rewardCoin = "sfx.reward.coin"
    case rewardChest = "sfx.reward.chest"
    case rewardLevelUp = "sfx.reward.level_up"

    case puzzleClear = "sfx.puzzle.clear"
    case puzzleCombo = "sfx.puzzle.combo"

    case attackLight = "sfx.attack.light"
    case attackHeavy = "sfx.attack.heavy"
    case attackSlash = "sfx.attack.slash"
    case attackBash = "sfx.attack.bash"
    case attackBreak = "sfx.attack.break"
    case attackBow = "sfx.attack.bow"
    case attackCritical = "sfx.attack.critical"
    case damageTake = "sfx.damage.take"
    case defend = "sfx.defend"
    case defendParry = "sfx.defend.parry"

    case skillCast = "sfx.skill.cast"
    case magicFire = "sfx.magic.fire"
    case magicIce = "sfx.magic.ice"
    case magicPoison = "sfx.magic.poison"
    case magicStorm = "sfx.magic.storm"
    case magicBeam = "sfx.magic.beam"
    case heal = "sfx.heal"

    case moveWalk = "sfx.move.walk"
    case moveRun = "sfx.move.run"
    case moveFly = "sfx.move.fly"
    case moveJump = "sfx.move.jump"
    case moveLand = "sfx.move.land"
    case moveDash = "sfx.move.dash"
    case moveSwim = "sfx.move.swim"
    case moveDoor = "sfx.move.door"
    case moveWarp = "sfx.move.warp"

    case gachaSpin = "sfx.gacha.spin"
    case gachaRare = "sfx.gacha.rare"

    case victory = "sfx.victory"
    case defeat = "sfx.defeat"
    case fanfareSting = "sfx.fanfare.sting"
    case fanfareCorrect = "sfx.fanfare.correct"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .uiTap: return "タップ"
        case .uiConfirm: return "決定"
        case .uiCancel: return "キャンセル"
        case .uiBack: return "戻る"
        case .uiSwipe: return "スワイプ"
        case .uiWarning: return "警告・時間切れ"
        case .uiError: return "エラー・禁止"
        case .uiUnlock: return "ロック解除"
        case .uiText: return "テキスト表示"
        case .cardDraw: return "カードドロー"
        case .cardPlay: return "カードプレイ"
        case .cardShuffle: return "シャッフル"
        case .cardFlip: return "めくる"
        case .cardDiscard: return "捨てる"
        case .rewardCoin: return "コイン獲得"
        case .rewardChest: return "宝箱開封"
        case .rewardLevelUp: return "レベルアップ"
        case .puzzleClear: return "パズル消去"
        case .puzzleCombo: return "コンボ・連鎖"
        case .attackLight: return "通常攻撃"
        case .attackHeavy: return "強攻撃"
        case .attackSlash: return "斬る"
        case .attackBash: return "叩く"
        case .attackBreak: return "割る"
        case .attackBow: return "弓攻撃"
        case .attackCritical: return "クリティカル"
        case .damageTake: return "被ダメージ"
        case .defend: return "防御"
        case .defendParry: return "パリィ・回避"
        case .skillCast: return "スキル発動"
        case .magicFire: return "炎魔法"
        case .magicIce: return "氷魔法"
        case .magicPoison: return "毒"
        case .magicStorm: return "嵐"
        case .magicBeam: return "ビーム照射"
        case .heal: return "回復"
        case .moveWalk: return "歩く"
        case .moveRun: return "走る"
        case .moveFly: return "飛ぶ"
        case .moveJump: return "ジャンプ"
        case .moveLand: return "着地"
        case .moveDash: return "ダッシュ"
        case .moveSwim: return "泳ぐ"
        case .moveDoor: return "扉を開く"
        case .moveWarp: return "ワープ"
        case .gachaSpin: return "ガチャ回転"
        case .gachaRare: return "レア演出"
        case .victory: return "勝利"
        case .defeat: return "敗北"
        case .fanfareSting: return "ジャジャーン"
        case .fanfareCorrect: return "ピンポーン"
        }
    }

    /// Default length when recipe does not override meaningfully.
    public var defaultDurationMs: Int {
        switch self {
        case .uiTap, .uiText: return 80
        case .uiConfirm, .uiCancel, .uiBack: return 140
        case .uiSwipe: return 180
        case .uiWarning: return 420
        case .uiError, .uiUnlock: return 220
        case .cardDraw: return 280
        case .cardPlay, .cardFlip, .cardDiscard: return 220
        case .cardShuffle: return 420
        case .rewardCoin: return 220
        case .rewardChest: return 600
        case .rewardLevelUp: return 700
        case .puzzleClear: return 260
        case .puzzleCombo: return 480
        case .attackLight: return 220
        case .attackSlash: return 280
        case .attackBash: return 280
        case .attackHeavy: return 480
        case .attackBreak: return 450
        case .attackBow: return 500
        case .attackCritical: return 380
        case .damageTake: return 260
        case .defend: return 240
        case .defendParry: return 260
        case .skillCast: return 400
        case .magicFire: return 520
        case .magicIce: return 560
        case .magicPoison: return 480
        case .magicStorm: return 700
        case .magicBeam: return 650
        case .heal: return 380
        case .moveWalk: return 200
        case .moveRun: return 160
        case .moveFly: return 360
        case .moveJump: return 220
        case .moveLand: return 180
        case .moveDash: return 200
        case .moveSwim: return 420
        case .moveDoor: return 380
        case .moveWarp: return 550
        case .gachaSpin: return 500
        case .gachaRare: return 650
        case .victory: return 680
        case .defeat: return 650
        case .fanfareSting: return 650
        case .fanfareCorrect: return 500
        }
    }
}

public struct SFXParams: Codable, Equatable, Sendable {
    public var seed: UInt64
    public var durationMs: Int
    public var pitch: Float
    public var timbre: Float
    public var intensity: Float
    public var variation: Int
    /// How many sound events to layer (1–8).
    public var count: Int

    public init(
        seed: UInt64 = 1,
        durationMs: Int = 220,
        pitch: Float = 1.0,
        timbre: Float = 0.5,
        intensity: Float = 0.7,
        variation: Int = 0,
        count: Int = 1
    ) {
        self.seed = seed
        self.durationMs = min(2000, max(50, durationMs))
        self.pitch = min(2.0, max(0.5, pitch))
        self.timbre = min(1, max(0, timbre))
        self.intensity = min(1, max(0, intensity))
        self.variation = min(7, max(0, variation))
        self.count = min(8, max(1, count))
    }

    public static func defaults(for category: SFXCategory, seed: UInt64 = 1) -> SFXParams {
        SFXParams(seed: seed, durationMs: category.defaultDurationMs)
    }

    enum CodingKeys: String, CodingKey {
        case seed, durationMs, pitch, timbre, intensity, variation, count
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let seed = try c.decode(UInt64.self, forKey: .seed)
        let durationMs = try c.decode(Int.self, forKey: .durationMs)
        let pitch = try c.decode(Float.self, forKey: .pitch)
        let timbre = try c.decode(Float.self, forKey: .timbre)
        let intensity = try c.decode(Float.self, forKey: .intensity)
        let variation = try c.decode(Int.self, forKey: .variation)
        let count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 1
        self.init(
            seed: seed,
            durationMs: durationMs,
            pitch: pitch,
            timbre: timbre,
            intensity: intensity,
            variation: variation,
            count: count
        )
    }
}

public struct SFXRecipe: Codable, Equatable, Sendable {
    public var version: Int
    public var type: String
    public var category: SFXCategory
    public var params: SFXParams

    public init(category: SFXCategory, params: SFXParams) {
        self.version = 1
        self.type = "sfx"
        self.category = category
        self.params = params
    }

    public static func make(
        category: SFXCategory,
        seed: UInt64 = 1,
        pitch: Float = 1.0,
        timbre: Float = 0.5,
        intensity: Float = 0.7,
        variation: Int = 0,
        durationMs: Int? = nil,
        count: Int = 1
    ) -> SFXRecipe {
        var params = SFXParams.defaults(for: category, seed: seed)
        params.pitch = pitch
        params.timbre = timbre
        params.intensity = intensity
        params.variation = variation
        params.count = count
        if let durationMs {
            params.durationMs = durationMs
        }
        return SFXRecipe(category: category, params: params)
    }

    public func jsonString(pretty: Bool = true) throws -> String {
        let encoder = JSONEncoder()
        if pretty {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        let data = try encoder.encode(self)
        guard let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return string
    }

    public static func from(json: String) throws -> SFXRecipe {
        guard let data = json.data(using: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return try JSONDecoder().decode(SFXRecipe.self, from: data)
    }

    public var exportFileName: String {
        let safeCategory = category.rawValue.replacingOccurrences(of: ".", with: "_")
        return "\(safeCategory)_seed\(params.seed).wav"
    }
}

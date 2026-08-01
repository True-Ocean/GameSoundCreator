import Foundation

/// Internal engine category IDs (SPEC §5.1). One purpose → one category for distinct sound design.
public enum SFXCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case uiTap = "sfx.ui.tap"
    case uiConfirm = "sfx.ui.confirm"
    case uiCancel = "sfx.ui.cancel"
    case uiBack = "sfx.ui.back"
    case uiSwipe = "sfx.ui.swipe"
    case uiDoubleTap = "sfx.ui.double_tap"

    case cardDraw = "sfx.card.draw"
    case cardPlay = "sfx.card.play"
    case cardShuffle = "sfx.card.shuffle"
    case cardFlip = "sfx.card.flip"
    case cardDiscard = "sfx.card.discard"

    case attackLight = "sfx.attack.light"
    case attackHeavy = "sfx.attack.heavy"
    case attackSlash = "sfx.attack.slash"
    case attackBash = "sfx.attack.bash"
    case attackBreak = "sfx.attack.break"
    case damageTake = "sfx.damage.take"
    case defend = "sfx.defend"

    case skillCast = "sfx.skill.cast"
    case magicFire = "sfx.magic.fire"
    case magicIce = "sfx.magic.ice"
    case magicPoison = "sfx.magic.poison"
    case heal = "sfx.heal"

    case moveWalk = "sfx.move.walk"
    case moveRun = "sfx.move.run"
    case moveFly = "sfx.move.fly"

    case gachaSpin = "sfx.gacha.spin"
    case gachaRare = "sfx.gacha.rare"

    case victory = "sfx.victory"
    case defeat = "sfx.defeat"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .uiTap: return "タップ"
        case .uiConfirm: return "決定"
        case .uiCancel: return "キャンセル"
        case .uiBack: return "戻る"
        case .uiSwipe: return "スワイプ"
        case .uiDoubleTap: return "ダブルタップ"
        case .cardDraw: return "カードドロー"
        case .cardPlay: return "カードプレイ"
        case .cardShuffle: return "シャッフル"
        case .cardFlip: return "めくる"
        case .cardDiscard: return "捨てる"
        case .attackLight: return "通常攻撃"
        case .attackHeavy: return "強攻撃"
        case .attackSlash: return "斬る"
        case .attackBash: return "叩く"
        case .attackBreak: return "割る"
        case .damageTake: return "被ダメージ"
        case .defend: return "防御"
        case .skillCast: return "スキル発動"
        case .magicFire: return "炎魔法"
        case .magicIce: return "氷魔法"
        case .magicPoison: return "毒"
        case .heal: return "回復"
        case .moveWalk: return "歩く"
        case .moveRun: return "走る"
        case .moveFly: return "飛ぶ"
        case .gachaSpin: return "ガチャ回転"
        case .gachaRare: return "レア演出"
        case .victory: return "勝利"
        case .defeat: return "敗北"
        }
    }

    /// Default length when recipe does not override meaningfully.
    public var defaultDurationMs: Int {
        switch self {
        case .uiTap: return 80
        case .uiConfirm, .uiCancel, .uiBack: return 140
        case .uiSwipe: return 180
        case .uiDoubleTap: return 160
        case .cardDraw: return 280
        case .cardPlay, .cardFlip, .cardDiscard: return 220
        case .cardShuffle: return 420
        case .attackLight, .attackSlash: return 220
        case .attackHeavy, .attackBash: return 380
        case .attackBreak: return 450
        case .damageTake: return 260
        case .defend: return 240
        case .skillCast: return 480
        case .magicFire, .magicIce: return 520
        case .magicPoison: return 480
        case .heal: return 380
        case .moveWalk: return 200
        case .moveRun: return 160
        case .moveFly: return 360
        case .gachaSpin: return 500
        case .gachaRare: return 750
        case .victory: return 700
        case .defeat: return 650
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

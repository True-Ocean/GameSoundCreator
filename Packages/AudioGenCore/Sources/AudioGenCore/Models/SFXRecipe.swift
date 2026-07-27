import Foundation

/// Internal engine category IDs (SPEC §5.1).
public enum SFXCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case uiTap = "sfx.ui.tap"
    case uiConfirm = "sfx.ui.confirm"
    case uiCancel = "sfx.ui.cancel"
    case cardDraw = "sfx.card.draw"
    case cardPlay = "sfx.card.play"
    case attackLight = "sfx.attack.light"
    case attackHeavy = "sfx.attack.heavy"
    case skillCast = "sfx.skill.cast"
    case damageTake = "sfx.damage.take"
    case heal = "sfx.heal"
    case victory = "sfx.victory"
    case defeat = "sfx.defeat"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .uiTap: return "タップ / ボタン"
        case .uiConfirm: return "決定"
        case .uiCancel: return "キャンセル"
        case .cardDraw: return "カードドロー"
        case .cardPlay: return "カードプレイ"
        case .attackLight: return "通常攻撃"
        case .attackHeavy: return "強攻撃"
        case .skillCast: return "スキル発動"
        case .damageTake: return "被ダメージ"
        case .heal: return "回復"
        case .victory: return "勝利"
        case .defeat: return "敗北"
        }
    }

    /// Default length when recipe does not override meaningfully.
    public var defaultDurationMs: Int {
        switch self {
        case .uiTap: return 80
        case .uiConfirm: return 140
        case .uiCancel: return 120
        case .cardDraw: return 280
        case .cardPlay: return 220
        case .attackLight: return 220
        case .attackHeavy: return 420
        case .skillCast: return 480
        case .damageTake: return 260
        case .heal: return 380
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

    public init(
        seed: UInt64 = 1,
        durationMs: Int = 220,
        pitch: Float = 1.0,
        timbre: Float = 0.5,
        intensity: Float = 0.7,
        variation: Int = 0
    ) {
        self.seed = seed
        self.durationMs = min(2000, max(50, durationMs))
        self.pitch = min(2.0, max(0.5, pitch))
        self.timbre = min(1, max(0, timbre))
        self.intensity = min(1, max(0, intensity))
        self.variation = min(7, max(0, variation))
    }

    public static func defaults(for category: SFXCategory, seed: UInt64 = 1) -> SFXParams {
        SFXParams(seed: seed, durationMs: category.defaultDurationMs)
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
        durationMs: Int? = nil
    ) -> SFXRecipe {
        var params = SFXParams.defaults(for: category, seed: seed)
        params.pitch = pitch
        params.timbre = timbre
        params.intensity = intensity
        params.variation = variation
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

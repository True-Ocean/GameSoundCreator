import Foundation

/// Single source of catalog options. Only `available` items appear in MVP UI.
public enum Catalog {
    public struct Item: Identifiable, Hashable, Sendable {
        public let id: String
        public let displayName: String
        public let isAvailable: Bool
        public let group: String?

        public init(id: String, displayName: String, isAvailable: Bool, group: String? = nil) {
            self.id = id
            self.displayName = displayName
            self.isAvailable = isAvailable
            self.group = group
        }
    }

    public enum Genre: String, CaseIterable, Sendable {
        case cardBattle = "card_battle"
        case rpg = "rpg"
        case puzzle = "puzzle"
        case action = "action"
        case casual = "casual"

        public var displayName: String {
            switch self {
            case .cardBattle: return "カードバトル"
            case .rpg: return "RPG"
            case .puzzle: return "パズル"
            case .action: return "アクション"
            case .casual: return "カジュアル"
            }
        }

        public var isAvailable: Bool { self == .cardBattle }
    }

    public enum BGMScene: String, CaseIterable, Sendable {
        case menuMain = "menu_main"
        case battleNormal = "battle_normal"
        case battleBoss = "battle_boss"
        case resultWin = "result_win"
        case resultLose = "result_lose"

        public var displayName: String {
            switch self {
            case .menuMain: return "メインメニュー"
            case .battleNormal: return "通常戦闘"
            case .battleBoss: return "ボス戦"
            case .resultWin: return "勝利"
            case .resultLose: return "敗北"
            }
        }

        public var isAvailable: Bool { true }

        public var defaultMood: Mood {
            switch self {
            case .menuMain: return .bright
            case .battleNormal, .battleBoss: return .tense
            case .resultWin: return .bright
            case .resultLose: return .dark
            }
        }

        public var defaultLength: BGMLength {
            switch self {
            case .menuMain: return .bars16
            case .battleNormal, .battleBoss: return .bars16
            case .resultWin, .resultLose: return .bars8
            }
        }
    }

    public enum SFXPurpose: String, CaseIterable, Sendable {
        case uiTap = "ui_tap"
        case uiConfirm = "ui_confirm"
        case uiCancel = "ui_cancel"
        case cardDraw = "card_draw"
        case cardPlay = "card_play"
        case attackLight = "attack_light"
        case attackHeavy = "attack_heavy"
        case skillCast = "skill_cast"
        case damageTake = "damage_take"
        case heal = "heal"
        case victory = "victory"
        case defeat = "defeat"

        public var displayName: String {
            switch self {
            case .uiTap: return "タップ / ボタン"
            case .uiConfirm: return "決定"
            case .uiCancel: return "キャンセル"
            case .cardDraw: return "カードドロー"
            case .cardPlay: return "カードを出す"
            case .attackLight: return "通常攻撃"
            case .attackHeavy: return "強攻撃"
            case .skillCast: return "スキル発動"
            case .damageTake: return "被ダメージ"
            case .heal: return "回復"
            case .victory: return "勝利"
            case .defeat: return "敗北"
            }
        }

        public var group: String {
            switch self {
            case .uiTap, .uiConfirm, .uiCancel: return "UI"
            case .cardDraw, .cardPlay: return "カード"
            case .attackLight, .attackHeavy, .skillCast, .damageTake, .heal: return "戦闘"
            case .victory, .defeat: return "結果"
            }
        }

        public var isAvailable: Bool { true }

        public var defaultLength: SFXLength {
            switch self {
            case .uiTap, .uiConfirm, .uiCancel: return .short
            case .victory, .defeat, .skillCast, .heal: return .long
            default: return .medium
            }
        }

        public var category: SFXCategory {
            switch self {
            case .uiTap: return .uiTap
            case .uiConfirm: return .uiConfirm
            case .uiCancel: return .uiCancel
            case .cardDraw: return .cardDraw
            case .cardPlay: return .cardPlay
            case .attackLight: return .attackLight
            case .attackHeavy: return .attackHeavy
            case .skillCast: return .skillCast
            case .damageTake: return .damageTake
            case .heal: return .heal
            case .victory: return .victory
            case .defeat: return .defeat
            }
        }
    }

    public enum Mood: String, CaseIterable, Sendable {
        case bright = "bright"
        case neutral = "neutral"
        case tense = "tense"
        case dark = "dark"

        public var displayName: String {
            switch self {
            case .bright: return "明るい"
            case .neutral: return "ふつう"
            case .tense: return "緊張"
            case .dark: return "暗い"
            }
        }

        public var hint: String {
            switch self {
            case .bright: return "高め・軽やか・長調寄り"
            case .neutral: return "シーン標準のバランス"
            case .tense: return "ドラム強め・短調・迫力"
            case .dark: return "低め・静か・くすんだ音色"
            }
        }
    }

    public enum BGMLength: String, CaseIterable, Sendable {
        /// Musical phrase lengths (4/4). Always a multiple of a 4-bar progression cycle.
        case bars8 = "bars_8"
        case bars16 = "bars_16"
        case bars24 = "bars_24"

        public var displayName: String {
            switch self {
            case .bars8: return "短い（8小節）"
            case .bars16: return "ふつう（16小節）"
            case .bars24: return "長め（24小節）"
            }
        }

        public var barCount: Int {
            switch self {
            case .bars8: return 8
            case .bars16: return 16
            case .bars24: return 24
            }
        }

        /// Approximate duration hint at 120 BPM (4/4).
        public var approximateSecondsHint: String {
            let sec = Double(barCount) * 2.0 // 120 BPM → 2 sec/bar
            return String(format: "目安 約%.0f秒＠120BPM", sec)
        }

        /// Resolve current + legacy length IDs (`sec_15` etc.).
        public static func resolve(_ lengthId: String) -> BGMLength {
            switch lengthId {
            case bars8.rawValue, "sec_15":
                return .bars8
            case bars16.rawValue, "sec_30":
                return .bars16
            case bars24.rawValue, "sec_45", "bars_32":
                return .bars24
            default:
                return .bars16
            }
        }
    }

    public enum SFXLength: String, CaseIterable, Sendable {
        case short = "sfx_short"
        case medium = "sfx_medium"
        case long = "sfx_long"

        public var displayName: String {
            switch self {
            case .short: return "短め"
            case .medium: return "ふつう"
            case .long: return "長め"
            }
        }

        public var durationMs: Int {
            switch self {
            case .short: return 120
            case .medium: return 280
            case .long: return 700
            }
        }
    }

    public static var availableGenres: [Item] {
        Genre.allCases.map {
            Item(id: $0.rawValue, displayName: $0.displayName, isAvailable: $0.isAvailable)
        }
    }

    public static var availableBGMScenes: [Item] {
        BGMScene.allCases.filter(\.isAvailable).map {
            Item(id: $0.rawValue, displayName: $0.displayName, isAvailable: true)
        }
    }

    public static var availableSFXPurposes: [Item] {
        SFXPurpose.allCases.filter(\.isAvailable).map {
            Item(id: $0.rawValue, displayName: $0.displayName, isAvailable: true, group: $0.group)
        }
    }

    public static var moods: [Item] {
        Mood.allCases.map { Item(id: $0.rawValue, displayName: $0.displayName, isAvailable: true) }
    }

    public static var bgmLengths: [Item] {
        BGMLength.allCases.map { Item(id: $0.rawValue, displayName: $0.displayName, isAvailable: true) }
    }

    public static var sfxLengths: [Item] {
        SFXLength.allCases.map { Item(id: $0.rawValue, displayName: $0.displayName, isAvailable: true) }
    }
}

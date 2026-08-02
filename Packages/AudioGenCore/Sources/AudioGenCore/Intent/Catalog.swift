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

    /// ゲームタイプ（BGM の音色・テンポ寄り。旧「ジャンル」）。
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

        public var hint: String {
            switch self {
            case .cardBattle: return "キビキビしたループ。戦闘とメニューのメリハリ"
            case .rpg: return "ややゆったり。冒険・探索向き"
            case .puzzle: return "軽快で短いフレーズ寄り"
            case .action: return "高テンポ・迫力寄り（準備中）"
            case .casual: return "明るく短いループ寄り（準備中）"
            }
        }

        /// BGM スタジオで選べるタイプ。
        public var isAvailable: Bool {
            switch self {
            case .cardBattle, .rpg, .puzzle: return true
            case .action, .casual: return false
            }
        }
    }

    public enum BGMScene: String, CaseIterable, Sendable {
        // 画面
        case opening = "opening"
        case title = "title"
        case menuMain = "menu_main"
        case shop = "shop"
        case gachaOrReward = "gacha_or_reward"
        case settings = "settings"
        // プレイ中
        case story = "story"
        case adventure = "adventure"
        case explore = "explore"
        case battleNormal = "battle_normal"
        case battleBoss = "battle_boss"
        case battleEasy = "battle_easy"
        case battleHard = "battle_hard"
        case battleExtra = "battle_extra"
        /// Legacy library entries; hidden from picker.
        case battlePinch = "battle_pinch"
        // 結果
        case resultWin = "result_win"
        case resultLose = "result_lose"
        case resultHappyEnd = "result_happy_end"
        case resultBadEnd = "result_bad_end"

        public var displayName: String {
            switch self {
            case .opening: return "オープニング"
            case .title: return "タイトル"
            case .menuMain: return "メインメニュー"
            case .shop: return "ショップ"
            case .gachaOrReward: return "ガチャ"
            case .settings: return "設定"
            case .story: return "ストーリー"
            case .adventure: return "冒険"
            case .explore: return "探索"
            case .battleNormal: return "バトル"
            case .battleBoss: return "ボス戦"
            case .battleEasy: return "イージーモード"
            case .battleHard: return "ハードモード"
            case .battleExtra: return "エクストラモード"
            case .battlePinch: return "ピンチ"
            case .resultWin: return "勝利"
            case .resultLose: return "敗北"
            case .resultHappyEnd: return "ハッピーエンド"
            case .resultBadEnd: return "バッドエンド"
            }
        }

        public var group: String {
            switch self {
            case .opening, .title, .menuMain, .shop, .gachaOrReward, .settings:
                return "画面"
            case .story, .adventure, .explore, .battleNormal, .battleBoss,
                 .battleEasy, .battleHard, .battleExtra, .battlePinch:
                return "プレイ中"
            case .resultWin, .resultLose, .resultHappyEnd, .resultBadEnd:
                return "結果"
            }
        }

        public var isAvailable: Bool {
            self != .battlePinch
        }

        public var defaultMood: Mood {
            switch self {
            case .opening, .title, .menuMain, .shop, .gachaOrReward, .resultWin, .resultHappyEnd:
                return .bright
            case .settings, .story, .adventure, .explore, .battleEasy:
                return .neutral
            case .battleNormal, .battleBoss, .battleHard, .battleExtra, .battlePinch:
                return .tense
            case .resultLose, .resultBadEnd:
                return .dark
            }
        }

        public var defaultLength: BGMLength {
            switch self {
            case .opening, .title, .settings, .gachaOrReward,
                 .resultWin, .resultLose, .resultHappyEnd, .resultBadEnd:
                return .bars4
            case .menuMain, .shop, .story, .adventure, .explore,
                 .battleNormal, .battleBoss, .battleEasy, .battleHard, .battleExtra, .battlePinch:
                return .bars8
            }
        }
    }

    public enum SFXPurpose: String, CaseIterable, Sendable {
        // UI
        case uiTap = "ui_tap"
        case uiConfirm = "ui_confirm"
        case uiCancel = "ui_cancel"
        case uiBack = "ui_back"
        case uiSwipe = "ui_swipe"
        case uiDoubleTap = "ui_double_tap"
        // カード
        case cardDraw = "card_draw"
        case cardPlay = "card_play"
        case cardShuffle = "card_shuffle"
        case cardFlip = "card_flip"
        case cardDiscard = "card_discard"
        // バトル
        case attackLight = "attack_light"
        case attackHeavy = "attack_heavy"
        case attackSlash = "attack_slash"
        case attackBash = "attack_bash"
        case attackBreak = "attack_break"
        case damageTake = "damage_take"
        case defend = "defend"
        // 魔法・状態
        case skillCast = "skill_cast"
        case magicFire = "magic_fire"
        case magicIce = "magic_ice"
        case magicPoison = "magic_poison"
        case heal = "heal"
        // 動作
        case moveWalk = "move_walk"
        case moveRun = "move_run"
        case moveFly = "move_fly"
        // ガチャ
        case gachaSpin = "gacha_spin"
        case gachaRare = "gacha_rare"
        // 結果
        case victory = "victory"
        case defeat = "defeat"

        public var displayName: String {
            switch self {
            case .uiTap: return "タップ"
            case .uiConfirm: return "決定 (OK)"
            case .uiCancel: return "キャンセル"
            case .uiBack: return "戻る"
            case .uiSwipe: return "スワイプ"
            case .uiDoubleTap: return "ダブルタップ"
            case .cardDraw: return "ドロー"
            case .cardPlay: return "カードを出す"
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
            case .heal: return "癒し / 回復"
            case .moveWalk: return "歩く"
            case .moveRun: return "走る"
            case .moveFly: return "飛ぶ"
            case .gachaSpin: return "ガチャ回転"
            case .gachaRare: return "レア演出"
            case .victory: return "勝利"
            case .defeat: return "敗北"
            }
        }

        public var group: String {
            switch self {
            case .uiTap, .uiConfirm, .uiCancel, .uiBack, .uiSwipe, .uiDoubleTap: return "UI"
            case .cardDraw, .cardPlay, .cardShuffle, .cardFlip, .cardDiscard: return "カード"
            case .attackLight, .attackHeavy, .attackSlash, .attackBash, .attackBreak, .damageTake, .defend:
                return "バトル"
            case .skillCast, .magicFire, .magicIce, .magicPoison, .heal: return "魔法・状態"
            case .moveWalk, .moveRun, .moveFly: return "動作"
            case .gachaSpin, .gachaRare: return "ガチャ"
            case .victory, .defeat: return "結果"
            }
        }

        public var isAvailable: Bool { true }

        public var defaultLength: SFXLength {
            switch self {
            case .uiTap, .uiConfirm, .uiCancel, .uiBack, .uiSwipe, .uiDoubleTap,
                 .moveWalk, .moveRun:
                return .short
            case .victory, .defeat, .skillCast, .heal, .gachaRare, .magicFire, .magicIce:
                return .long
            default:
                return .medium
            }
        }

        /// 用途ごとに専用エンジンカテゴリ（1:1）。音の作り分けは SFXEngine 側。
        public var category: SFXCategory {
            switch self {
            case .uiTap: return .uiTap
            case .uiConfirm: return .uiConfirm
            case .uiCancel: return .uiCancel
            case .uiBack: return .uiBack
            case .uiSwipe: return .uiSwipe
            case .uiDoubleTap: return .uiDoubleTap
            case .cardDraw: return .cardDraw
            case .cardPlay: return .cardPlay
            case .cardShuffle: return .cardShuffle
            case .cardFlip: return .cardFlip
            case .cardDiscard: return .cardDiscard
            case .attackLight: return .attackLight
            case .attackHeavy: return .attackHeavy
            case .attackSlash: return .attackSlash
            case .attackBash: return .attackBash
            case .attackBreak: return .attackBreak
            case .damageTake: return .damageTake
            case .defend: return .defend
            case .skillCast: return .skillCast
            case .magicFire: return .magicFire
            case .magicIce: return .magicIce
            case .magicPoison: return .magicPoison
            case .heal: return .heal
            case .moveWalk: return .moveWalk
            case .moveRun: return .moveRun
            case .moveFly: return .moveFly
            case .gachaSpin: return .gachaSpin
            case .gachaRare: return .gachaRare
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

    /// BGM 音色プリセット（Phase 3.5）。SE では未使用。
    public enum Instrument: String, CaseIterable, Sendable {
        case leadSynth = "lead_synth"
        case piano = "piano"
        case pad = "pad"
        case bass = "bass"
        case musicBox = "music_box"
        case organ = "organ"
        case guitar = "guitar"

        public var displayName: String {
            switch self {
            case .leadSynth: return "シンセリード"
            case .piano: return "ピアノ風"
            case .pad: return "パッド"
            case .bass: return "ベース"
            case .musicBox: return "オルゴール"
            case .organ: return "オルガン"
            case .guitar: return "ギター風"
            }
        }

        public var hint: String {
            switch self {
            case .leadSynth: return "キビキビしたメロディ向き。戦闘に合う"
            case .piano: return "アタックのはっきりした鍵盤風。メニュー向き"
            case .pad: return "ゆっくり広がる厚み。雰囲気・敗北寄り"
            case .bass: return "低音を前面に。土台を強調"
            case .musicBox: return "高いキラキラのプラック。ショップ・ガチャ向き"
            case .organ: return "持続する荘厳な響き。ストーリー向き"
            case .guitar: return "明るめのプラック。冒険・カジュアル向き"
            }
        }

        public var isAvailable: Bool { true }

        public static func resolve(_ id: String?) -> Instrument {
            guard let id, let value = Instrument(rawValue: id) else { return .leadSynth }
            return value
        }

        public static func defaultFor(scene: BGMScene) -> Instrument {
            switch scene {
            case .battleNormal, .battleBoss, .battlePinch, .battleHard, .battleExtra:
                return .leadSynth
            case .battleEasy:
                return .piano
            case .opening, .title, .menuMain, .resultWin, .resultHappyEnd:
                return .piano
            case .shop, .gachaOrReward:
                return .musicBox
            case .settings, .resultLose, .resultBadEnd:
                return .pad
            case .story:
                return .organ
            case .adventure, .explore:
                return .guitar
            }
        }
    }

    public enum BGMLength: String, CaseIterable, Sendable {
        /// Musical phrase lengths (4/4). Always a multiple of a 4-bar progression cycle.
        /// Form: 4=1メロ(くり返し) / 8=2メロ(起承) / 16=4メロ(起承転結).
        case bars4 = "bars_4"
        case bars8 = "bars_8"
        case bars16 = "bars_16"

        public var displayName: String {
            switch self {
            case .bars4: return "短・1メロ"
            case .bars8: return "中・2メロ"
            case .bars16: return "長・4メロ"
            }
        }

        /// Short UI caption for how length shapes phrase form.
        public var formHint: String {
            switch self {
            case .bars4: return "1メロ"
            case .bars8: return "2メロ"
            case .bars16: return "4メロ"
            }
        }

        public var barCount: Int {
            switch self {
            case .bars4: return 4
            case .bars8: return 8
            case .bars16: return 16
            }
        }

        /// Approximate duration hint at 120 BPM (4/4).
        public var approximateSecondsHint: String {
            let sec = Double(barCount) * 2.0 // 120 BPM → 2 sec/bar
            return String(format: "目安 約%.0f秒＠120BPM", sec)
        }

        /// Resolve current + legacy length IDs (`sec_15` / `bars_24` etc.).
        public static func resolve(_ lengthId: String) -> BGMLength {
            switch lengthId {
            case bars4.rawValue, "sec_15":
                return .bars4
            case bars8.rawValue:
                return .bars8
            case bars16.rawValue, "sec_30":
                return .bars16
            case "bars_24", "sec_45", "bars_32":
                return .bars16
            default:
                return .bars8
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

    public static var selectableGenres: [Genre] {
        Genre.allCases.filter(\.isAvailable)
    }

    public static var availableBGMScenes: [Item] {
        BGMScene.allCases.filter(\.isAvailable).map {
            Item(id: $0.rawValue, displayName: $0.displayName, isAvailable: true, group: $0.group)
        }
    }

    public static let bgmSceneGroupOrder = ["画面", "プレイ中", "結果"]

    public static func bgmScenes(in group: String) -> [BGMScene] {
        BGMScene.allCases.filter { $0.isAvailable && $0.group == group }
    }

    public static var availableSFXPurposes: [Item] {
        SFXPurpose.allCases.filter(\.isAvailable).map {
            Item(id: $0.rawValue, displayName: $0.displayName, isAvailable: true, group: $0.group)
        }
    }

    /// Stable order for SE purpose browsing.
    public static let sfxPurposeGroupOrder = ["UI", "カード", "バトル", "魔法・状態", "動作", "ガチャ", "結果"]

    public static func sfxPurposes(in group: String) -> [SFXPurpose] {
        SFXPurpose.allCases.filter { $0.isAvailable && $0.group == group }
    }

    public static var moods: [Item] {
        Mood.allCases.map { Item(id: $0.rawValue, displayName: $0.displayName, isAvailable: true) }
    }

    public static var instruments: [Item] {
        Instrument.allCases.filter(\.isAvailable).map {
            Item(id: $0.rawValue, displayName: $0.displayName, isAvailable: true)
        }
    }

    public static var bgmLengths: [Item] {
        BGMLength.allCases.map { Item(id: $0.rawValue, displayName: $0.displayName, isAvailable: true) }
    }

    public static var sfxLengths: [Item] {
        SFXLength.allCases.map { Item(id: $0.rawValue, displayName: $0.displayName, isAvailable: true) }
    }
}

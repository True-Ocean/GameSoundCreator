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
        /// Legacy; resolves to `title`.
        case opening = "opening"
        case title = "title"
        case menuMain = "menu_main"
        case shop = "shop"
        case gachaOrReward = "gacha_or_reward"
        case settings = "settings"
        // プレイ中
        case story = "story"
        case town = "town"
        case adventure = "adventure"
        case explore = "explore"
        case puzzle = "puzzle"
        case rest = "rest"
        case battleNormal = "battle_normal"
        case battleBoss = "battle_boss"
        /// Legacy difficulty variants; resolve to `battle_normal`.
        case battleEasy = "battle_easy"
        case battleHard = "battle_hard"
        case battleExtra = "battle_extra"
        case battlePinch = "battle_pinch"
        // 結果
        case resultWin = "result_win"
        case resultLose = "result_lose"
        /// Legacy; resolves to `result_win` / `result_lose`.
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
            case .town: return "町／拠点"
            case .adventure: return "冒険"
            case .explore: return "探索"
            case .puzzle: return "パズル／思考"
            case .rest: return "休憩"
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
            case .story, .town, .adventure, .explore, .puzzle, .rest,
                 .battleNormal, .battleBoss, .battleEasy, .battleHard, .battleExtra, .battlePinch:
                return "プレイ中"
            case .resultWin, .resultLose, .resultHappyEnd, .resultBadEnd:
                return "結果"
            }
        }

        public var isAvailable: Bool {
            switch self {
            case .title, .menuMain, .shop, .gachaOrReward, .settings,
                 .story, .town, .adventure, .explore, .puzzle, .rest,
                 .battleNormal, .battleBoss, .resultWin, .resultLose:
                return true
            case .opening, .battleEasy, .battleHard, .battleExtra, .battlePinch,
                 .resultHappyEnd, .resultBadEnd:
                return false
            }
        }

        /// Collapse legacy IDs so library entries keep working.
        public var resolved: BGMScene {
            switch self {
            case .opening: return .title
            case .battleEasy, .battleHard, .battleExtra, .battlePinch: return .battleNormal
            case .resultHappyEnd: return .resultWin
            case .resultBadEnd: return .resultLose
            case .title, .menuMain, .shop, .gachaOrReward, .settings,
                 .story, .town, .adventure, .explore, .puzzle, .rest,
                 .battleNormal, .battleBoss, .resultWin, .resultLose:
                return self
            }
        }

        public static func resolve(_ id: String?) -> BGMScene? {
            guard let id, let scene = BGMScene(rawValue: id) else { return nil }
            return scene.resolved
        }

        public var defaultMood: Mood {
            switch resolved {
            case .title, .menuMain, .shop, .gachaOrReward, .town, .resultWin:
                return .bright
            case .settings, .story, .adventure, .explore, .puzzle, .rest:
                return .neutral
            case .battleNormal, .battleBoss:
                return .tense
            case .resultLose:
                return .dark
            case .opening, .battleEasy, .battleHard, .battleExtra, .battlePinch,
                 .resultHappyEnd, .resultBadEnd:
                return .neutral
            }
        }

        public var defaultLength: BGMLength {
            switch resolved {
            case .title, .settings, .gachaOrReward, .resultWin, .resultLose:
                return .bars4
            case .menuMain, .shop, .story, .town, .adventure, .explore, .puzzle, .rest,
                 .battleNormal, .battleBoss:
                return .bars8
            case .opening, .battleEasy, .battleHard, .battleExtra, .battlePinch,
                 .resultHappyEnd, .resultBadEnd:
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
        case uiWarning = "ui_warning"
        case uiError = "ui_error"
        case uiUnlock = "ui_unlock"
        case uiText = "ui_text"
        // カード
        case cardDraw = "card_draw"
        case cardPlay = "card_play"
        case cardShuffle = "card_shuffle"
        case cardFlip = "card_flip"
        case cardDiscard = "card_discard"
        // 報酬・成長
        case rewardCoin = "reward_coin"
        case rewardChest = "reward_chest"
        case rewardLevelUp = "reward_level_up"
        // パズル・ミニゲーム
        case puzzleClear = "puzzle_clear"
        case puzzleCombo = "puzzle_combo"
        // バトル
        case attackLight = "attack_light"
        case attackHeavy = "attack_heavy"
        case attackSlash = "attack_slash"
        case attackBash = "attack_bash"
        case attackBreak = "attack_break"
        case attackBow = "attack_bow"
        case attackCritical = "attack_critical"
        case damageTake = "damage_take"
        case defend = "defend"
        case defendParry = "defend_parry"
        // 魔法・状態
        case skillCast = "skill_cast"
        case magicFire = "magic_fire"
        case magicIce = "magic_ice"
        case magicPoison = "magic_poison"
        case magicStorm = "magic_storm"
        case magicBeam = "magic_beam"
        case heal = "heal"
        // 動作
        case moveWalk = "move_walk"
        case moveRun = "move_run"
        case moveFly = "move_fly"
        case moveJump = "move_jump"
        case moveLand = "move_land"
        case moveDash = "move_dash"
        case moveSwim = "move_swim"
        case moveDoor = "move_door"
        case moveWarp = "move_warp"
        // ガチャ
        case gachaSpin = "gacha_spin"
        case gachaRare = "gacha_rare"
        // ファンファーレ
        case victory = "victory"
        case defeat = "defeat"
        case fanfareSting = "fanfare_sting"
        case fanfareCorrect = "fanfare_correct"

        public var displayName: String {
            switch self {
            case .uiTap: return "タップ"
            case .uiConfirm: return "決定 (OK)"
            case .uiCancel: return "キャンセル"
            case .uiBack: return "戻る"
            case .uiSwipe: return "スワイプ"
            case .uiWarning: return "警告・時間切れ"
            case .uiError: return "エラー・禁止"
            case .uiUnlock: return "ロック解除"
            case .uiText: return "テキスト表示"
            case .cardDraw: return "ドロー"
            case .cardPlay: return "カードを出す"
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
            case .heal: return "癒し / 回復"
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

        public var group: String {
            switch self {
            case .uiTap, .uiConfirm, .uiCancel, .uiBack, .uiSwipe,
                 .uiWarning, .uiError, .uiUnlock, .uiText:
                return "UI・テキスト"
            case .cardDraw, .cardPlay, .cardShuffle, .cardFlip, .cardDiscard: return "カード"
            case .rewardCoin, .rewardChest, .rewardLevelUp: return "報酬・成長"
            case .puzzleClear, .puzzleCombo: return "パズル・ミニゲーム"
            case .attackLight, .attackHeavy, .attackSlash, .attackBash, .attackBreak,
                 .attackBow, .attackCritical, .damageTake, .defend, .defendParry:
                return "バトル"
            case .skillCast, .magicFire, .magicIce, .magicPoison, .magicStorm, .magicBeam, .heal:
                return "魔法・状態"
            case .moveWalk, .moveRun, .moveFly, .moveJump, .moveLand, .moveDash, .moveSwim, .moveDoor,
                 .moveWarp:
                return "移動・フィールド"
            case .gachaSpin, .gachaRare: return "ガチャ"
            case .victory, .defeat, .fanfareSting, .fanfareCorrect:
                return "ファンファーレ"
            }
        }

        public var isAvailable: Bool { true }

        public var defaultLength: SFXLength {
            switch self {
            case .uiTap, .uiConfirm, .uiCancel, .uiBack, .uiSwipe, .uiError, .uiUnlock, .uiText,
                 .moveWalk, .moveRun, .moveJump, .moveLand, .moveDash, .puzzleClear, .attackCritical,
                 .defendParry:
                return .short
            case .victory, .defeat, .skillCast, .heal, .gachaRare, .magicFire, .magicIce,
                 .magicStorm, .magicBeam, .attackHeavy, .fanfareSting, .rewardChest, .rewardLevelUp,
                 .moveWarp:
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
            case .uiWarning: return .uiWarning
            case .uiError: return .uiError
            case .uiUnlock: return .uiUnlock
            case .uiText: return .uiText
            case .cardDraw: return .cardDraw
            case .cardPlay: return .cardPlay
            case .cardShuffle: return .cardShuffle
            case .cardFlip: return .cardFlip
            case .cardDiscard: return .cardDiscard
            case .rewardCoin: return .rewardCoin
            case .rewardChest: return .rewardChest
            case .rewardLevelUp: return .rewardLevelUp
            case .puzzleClear: return .puzzleClear
            case .puzzleCombo: return .puzzleCombo
            case .attackLight: return .attackLight
            case .attackHeavy: return .attackHeavy
            case .attackSlash: return .attackSlash
            case .attackBash: return .attackBash
            case .attackBreak: return .attackBreak
            case .attackBow: return .attackBow
            case .attackCritical: return .attackCritical
            case .damageTake: return .damageTake
            case .defend: return .defend
            case .defendParry: return .defendParry
            case .skillCast: return .skillCast
            case .magicFire: return .magicFire
            case .magicIce: return .magicIce
            case .magicPoison: return .magicPoison
            case .magicStorm: return .magicStorm
            case .magicBeam: return .magicBeam
            case .heal: return .heal
            case .moveWalk: return .moveWalk
            case .moveRun: return .moveRun
            case .moveFly: return .moveFly
            case .moveJump: return .moveJump
            case .moveLand: return .moveLand
            case .moveDash: return .moveDash
            case .moveSwim: return .moveSwim
            case .moveDoor: return .moveDoor
            case .moveWarp: return .moveWarp
            case .gachaSpin: return .gachaSpin
            case .gachaRare: return .gachaRare
            case .victory: return .victory
            case .defeat: return .defeat
            case .fanfareSting: return .fanfareSting
            case .fanfareCorrect: return .fanfareCorrect
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

    /// BGM 音色イメージ（Phase 3.5）。SE では未使用。
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
            case .piano: return "ピアノ"
            case .pad: return "パッド"
            case .bass: return "ベース"
            case .musicBox: return "オルゴール"
            case .organ: return "オルガン"
            case .guitar: return "ギター"
            }
        }

        public var hint: String {
            switch self {
            case .leadSynth: return "キビキビしたメロディ向き。戦闘に合う"
            case .piano: return "アタックのはっきりした鍵盤寄り。メニュー向き"
            case .pad: return "ゆっくり広がる厚み。雰囲気・敗北寄り"
            case .bass: return "低音を前面に。探索・ダンジョン向き"
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
            switch scene.resolved {
            case .battleNormal, .battleBoss, .resultWin:
                // Victory uses lead for fanfare bite; distinct from title piano.
                return .leadSynth
            case .title, .menuMain, .puzzle:
                return .piano
            case .town:
                return .guitar
            case .shop, .gachaOrReward:
                return .musicBox
            case .settings, .resultLose, .rest:
                return .pad
            case .story:
                return .organ
            case .adventure:
                return .guitar
            case .explore:
                return .bass
            case .opening, .battleEasy, .battleHard, .battleExtra, .battlePinch,
                 .resultHappyEnd, .resultBadEnd:
                return .piano
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
    public static let sfxPurposeGroupOrder = ["UI・テキスト", "カード", "報酬・成長", "パズル・ミニゲーム", "バトル", "魔法・状態", "移動・フィールド", "ガチャ", "ファンファーレ"]

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

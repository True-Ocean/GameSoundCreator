import Foundation

public enum MusicalMode: String, Codable, Sendable, CaseIterable {
    case major
    case minor
}

public struct MusicalKey: Codable, Equatable, Sendable {
    /// 0 = C, 1 = C#, ... 11 = B
    public var root: Int
    public var mode: MusicalMode

    public init(root: Int, mode: MusicalMode) {
        self.root = ((root % 12) + 12) % 12
        self.mode = mode
    }

    public var displayName: String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        return "\(names[root]) \(mode == .major ? "major" : "minor")"
    }
}

public enum BGMPreset: String, Codable, CaseIterable, Sendable, Identifiable {
    case battleNormal = "bgm.battle.normal"
    case menuMain = "bgm.menu.main"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .battleNormal: return "戦闘 (通常)"
        case .menuMain: return "メインメニュー"
        }
    }

    public func makeRecipe(seed: UInt64 = 1) -> BGMRecipe {
        switch self {
        case .battleNormal:
            return BGMRecipe(
                preset: self,
                params: BGMParams(
                    seed: seed,
                    tempoBpm: 128,
                    key: MusicalKey(root: 9, mode: .minor), // A minor
                    bars: 16,
                    density: 0.65,
                    energy: 0.8,
                    melody: true
                )
            )
        case .menuMain:
            return BGMRecipe(
                preset: self,
                params: BGMParams(
                    seed: seed,
                    tempoBpm: 96,
                    key: MusicalKey(root: 0, mode: .major), // C major
                    bars: 12,
                    density: 0.4,
                    energy: 0.35,
                    melody: true
                )
            )
        }
    }
}

public struct BGMParams: Codable, Equatable, Sendable {
    public var seed: UInt64
    public var tempoBpm: Int
    public var key: MusicalKey
    public var bars: Int
    public var density: Float
    public var energy: Float
    public var melody: Bool
    /// Catalog mood id: bright / neutral / tense / dark — drives audible style in the engine.
    public var moodId: String
    /// 0 = dark/muted, 1 = bright/open. Derived from mood but overridable in fine-tune later.
    public var brightness: Float

    public init(
        seed: UInt64 = 1,
        tempoBpm: Int = 120,
        key: MusicalKey = MusicalKey(root: 0, mode: .major),
        bars: Int = 8,
        density: Float = 0.5,
        energy: Float = 0.5,
        melody: Bool = true,
        moodId: String = "neutral",
        brightness: Float = 0.5
    ) {
        self.seed = seed
        self.tempoBpm = min(160, max(80, tempoBpm))
        self.key = key
        self.bars = min(32, max(4, bars))
        self.density = min(1, max(0, density))
        self.energy = min(1, max(0, energy))
        self.melody = melody
        self.moodId = moodId
        self.brightness = min(1, max(0, brightness))
    }
}

public struct BGMRecipe: Codable, Equatable, Sendable {
    public var version: Int
    public var type: String
    public var preset: BGMPreset
    public var params: BGMParams

    public init(preset: BGMPreset, params: BGMParams) {
        self.version = 1
        self.type = "bgm"
        self.preset = preset
        self.params = params
    }

    public var exportFileName: String {
        let safe = preset.rawValue.replacingOccurrences(of: ".", with: "_")
        return "\(safe)_seed\(params.seed).wav"
    }

    public var estimatedDurationSeconds: Double {
        // 4/4: bars * 4 beats * 60 / bpm
        Double(params.bars) * 4.0 * 60.0 / Double(params.tempoBpm)
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
}

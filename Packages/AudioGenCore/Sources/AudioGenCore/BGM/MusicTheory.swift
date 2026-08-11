import Foundation

enum MusicTheory {
    static func scaleIntervals(mode: MusicalMode) -> [Int] {
        switch mode {
        case .major: return [0, 2, 4, 5, 7, 9, 11]
        case .minor: return [0, 2, 3, 5, 7, 8, 10]
        case .dorian: return [0, 2, 3, 5, 7, 9, 10]
        case .mixolydian: return [0, 2, 4, 5, 7, 9, 10]
        }
    }

    static func midi(root: Int, degree: Int, octave: Int, mode: MusicalMode) -> Int {
        let scale = scaleIntervals(mode: mode)
        let idx = ((degree % 7) + 7) % 7
        // Swift integer division truncates toward zero. For a negative degree,
        // musical notation instead needs floor division: degree -1 is the
        // leading tone below the tonic, never the one an octave above it.
        let octBoost = degree >= 0 ? degree / 7 : -((-degree + 6) / 7)
        return 12 * (octave + octBoost) + root + scale[idx]
    }

    static func freq(midi: Int) -> Double {
        440.0 * pow(2.0, (Double(midi) - 69.0) / 12.0)
    }

    static func triadMIDI(root: Int, chordDegree: Int, octave: Int, mode: MusicalMode) -> [Int] {
        let d0 = chordDegree
        return [
            midi(root: root, degree: d0, octave: octave, mode: mode),
            midi(root: root, degree: d0 + 2, octave: octave, mode: mode),
            midi(root: root, degree: d0 + 4, octave: octave, mode: mode),
        ]
    }

    /// Mild seed-driven transposition that keeps mood mode intact.
    /// Uses consonant offsets so "別パターン" shifts key without leaving the family.
    static func seedTransposeSemitones(seed: UInt64) -> Int {
        let steps = [0, 2, -2, 5, -5, 3, -3, 7]
        var x = seed &+ 0xA24B_AED4_96E9_B5C5
        x ^= x >> 30
        x &*= 0xBF58_476D_1CE4_E5B9
        x ^= x >> 27
        return steps[Int(x % UInt64(steps.count))]
    }

    /// Chooses a mode independently from the root transposition. The base mode
    /// supplied by the scene/mood remains most likely, while alternate patterns
    /// gain a distinct scale color without exposing another UI control.
    static func variationMode(base: MusicalMode, moodId: String, seed: UInt64) -> MusicalMode {
        let mood = Catalog.Mood(rawValue: moodId) ?? .neutral
        let choices: [MusicalMode]
        switch (base, mood) {
        case (.major, .bright), (.major, .neutral):
            choices = [.major, .major, .major, .mixolydian]
        case (.minor, .dark):
            choices = [.minor, .minor, .minor, .dorian]
        case (.minor, .tense):
            choices = [.minor, .minor, .dorian, .minor]
        case (.minor, _):
            choices = [.minor, .minor, .minor, .dorian]
        case (.major, _):
            choices = [.major, .major, .mixolydian, .major]
        default:
            choices = [base]
        }
        return choices[Int(mix(seed, salt: 0x4D4F_4445) % UInt64(choices.count))]
    }

    static func compositionStyle(moodId: String, seed: UInt64) -> BGMCompositionStyle {
        let mood = Catalog.Mood(rawValue: moodId) ?? .neutral
        let choices: [BGMCompositionStyle]
        switch mood {
        case .bright:
            choices = [.hook, .hook, .questionAnswer, .syncopated, .riff]
        case .dark:
            choices = [.spacious, .spacious, .questionAnswer, .riff, .syncopated]
        case .tense:
            choices = [.syncopated, .syncopated, .riff, .hook, .questionAnswer]
        case .neutral:
            choices = [.hook, .questionAnswer, .syncopated, .spacious, .riff]
        }
        return choices[Int(mix(seed, salt: 0x5354_594C_45) % UInt64(choices.count))]
    }

    private static func mix(_ seed: UInt64, salt: UInt64) -> UInt64 {
        var x = seed &+ salt &* 0x9E37_79B9_7F4A_7C15
        x ^= x >> 30
        x &*= 0xBF58_476D_1CE4_E5B9
        x ^= x >> 27
        x &*= 0x94D0_49BB_1331_11EB
        x ^= x >> 31
        return x
    }

    /// More options; mood biases which family is preferred.
    /// `pick` also rotates the cycle so openings are not always tonic.
    static func progression(
        for preset: BGMPreset,
        moodId: String,
        pick: Int,
        style: BGMCompositionStyle = .hook
    ) -> [Int] {
        let mood = Catalog.Mood(rawValue: moodId) ?? .neutral
        let pool: [[Int]]
        switch (preset, mood) {
        case (.battleNormal, .bright):
            pool = [
                [0, 4, 5, 3],
                [0, 5, 3, 4],
                [0, 3, 4, 0],
                [0, 4, 0, 5],
                [0, 5, 4, 3],
                [0, 2, 3, 4],
                [3, 0, 4, 5],
                [4, 5, 3, 0],
                [5, 3, 0, 4],
            ]
        case (.battleNormal, .dark):
            pool = [
                [0, 5, 2, 6],
                [0, 6, 5, 4],
                [0, 3, 6, 0],
                [0, 5, 6, 4],
                [0, 6, 3, 4],
                [0, 2, 5, 6],
                [5, 2, 6, 0],
                [2, 6, 0, 5],
                [6, 5, 4, 0],
            ]
        case (.battleNormal, .tense):
            pool = [
                [0, 5, 2, 6],
                [0, 3, 4, 0],
                [0, 5, 0, 4],
                [0, 6, 5, 4],
                [0, 4, 6, 5],
                [0, 5, 4, 6],
                [5, 2, 6, 0],
                [3, 4, 0, 5],
                [4, 6, 5, 0],
            ]
        case (.battleNormal, _):
            pool = [
                [0, 5, 2, 6],
                [0, 3, 4, 0],
                [0, 5, 0, 4],
                [0, 6, 5, 4],
                [0, 4, 5, 3],
                [0, 5, 3, 4],
                [5, 2, 6, 0],
                [3, 0, 4, 5],
                [4, 5, 3, 0],
            ]
        case (.menuMain, .dark), (.menuMain, .tense):
            pool = [
                [0, 5, 3, 4],
                [0, 3, 4, 0],
                [0, 5, 0, 4],
                [0, 6, 5, 3],
                [0, 3, 5, 4],
                [0, 4, 3, 0],
                [5, 3, 4, 0],
                [3, 4, 0, 5],
                [4, 0, 5, 3],
            ]
        case (.menuMain, _):
            pool = [
                [0, 4, 5, 3],
                [0, 5, 3, 4],
                [0, 3, 4, 0],
                [0, 4, 0, 5],
                [0, 5, 4, 3],
                [0, 2, 5, 3],
                [0, 4, 5, 0],
                [0, 3, 5, 4],
                [3, 0, 4, 5],
                [4, 5, 0, 3],
                [5, 3, 4, 0],
            ]
        }
        let base = pool[pick % pool.count]
        let rotate = (pick / max(1, pool.count)) % max(1, base.count)
        let rotated = rotate > 0 ? Array(base[rotate...]) + Array(base[..<rotate]) : base
        return styleProgression(rotated, style: style)
    }

    /// Changes harmonic rhythm as a phrase-level choice, not merely a new chord order.
    private static func styleProgression(_ progression: [Int], style: BGMCompositionStyle) -> [Int] {
        guard progression.count >= 4 else { return progression }
        switch style {
        case .hook:
            return progression
        case .questionAnswer:
            return [progression[0], progression[1], progression[0], progression[3]]
        case .syncopated:
            return [progression[0], progression[2], progression[1], progression[3]]
        case .spacious:
            return [progression[0], progression[0], progression[2], progression[2]]
        case .riff:
            return [progression[0], progression[1], progression[0], progression[1]]
        }
    }
}

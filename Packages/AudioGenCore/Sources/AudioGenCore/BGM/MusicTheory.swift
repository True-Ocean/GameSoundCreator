import Foundation

enum MusicTheory {
    static func scaleIntervals(mode: MusicalMode) -> [Int] {
        switch mode {
        case .major: return [0, 2, 4, 5, 7, 9, 11]
        case .minor: return [0, 2, 3, 5, 7, 8, 10]
        }
    }

    static func midi(root: Int, degree: Int, octave: Int, mode: MusicalMode) -> Int {
        let scale = scaleIntervals(mode: mode)
        let idx = ((degree % 7) + 7) % 7
        let octBoost = degree / 7
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

    /// More options; mood biases which family is preferred.
    static func progression(for preset: BGMPreset, moodId: String, pick: Int) -> [Int] {
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
            ]
        case (.battleNormal, .dark):
            pool = [
                [0, 5, 2, 6],
                [0, 6, 5, 4],
                [0, 3, 6, 0],
                [0, 5, 6, 4],
                [0, 6, 3, 4],
                [0, 2, 5, 6],
            ]
        case (.battleNormal, .tense):
            pool = [
                [0, 5, 2, 6],
                [0, 3, 4, 0],
                [0, 5, 0, 4],
                [0, 6, 5, 4],
                [0, 4, 6, 5],
                [0, 5, 4, 6],
            ]
        case (.battleNormal, _):
            pool = [
                [0, 5, 2, 6],
                [0, 3, 4, 0],
                [0, 5, 0, 4],
                [0, 6, 5, 4],
                [0, 4, 5, 3],
                [0, 5, 3, 4],
            ]
        case (.menuMain, .dark), (.menuMain, .tense):
            pool = [
                [0, 5, 3, 4],
                [0, 3, 4, 0],
                [0, 5, 0, 4],
                [0, 6, 5, 3],
                [0, 3, 5, 4],
                [0, 4, 3, 0],
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
            ]
        }
        return pool[pick % pool.count]
    }
}

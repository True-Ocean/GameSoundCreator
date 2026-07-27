import Foundation

enum MusicTheory {
    /// Major: W W H W W W H / Minor natural: W H W W H W W
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

    /// Triad degrees for Roman-ish steps: 0=I/i, 1=II/ii, ...
    static func triadMIDI(root: Int, chordDegree: Int, octave: Int, mode: MusicalMode) -> [Int] {
        let d0 = chordDegree
        return [
            midi(root: root, degree: d0, octave: octave, mode: mode),
            midi(root: root, degree: d0 + 2, octave: octave, mode: mode),
            midi(root: root, degree: d0 + 4, octave: octave, mode: mode),
        ]
    }

    /// Progressions as scale degrees (0-based).
    static func progression(for preset: BGMPreset, pick: Int) -> [Int] {
        switch preset {
        case .battleNormal:
            let options: [[Int]] = [
                [0, 5, 2, 6], // i VI III VII
                [0, 3, 4, 0], // i iv V i
                [0, 5, 0, 4], // i VI i V
                [0, 6, 5, 4], // i VII VI V
            ]
            return options[pick % options.count]
        case .menuMain:
            let options: [[Int]] = [
                [0, 4, 5, 3], // I V vi IV
                [0, 5, 3, 4],
                [0, 3, 4, 0],
                [0, 4, 0, 5],
            ]
            return options[pick % options.count]
        }
    }
}

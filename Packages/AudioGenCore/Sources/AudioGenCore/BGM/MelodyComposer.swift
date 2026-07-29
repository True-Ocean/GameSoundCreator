import Foundation

/// One scheduled melody event on the 16th-note grid.
public struct MelodyNote: Equatable, Sendable {
    public var bar: Int
    public var step: Int
    /// Absolute scale degree for `MusicTheory.midi`.
    public var degree: Int
    public var durationSteps: Int
    public var velocity: Float

    public init(bar: Int, step: Int, degree: Int, durationSteps: Int, velocity: Float) {
        self.bar = bar
        self.step = step
        self.degree = degree
        self.durationSteps = max(1, durationSteps)
        self.velocity = min(1, max(0.2, velocity))
    }
}

/// Motif + rhythm-pattern + contour melody plan (Phase 3.5-M1).
public struct MelodyPlan: Equatable, Sendable {
    public var rhythmId: Int
    public var contourId: Int
    public var motifBars: Int
    public var notes: [MelodyNote]
}

/// Pure melody composer — deterministic from seed, no audio I/O.
public enum MelodyComposer {
    private static let stepsPerBar = 16

    public static func compose(
        bars: Int,
        progression: [Int],
        density: Float,
        moodId: String,
        melodyEnabled: Bool,
        melodyChanceScale: Float,
        seed: UInt64
    ) -> MelodyPlan {
        guard melodyEnabled, bars > 0, !progression.isEmpty else {
            return MelodyPlan(rhythmId: 0, contourId: 0, motifBars: 2, notes: [])
        }

        var rng = SeededGenerator(seed: seed &+ 0x4D45_4C4F_4459) // "MELODY"
        let mood = Catalog.Mood(rawValue: moodId) ?? .neutral

        let rhythmPool = rhythmPatterns(for: mood, density: density)
        let rhythmId = Int(rng.unit() * Float(rhythmPool.count)) % rhythmPool.count
        let contourPool = contourShapes(for: mood)
        let contourId = Int(rng.unit() * Float(contourPool.count)) % contourPool.count
        let motifBars = density > 0.65 ? 2 : (rng.unit() > 0.4 ? 2 : 4)
        let keepChance = min(0.98, max(0.25, melodyChanceScale * (0.45 + 0.55 * density)))

        let rhythm = rhythmPool[rhythmId]
        let contour = contourShape(contourPool[contourId], length: max(4, rhythm.count * motifBars))

        // Build motif events for `motifBars` bars (relative degrees vs chord).
        var motifEvents: [(barOffset: Int, step: Int, duration: Int, rel: Int, velocity: Float)] = []
        var contourIndex = 0
        for barOffset in 0..<motifBars {
            for (index, hit) in rhythm.enumerated() {
                let isAnchor = barOffset == 0 && index == 0
                if !isAnchor, rng.unit() > keepChance { continue }

                let relRaw = contour[contourIndex % contour.count]
                contourIndex += 1
                let strong = hit.step % 4 == 0
                let rel = preferChordTone(relRaw, strongBeat: strong)
                let velocity: Float
                if index == 0 {
                    velocity = 1.0
                } else if index == rhythm.count - 1 {
                    velocity = 0.72
                } else {
                    velocity = 0.85
                }
                // Slightly longer on phrase head / strong beats.
                let duration = strong ? max(hit.duration, min(4, hit.duration + 1)) : hit.duration
                motifEvents.append((barOffset, hit.step, duration, rel, velocity))
            }
        }

        // Ensure at least one note when melody is on.
        if motifEvents.isEmpty, let first = rhythm.first {
            motifEvents.append((0, first.step, first.duration, 0, 1))
        }

        var notes: [MelodyNote] = []
        notes.reserveCapacity(bars * max(1, motifEvents.count / max(1, motifBars)))

        for bar in 0..<bars {
            let chordDegree = progression[bar % progression.count]
            let cycle = bar / motifBars
            let barOffset = bar % motifBars
            // Alternate cycles: light variation (invert contour lean / drop an octave lean).
            let variation = cycle % 2 == 1 ? -1 : 0
            let events = motifEvents.filter { $0.barOffset == barOffset }

            for event in events {
                var rel = event.rel + variation
                if event.step % 4 == 0 {
                    rel = preferChordTone(rel, strongBeat: true)
                }
                notes.append(
                    MelodyNote(
                        bar: bar,
                        step: event.step,
                        degree: chordDegree + rel,
                        durationSteps: event.duration,
                        velocity: event.velocity * (cycle % 2 == 1 ? 0.92 : 1)
                    )
                )
            }
        }

        return MelodyPlan(
            rhythmId: rhythmId,
            contourId: contourId,
            motifBars: motifBars,
            notes: notes
        )
    }

    // MARK: - Rhythm / contour libraries

    private struct RhythmHit {
        var step: Int
        var duration: Int
    }

    private static func rhythmPatterns(for mood: Catalog.Mood, density: Float) -> [[RhythmHit]] {
        let sparse: [[RhythmHit]] = [
            [RhythmHit(step: 0, duration: 4), RhythmHit(step: 8, duration: 4)],
            [RhythmHit(step: 0, duration: 2), RhythmHit(step: 4, duration: 2), RhythmHit(step: 8, duration: 4)],
            [RhythmHit(step: 0, duration: 2), RhythmHit(step: 6, duration: 2), RhythmHit(step: 12, duration: 2)],
        ]
        let medium: [[RhythmHit]] = [
            [
                RhythmHit(step: 0, duration: 2), RhythmHit(step: 4, duration: 2),
                RhythmHit(step: 8, duration: 2), RhythmHit(step: 12, duration: 2),
            ],
            [
                RhythmHit(step: 0, duration: 2), RhythmHit(step: 3, duration: 1),
                RhythmHit(step: 6, duration: 2), RhythmHit(step: 8, duration: 2),
                RhythmHit(step: 12, duration: 2),
            ],
            [
                RhythmHit(step: 0, duration: 2), RhythmHit(step: 2, duration: 2),
                RhythmHit(step: 4, duration: 2), RhythmHit(step: 8, duration: 4),
            ],
            [
                RhythmHit(step: 0, duration: 2), RhythmHit(step: 4, duration: 1),
                RhythmHit(step: 6, duration: 2), RhythmHit(step: 10, duration: 2),
                RhythmHit(step: 14, duration: 2),
            ],
        ]
        let dense: [[RhythmHit]] = [
            [
                RhythmHit(step: 0, duration: 1), RhythmHit(step: 2, duration: 1),
                RhythmHit(step: 4, duration: 2), RhythmHit(step: 8, duration: 1),
                RhythmHit(step: 10, duration: 1), RhythmHit(step: 12, duration: 2),
            ],
            [
                RhythmHit(step: 0, duration: 2), RhythmHit(step: 2, duration: 1),
                RhythmHit(step: 4, duration: 1), RhythmHit(step: 6, duration: 2),
                RhythmHit(step: 8, duration: 2), RhythmHit(step: 12, duration: 1),
                RhythmHit(step: 14, duration: 1),
            ],
            [
                RhythmHit(step: 0, duration: 1), RhythmHit(step: 3, duration: 1),
                RhythmHit(step: 4, duration: 2), RhythmHit(step: 8, duration: 1),
                RhythmHit(step: 11, duration: 1), RhythmHit(step: 12, duration: 2),
            ],
        ]

        switch mood {
        case .dark:
            return sparse + medium
        case .tense:
            return density > 0.55 ? dense + medium : medium + dense
        case .bright:
            return density > 0.5 ? medium + dense : medium + sparse
        case .neutral:
            if density < 0.35 { return sparse + medium }
            if density > 0.7 { return dense + medium }
            return medium + sparse + Array(dense.prefix(1))
        }
    }

    private enum ContourKind: CaseIterable {
        case riseFall
        case questionAnswer
        case stepwiseClimb
        case arch
        case zigzag
    }

    private static func contourShapes(for mood: Catalog.Mood) -> [ContourKind] {
        switch mood {
        case .tense:
            return [.zigzag, .riseFall, .questionAnswer, .arch]
        case .bright:
            return [.stepwiseClimb, .riseFall, .questionAnswer, .arch]
        case .dark:
            return [.arch, .riseFall, .questionAnswer]
        case .neutral:
            return ContourKind.allCases
        }
    }

    private static func contourShape(_ kind: ContourKind, length: Int) -> [Int] {
        let base: [Int]
        switch kind {
        case .riseFall:
            base = [0, 1, 2, 4, 3, 2, 1, 0]
        case .questionAnswer:
            base = [0, 2, 4, 2, 3, 1, 0, -1]
        case .stepwiseClimb:
            base = [0, 1, 2, 1, 3, 2, 4, 3]
        case .arch:
            base = [0, 2, 4, 5, 4, 2, 0, 2]
        case .zigzag:
            base = [0, 3, 1, 4, 2, 5, 1, 0]
        }
        if length <= base.count { return Array(base.prefix(length)) }
        var out = base
        while out.count < length {
            out.append(contentsOf: base)
        }
        return Array(out.prefix(length))
    }

    private static func preferChordTone(_ relative: Int, strongBeat: Bool) -> Int {
        guard strongBeat else { return relative }
        let tones = [0, 2, 4, 7, -3, -1]
        return tones.min(by: { abs($0 - relative) < abs($1 - relative) }) ?? 0
    }
}

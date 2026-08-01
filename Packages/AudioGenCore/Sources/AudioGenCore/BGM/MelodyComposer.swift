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

/// Phrase layout driven by BGM length (8 / 16 / 24 bars).
public enum MelodyForm: String, Equatable, Sendable {
    /// Short loop: motif repeats with light variation.
    case loop
    /// 起承: statement then contrasting response.
    case statementResponse
    /// 起承転結: four contrasting sections.
    case kiShoTenKetsu

    public static func forBarCount(_ bars: Int) -> MelodyForm {
        if bars >= 24 { return .kiShoTenKetsu }
        if bars >= 16 { return .statementResponse }
        return .loop
    }

    public var sectionCount: Int {
        switch self {
        case .loop: return 1
        case .statementResponse: return 2
        case .kiShoTenKetsu: return 4
        }
    }

    public func sectionIndex(bar: Int, totalBars: Int) -> Int {
        let count = sectionCount
        guard count > 1, totalBars > 0 else { return 0 }
        return min(count - 1, bar * count / totalBars)
    }
}

/// Motif + rhythm-pattern + contour melody plan (Phase 3.5-M1).
public struct MelodyPlan: Equatable, Sendable {
    public var rhythmId: Int
    public var contourId: Int
    public var motifBars: Int
    public var form: MelodyForm
    public var notes: [MelodyNote]
}

/// Pure melody composer — deterministic from seed, no audio I/O.
public enum MelodyComposer {
    private static let stepsPerBar = 16

    private struct MotifEvent: Equatable {
        var barOffset: Int
        var step: Int
        var duration: Int
        var rel: Int
        var velocity: Float
    }

    public static func compose(
        bars: Int,
        progression: [Int],
        density: Float,
        moodId: String,
        melodyEnabled: Bool,
        melodyChanceScale: Float,
        seed: UInt64
    ) -> MelodyPlan {
        let form = MelodyForm.forBarCount(bars)
        guard melodyEnabled, bars > 0, !progression.isEmpty else {
            return MelodyPlan(rhythmId: 0, contourId: 0, motifBars: 2, form: form, notes: [])
        }

        var rng = SeededGenerator(seed: seed &+ 0x4D45_4C4F_4459) // "MELODY"
        let mood = Catalog.Mood(rawValue: moodId) ?? .neutral

        let rhythmPool = rhythmPatterns(for: mood, density: density)
        let rhythmId = Int(rng.unit() * Float(rhythmPool.count)) % rhythmPool.count
        let contourPool = contourShapes(for: mood)
        let contourId = Int(rng.unit() * Float(contourPool.count)) % contourPool.count
        let motifBars = density > 0.65 ? 2 : (rng.unit() > 0.4 ? 2 : 4)
        let keepChance = min(0.98, max(0.25, melodyChanceScale * (0.45 + 0.55 * density)))

        let rhythmA = rhythmPool[rhythmId]
        let contourA = contourShape(contourPool[contourId], length: max(4, rhythmA.count * motifBars))
        let motifA = buildMotif(
            rhythm: rhythmA,
            contour: contourA,
            motifBars: motifBars,
            keepChance: keepChance,
            rng: &rng
        )

        let rhythmBId = (rhythmId + 1 + Int(rng.unit() * Float(max(1, rhythmPool.count - 1)))) % rhythmPool.count
        let contourBId = (contourId + 1 + Int(rng.unit() * Float(max(1, contourPool.count - 1)))) % contourPool.count
        let rhythmB = rhythmPool[rhythmBId]
        let contourB = contourShape(contourPool[contourBId], length: max(4, rhythmB.count * motifBars))
        let motifB = buildMotif(
            rhythm: rhythmB,
            contour: contourB,
            motifBars: motifBars,
            keepChance: min(0.98, keepChance + 0.08),
            rng: &rng
        )

        var notes: [MelodyNote] = []
        notes.reserveCapacity(bars * max(1, motifA.count / max(1, motifBars)))

        for bar in 0..<bars {
            let chordDegree = progression[bar % progression.count]
            let section = form.sectionIndex(bar: bar, totalBars: bars)
            let (events, degreeBias, velocityScale, thinChance) = sectionRendering(
                form: form,
                section: section,
                motifA: motifA,
                motifB: motifB,
                motifBars: motifBars,
                bar: bar
            )

            for event in events {
                if thinChance > 0, event.step != 0, rng.unit() < thinChance { continue }
                var rel = event.rel + degreeBias
                if event.step % 4 == 0 {
                    rel = preferChordTone(rel, strongBeat: true)
                }
                notes.append(
                    MelodyNote(
                        bar: bar,
                        step: event.step,
                        degree: chordDegree + rel,
                        durationSteps: event.duration,
                        velocity: min(1, max(0.2, event.velocity * velocityScale))
                    )
                )
            }
        }

        return MelodyPlan(
            rhythmId: rhythmId,
            contourId: contourId,
            motifBars: motifBars,
            form: form,
            notes: notes
        )
    }

    /// Arrangement hints for drums / octave (consumed by `BGMEngine`).
    public static func arrangementScale(
        form: MelodyForm,
        section: Int
    ) -> (drum: Float, leadOctaveBias: Int, forceFill: Bool, chordSparse: Bool) {
        switch form {
        case .loop:
            return (1.0, 0, false, false)
        case .statementResponse:
            return section == 0
                ? (1.0, 0, false, false)
                : (1.12, 0, true, false)
        case .kiShoTenKetsu:
            switch section {
            case 0: return (0.95, 0, false, false) // 起
            case 1: return (1.05, 0, false, false) // 承
            case 2: return (1.28, 1, true, false) // 転
            default: return (0.72, 0, false, true) // 結
            }
        }
    }

    // MARK: - Section rendering

    private static func sectionRendering(
        form: MelodyForm,
        section: Int,
        motifA: [MotifEvent],
        motifB: [MotifEvent],
        motifBars: Int,
        bar: Int
    ) -> (events: [MotifEvent], degreeBias: Int, velocityScale: Float, thinChance: Float) {
        let barOffset = bar % motifBars
        switch form {
        case .loop:
            let cycle = bar / motifBars
            let variation = cycle % 2 == 1 ? -1 : 0
            let events = motifA.filter { $0.barOffset == barOffset }.map { event in
                var copy = event
                copy.rel += variation
                copy.velocity *= (cycle % 2 == 1 ? 0.92 : 1)
                return copy
            }
            return (events, 0, 1, 0)

        case .statementResponse:
            if section == 0 {
                return (motifA.filter { $0.barOffset == barOffset }, 0, 1, 0)
            }
            return (motifB.filter { $0.barOffset == barOffset }, 2, 1.05, 0)

        case .kiShoTenKetsu:
            switch section {
            case 0: // 起 — establish A
                return (motifA.filter { $0.barOffset == barOffset }, 0, 1, 0)
            case 1: // 承 — develop A
                return (motifA.filter { $0.barOffset == barOffset }, 2, 1.04, 0)
            case 2: // 転 — contrast B
                return (motifB.filter { $0.barOffset == barOffset }, 4, 1.12, 0)
            default: // 結 — thinned A return
                return (motifA.filter { $0.barOffset == barOffset }, 0, 0.88, 0.35)
            }
        }
    }

    private static func buildMotif(
        rhythm: [RhythmHit],
        contour: [Int],
        motifBars: Int,
        keepChance: Float,
        rng: inout SeededGenerator
    ) -> [MotifEvent] {
        var motifEvents: [MotifEvent] = []
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
                let duration = strong ? max(hit.duration, min(4, hit.duration + 1)) : hit.duration
                motifEvents.append(
                    MotifEvent(
                        barOffset: barOffset,
                        step: hit.step,
                        duration: duration,
                        rel: rel,
                        velocity: velocity
                    )
                )
            }
        }
        if motifEvents.isEmpty, let first = rhythm.first {
            motifEvents.append(
                MotifEvent(barOffset: 0, step: first.step, duration: first.duration, rel: 0, velocity: 1)
            )
        }
        return motifEvents
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

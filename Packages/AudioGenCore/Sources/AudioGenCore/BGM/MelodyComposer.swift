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
        // 短4=1メロ / 中8=2メロ / 長16=4メロ
        if bars >= 16 { return .kiShoTenKetsu }
        if bars >= 8 { return .statementResponse }
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

/// Motif + rhythm-pattern + contour melody plan (Phase 3.5-M1 / pattern diversity).
public struct MelodyPlan: Equatable, Sendable {
    /// Primary motif-family index in the mood dictionary.
    public var rhythmId: Int
    /// Contrast motif-family index (B / 転 side).
    public var contourId: Int
    public var motifBars: Int
    public var form: MelodyForm
    public var notes: [MelodyNote]
}

/// Scene lean for motif-dictionary ordering (Step 5).
public enum MotifSceneBias: String, Equatable, Sendable {
    case general
    case battle
    case menu
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

    /// Paired rhythm + contour family (Step 5 dictionary entry).
    private struct MotifTemplate: Equatable {
        var rhythm: [RhythmHit]
        var contour: ContourKind
        var preferredStart: Int?
        var motifBars: Int
        /// 0 = sparse/calm … 2 = energetic (used for scene ordering).
        var energy: Int
    }

    public static func compose(
        bars: Int,
        progression: [Int],
        density: Float,
        moodId: String,
        melodyEnabled: Bool,
        melodyChanceScale: Float,
        seed: UInt64,
        sceneBias: MotifSceneBias = .general,
        style: BGMCompositionStyle? = nil
    ) -> MelodyPlan {
        let naturalForm = MelodyForm.forBarCount(bars)
        // Even the shortest BGM can become a clear question/answer rather than
        // repeating a two-bar idea when that composition style is selected.
        let form: MelodyForm = style == .questionAnswer && bars >= 4
            ? .statementResponse
            : naturalForm
        guard melodyEnabled, bars > 0, !progression.isEmpty else {
            return MelodyPlan(rhythmId: 0, contourId: 0, motifBars: 2, form: form, notes: [])
        }

        var rng = SeededGenerator(seed: seed &+ 0x4D45_4C4F_4459) // "MELODY"
        let mood = Catalog.Mood(rawValue: moodId) ?? .neutral

        let dictionary = motifDictionary(for: mood, density: density, sceneBias: sceneBias)
        let startPool = startDegreePool(for: mood)

        // A composition style selects a distinct subset before the seed chooses
        // a motif family. This changes the audible opening, not just its details.
        let familyPool = style.map { motifFamilyIndices(for: $0, dictionaryCount: dictionary.count) }
            ?? Array(0..<dictionary.count)
        let familyA = familyPool[Int(mix(seed, salt: 1) % UInt64(familyPool.count))]
        let remainingFamilies = familyPool.filter { $0 != familyA }
        let familyB = remainingFamilies.isEmpty
            ? familyA
            : remainingFamilies[Int(mix(seed, salt: 5) % UInt64(remainingFamilies.count))]
        let templateA = dictionary[familyA]
        let templateB = dictionary[familyB]

        let motifBars: Int
        if density > 0.72 {
            motifBars = 2
        } else if density < 0.35 {
            motifBars = max(templateA.motifBars, 2)
        } else {
            motifBars = templateA.motifBars
        }

        let startDegree = templateA.preferredStart
            ?? startPool[Int(mix(seed, salt: 3) % UInt64(startPool.count))]
        let startIdx = startPool.firstIndex(of: startDegree) ?? 0
        let startDegreeB = templateB.preferredStart
            ?? startPool[(startIdx + 2) % startPool.count]
        let baseKeepChance = min(0.98, max(0.25, melodyChanceScale * (0.45 + 0.55 * density)))
        let keepChance: Float
        switch style {
        case .spacious?:
            keepChance = min(baseKeepChance, 0.62)
        case .riff?:
            keepChance = max(baseKeepChance, 0.88)
        case .hook?, .questionAnswer?, .syncopated?, nil:
            keepChance = baseKeepChance
        }

        let contourA = contourShape(templateA.contour, length: max(4, templateA.rhythm.count * motifBars), mood: mood)
        let motifA = buildMotif(
            rhythm: templateA.rhythm,
            contour: contourA,
            startDegree: startDegree,
            motifBars: motifBars,
            keepChance: keepChance,
            mood: mood,
            rng: &rng
        )

        let contourB = contourShape(templateB.contour, length: max(4, templateB.rhythm.count * motifBars), mood: mood)
        let motifB = buildMotif(
            rhythm: templateB.rhythm,
            contour: contourB,
            startDegree: startDegreeB,
            motifBars: motifBars,
            keepChance: min(0.98, keepChance + 0.08),
            mood: mood,
            rng: &rng
        )

        let rhythmId = familyA
        let contourId = familyB

        var notes: [MelodyNote] = []
        notes.reserveCapacity(bars * max(1, motifA.count / max(1, motifBars)))
        var previousDegree: Int?

        for bar in 0..<bars {
            let chordDegree = progression[bar % progression.count]
            let section = form.sectionIndex(bar: bar, totalBars: bars)
            let (events, degreeBias, velocityScale, thinChance) = sectionRendering(
                form: form,
                section: section,
                motifA: motifA,
                motifB: motifB,
                motifBars: motifBars,
                bar: bar,
                mood: mood
            )

            let isLastBarInSection = bar == bars - 1
                || form.sectionIndex(bar: bar + 1, totalBars: bars) != section
            for (eventIndex, event) in events.enumerated() {
                if thinChance > 0, event.step != 0, rng.unit() < thinChance { continue }
                var rel = sanitizeRelative(event.rel + degreeBias, mood: mood)
                // Keep intentional openings; only gently snap later strong beats.
                let isOpening = bar == 0 && event.step == events.first?.step
                if event.step % 4 == 0, !isOpening {
                    rel = preferChordTone(rel, strongBeat: true, mood: mood)
                }
                let degree = smoothPhraseDegree(
                    target: chordDegree + rel,
                    previous: previousDegree,
                    chordDegree: chordDegree,
                    strongBeat: event.step % 4 == 0,
                    phraseEnding: isLastBarInSection && eventIndex == events.count - 1,
                    mood: mood
                )
                notes.append(
                    MelodyNote(
                        bar: bar,
                        step: event.step,
                        degree: degree,
                        durationSteps: event.duration,
                        velocity: min(1, max(0.2, event.velocity * velocityScale))
                    )
                )
                previousDegree = degree
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
    /// Step 4: 転 contrasts by drums / sparsity / fills — not lead octave.
    public static func arrangementScale(
        form: MelodyForm,
        section: Int,
        moodId: String = Catalog.Mood.neutral.rawValue
    ) -> (drum: Float, leadOctaveBias: Int, forceFill: Bool, chordSparse: Bool) {
        let mood = Catalog.Mood(rawValue: moodId) ?? .neutral
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
            case 2: // 転 — mood-colored arrangement contrast
                switch mood {
                case .bright:
                    return (1.38, 0, true, false) // busier drums + fills
                case .dark:
                    return (0.78, 0, false, true) // space / sparse chords
                case .tense:
                    return (1.42, 0, true, false) // aggressive drums
                case .neutral:
                    return (1.28, 0, true, false)
                }
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
        bar: Int,
        mood: Catalog.Mood
    ) -> (events: [MotifEvent], degreeBias: Int, velocityScale: Float, thinChance: Float) {
        let barOffset = bar % motifBars
        switch form {
        case .loop:
            let cycle = bar / motifBars
            // Bright: vary up (+1) instead of leading-tone dip (-1).
            let variation = cycle % 2 == 1 ? (mood == .bright ? 1 : -1) : 0
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
            case 2: // 転 — rhythm / density / dynamics (Step 4)
                return tenSectionRendering(
                    events: motifB.filter { $0.barOffset == barOffset },
                    mood: mood
                )
            default: // 結 — thinned A return
                return (motifA.filter { $0.barOffset == barOffset }, 0, 0.88, 0.35)
            }
        }
    }

    /// Applies voice leading after chord-relative motif rendering. This is where
    /// a musically valid motif becomes a singable phrase across chord changes.
    private static func smoothPhraseDegree(
        target: Int,
        previous: Int?,
        chordDegree: Int,
        strongBeat: Bool,
        phraseEnding: Bool,
        mood: Catalog.Mood
    ) -> Int {
        guard let previous else { return target }
        let maxStep = mood == .tense && !phraseEnding ? 3 : 2

        if phraseEnding {
            let landing = nearestStableChordTone(to: previous, chordDegree: chordDegree)
            if abs(landing - previous) <= maxStep { return landing }
            return previous + (landing > previous ? maxStep : -maxStep)
        }

        let anchoredTarget = strongBeat
            ? nearestChordTone(to: target, chordDegree: chordDegree)
            : target
        let delta = anchoredTarget - previous
        guard abs(delta) > maxStep else { return anchoredTarget }
        return previous + (delta > 0 ? maxStep : -maxStep)
    }

    private static func nearestChordTone(to degree: Int, chordDegree: Int) -> Int {
        chordToneCandidates(chordDegree: chordDegree, tones: [0, 2, 4])
            .min(by: { abs($0 - degree) < abs($1 - degree) }) ?? degree
    }

    private static func nearestStableChordTone(to degree: Int, chordDegree: Int) -> Int {
        chordToneCandidates(chordDegree: chordDegree, tones: [0, 2])
            .min(by: { abs($0 - degree) < abs($1 - degree) }) ?? degree
    }

    private static func chordToneCandidates(chordDegree: Int, tones: [Int]) -> [Int] {
        (-2...2).flatMap { octave in
            tones.map { chordDegree + $0 + octave * 7 }
        }
    }

    /// 転: keep register mild; contrast via articulation, rests, and energy.
    private static func tenSectionRendering(
        events: [MotifEvent],
        mood: Catalog.Mood
    ) -> (events: [MotifEvent], degreeBias: Int, velocityScale: Float, thinChance: Float) {
        switch mood {
        case .bright:
            // Same-ish register, punchier offbeats, shorter notes.
            let shaped = events.map { event -> MotifEvent in
                var copy = event
                if event.step % 4 != 0 {
                    copy.velocity = min(1, event.velocity * 1.18)
                }
                copy.duration = max(1, event.duration - (event.step % 4 == 0 ? 0 : 1))
                return copy
            }
            return (shaped, 1, 1.16, 0)

        case .dark:
            // Thin and soften — contrast by space, not height.
            let shaped = events.map { event -> MotifEvent in
                var copy = event
                copy.velocity *= 0.9
                copy.duration = max(1, event.duration)
                return copy
            }
            return (shaped, 0, 0.8, 0.45)

        case .tense:
            // Drop some downbeats for a syncopated push; keep mild lift.
            let shaped = events.compactMap { event -> MotifEvent? in
                // Keep phrase anchor; thin other strong beats.
                if event.step != 0, event.step % 4 == 0 { return nil }
                var copy = event
                copy.duration = max(1, min(event.duration, 2))
                copy.velocity = min(1, event.velocity * 1.12)
                return copy
            }
            return (shaped, 1, 1.2, 0.18)

        case .neutral:
            let shaped = events.map { event -> MotifEvent in
                var copy = event
                if event.step % 4 != 0 {
                    copy.duration = max(1, event.duration - 1)
                }
                return copy
            }
            return (shaped, 1, 1.12, 0.14)
        }
    }

    private static func buildMotif(
        rhythm: [RhythmHit],
        contour: [Int],
        startDegree: Int,
        motifBars: Int,
        keepChance: Float,
        mood: Catalog.Mood,
        rng: inout SeededGenerator
    ) -> [MotifEvent] {
        var motifEvents: [MotifEvent] = []
        var contourIndex = 0
        var previousRel: Int?
        var pendingLeapDirection: Int? // +1 / -1; next note steps back
        for barOffset in 0..<motifBars {
            for (index, hit) in rhythm.enumerated() {
                let isAnchor = barOffset == 0 && index == 0
                if !isAnchor, rng.unit() > keepChance { continue }

                let relRaw: Int
                if isAnchor {
                    relRaw = startDegree
                } else {
                    relRaw = contour[contourIndex % contour.count]
                    contourIndex += 1
                }
                let strong = hit.step % 4 == 0
                // Anchor already chose a chord-tone family; keep it. Soft-snap others.
                let snapped = isAnchor ? relRaw : preferChordTone(relRaw, strongBeat: strong, mood: mood)
                var rel = sanitizeRelative(snapped, mood: mood)

                // Step 3: singable motion — step limits, leap recovery.
                if let prev = previousRel {
                    if let leapDir = pendingLeapDirection {
                        rel = sanitizeRelative(prev - leapDir, mood: mood)
                        pendingLeapDirection = nil
                    } else {
                        let stepped = constrainMelodicStep(
                            from: prev,
                            toward: rel,
                            mood: mood,
                            rng: &rng
                        )
                        rel = sanitizeRelative(stepped, mood: mood)
                        let delta = rel - prev
                        if abs(delta) >= 3 {
                            pendingLeapDirection = delta > 0 ? 1 : -1
                        }
                    }
                }

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
                previousRel = rel
            }
        }
        if motifEvents.isEmpty, let first = rhythm.first {
            motifEvents.append(
                MotifEvent(barOffset: 0, step: first.step, duration: first.duration, rel: startDegree, velocity: 1)
            )
        }
        // Phrase ending prefers a stable tone (root / third).
        if motifEvents.count >= 2, var last = motifEvents.last {
            last.rel = stablePhraseEnding(last.rel, mood: mood)
            motifEvents[motifEvents.count - 1] = last
        }
        return motifEvents
    }

    /// Soft step limit so contours stay singable; mood controls how often leaps pass.
    private static func constrainMelodicStep(
        from previous: Int,
        toward target: Int,
        mood: Catalog.Mood,
        rng: inout SeededGenerator
    ) -> Int {
        let maxStep: Int
        let leapChance: Float
        switch mood {
        case .bright:
            maxStep = 2
            leapChance = 0.08
        case .neutral:
            maxStep = 2
            leapChance = 0.14
        case .dark:
            maxStep = 2
            leapChance = 0.12
        case .tense:
            maxStep = 3
            leapChance = 0.32
        }
        let delta = target - previous
        if abs(delta) <= maxStep { return target }
        if rng.unit() < leapChance {
            // Occasional expressive leap (resolved on the next note).
            return target
        }
        return previous + (delta > 0 ? maxStep : -maxStep)
    }

    private static func stablePhraseEnding(_ relative: Int, mood: Catalog.Mood) -> Int {
        let stables: [Int]
        switch mood {
        case .bright, .neutral:
            stables = [0, 2, 4]
        case .dark:
            stables = [0, 2, -3]
        case .tense:
            stables = [0, 2, 5]
        }
        return stables.min(by: { abs($0 - relative) < abs($1 - relative) }) ?? 0
    }

    // MARK: - Motif dictionary (Step 5)

    private static func motifDictionary(
        for mood: Catalog.Mood,
        density: Float,
        sceneBias: MotifSceneBias
    ) -> [MotifTemplate] {
        var templates = moodMotifTemplates(mood, density: density)
        switch sceneBias {
        case .battle:
            templates.sort { $0.energy > $1.energy }
        case .menu:
            templates.sort { $0.energy < $1.energy }
        case .general:
            break
        }
        return templates
    }

    private static func motifFamilyIndices(
        for style: BGMCompositionStyle,
        dictionaryCount: Int
    ) -> [Int] {
        let preferred: [Int]
        switch style {
        case .hook: preferred = [0, 5]
        case .questionAnswer: preferred = [1, 2, 7]
        case .syncopated: preferred = [2, 4, 6]
        case .spacious: preferred = [3, 7]
        case .riff: preferred = [0, 4, 5, 6]
        }
        let available = preferred.filter { $0 < dictionaryCount }
        return available.isEmpty ? Array(0..<dictionaryCount) : available
    }

    private static func moodMotifTemplates(_ mood: Catalog.Mood, density: Float) -> [MotifTemplate] {
        // Shared rhythm skeletons
        let even = [
            RhythmHit(step: 0, duration: 2), RhythmHit(step: 4, duration: 2),
            RhythmHit(step: 8, duration: 2), RhythmHit(step: 12, duration: 2),
        ]
        let syncopated = [
            RhythmHit(step: 0, duration: 2), RhythmHit(step: 3, duration: 1),
            RhythmHit(step: 6, duration: 2), RhythmHit(step: 8, duration: 2),
            RhythmHit(step: 12, duration: 2),
        ]
        let offbeat = [
            RhythmHit(step: 2, duration: 2), RhythmHit(step: 6, duration: 2),
            RhythmHit(step: 8, duration: 2), RhythmHit(step: 12, duration: 2),
        ]
        let sparse = [
            RhythmHit(step: 0, duration: 4), RhythmHit(step: 8, duration: 4),
        ]
        let late = [
            RhythmHit(step: 4, duration: 4), RhythmHit(step: 12, duration: 4),
        ]
        let busy = [
            RhythmHit(step: 0, duration: 1), RhythmHit(step: 2, duration: 1),
            RhythmHit(step: 4, duration: 2), RhythmHit(step: 8, duration: 1),
            RhythmHit(step: 10, duration: 1), RhythmHit(step: 12, duration: 2),
        ]
        let callDrop = [
            RhythmHit(step: 0, duration: 2), RhythmHit(step: 2, duration: 2),
            RhythmHit(step: 4, duration: 2), RhythmHit(step: 8, duration: 4),
        ]
        let tresillo = [
            RhythmHit(step: 0, duration: 2), RhythmHit(step: 3, duration: 2),
            RhythmHit(step: 6, duration: 2), RhythmHit(step: 8, duration: 2),
            RhythmHit(step: 11, duration: 1), RhythmHit(step: 14, duration: 2),
        ]
        let answer = [
            RhythmHit(step: 0, duration: 3), RhythmHit(step: 5, duration: 1),
            RhythmHit(step: 7, duration: 2), RhythmHit(step: 10, duration: 1),
            RhythmHit(step: 12, duration: 3),
        ]

        let preferDense = density > 0.55
        switch mood {
        case .bright:
            return [
                MotifTemplate(rhythm: even, contour: .stepwiseClimb, preferredStart: 0, motifBars: 2, energy: 1),
                MotifTemplate(rhythm: callDrop, contour: .riseFall, preferredStart: 0, motifBars: 2, energy: 1),
                MotifTemplate(rhythm: syncopated, contour: .questionAnswer, preferredStart: 2, motifBars: 2, energy: 2),
                MotifTemplate(rhythm: even, contour: .arch, preferredStart: 0, motifBars: preferDense ? 2 : 4, energy: 1),
                MotifTemplate(rhythm: offbeat, contour: .neighborDip, preferredStart: 2, motifBars: 2, energy: 2),
                MotifTemplate(rhythm: callDrop, contour: .leapResolve, preferredStart: 0, motifBars: 2, energy: 2),
                MotifTemplate(rhythm: tresillo, contour: .highLanding, preferredStart: 2, motifBars: 2, energy: 2),
                MotifTemplate(rhythm: answer, contour: .questionAnswer, preferredStart: 0, motifBars: 4, energy: 1),
            ]
        case .dark:
            return [
                MotifTemplate(rhythm: sparse, contour: .fallRise, preferredStart: 0, motifBars: 4, energy: 0),
                MotifTemplate(rhythm: late, contour: .plunge, preferredStart: 2, motifBars: 2, energy: 0),
                MotifTemplate(rhythm: even, contour: .arch, preferredStart: 0, motifBars: 4, energy: 1),
                MotifTemplate(rhythm: sparse, contour: .highLanding, preferredStart: -3, motifBars: 2, energy: 0),
                MotifTemplate(rhythm: callDrop, contour: .riseFall, preferredStart: 0, motifBars: 2, energy: 1),
                MotifTemplate(rhythm: late, contour: .questionAnswer, preferredStart: 2, motifBars: 4, energy: 0),
                MotifTemplate(rhythm: answer, contour: .neighborDip, preferredStart: -3, motifBars: 4, energy: 0),
                MotifTemplate(rhythm: tresillo, contour: .plunge, preferredStart: 0, motifBars: 2, energy: 1),
            ]
        case .tense:
            return [
                MotifTemplate(rhythm: syncopated, contour: .zigzag, preferredStart: 0, motifBars: 2, energy: 2),
                MotifTemplate(rhythm: busy, contour: .plunge, preferredStart: 5, motifBars: 2, energy: 2),
                MotifTemplate(rhythm: offbeat, contour: .leapResolve, preferredStart: 0, motifBars: 2, energy: 2),
                MotifTemplate(rhythm: syncopated, contour: .highLanding, preferredStart: 4, motifBars: 2, energy: 2),
                MotifTemplate(rhythm: busy, contour: .questionAnswer, preferredStart: -1, motifBars: 2, energy: 2),
                MotifTemplate(rhythm: even, contour: .riseFall, preferredStart: 0, motifBars: preferDense ? 2 : 4, energy: 1),
                MotifTemplate(rhythm: tresillo, contour: .zigzag, preferredStart: 4, motifBars: 2, energy: 2),
                MotifTemplate(rhythm: answer, contour: .leapResolve, preferredStart: 0, motifBars: 2, energy: 2),
            ]
        case .neutral:
            return [
                MotifTemplate(rhythm: even, contour: .riseFall, preferredStart: 0, motifBars: 2, energy: 1),
                MotifTemplate(rhythm: callDrop, contour: .questionAnswer, preferredStart: 2, motifBars: 2, energy: 1),
                MotifTemplate(rhythm: syncopated, contour: .arch, preferredStart: 4, motifBars: 2, energy: 2),
                MotifTemplate(rhythm: sparse, contour: .neighborDip, preferredStart: 0, motifBars: 4, energy: 0),
                MotifTemplate(rhythm: even, contour: .stepwiseClimb, preferredStart: 2, motifBars: preferDense ? 2 : 4, energy: 1),
                MotifTemplate(rhythm: offbeat, contour: .fallRise, preferredStart: 4, motifBars: 2, energy: 1),
                MotifTemplate(rhythm: tresillo, contour: .zigzag, preferredStart: 0, motifBars: 2, energy: 2),
                MotifTemplate(rhythm: answer, contour: .leapResolve, preferredStart: 2, motifBars: 4, energy: 1),
            ]
        }
    }

    // MARK: - Rhythm / contour libraries

    private struct RhythmHit: Equatable {
        var step: Int
        var duration: Int
    }

    private enum ContourKind: CaseIterable {
        case riseFall
        case questionAnswer
        case stepwiseClimb
        case arch
        case zigzag
        case fallRise
        case highLanding
        case plunge
        case leapResolve
        case neighborDip
    }

    private static func contourShape(_ kind: ContourKind, length: Int, mood: Catalog.Mood) -> [Int] {
        let base = contourDegrees(kind, mood: mood).map { sanitizeRelative($0, mood: mood) }
        if length <= base.count { return Array(base.prefix(length)) }
        var out = base
        while out.count < length {
            out.append(contentsOf: base)
        }
        return Array(out.prefix(length))
    }

    /// Mood-colored degree sequences for each contour kind.
    private static func contourDegrees(_ kind: ContourKind, mood: Catalog.Mood) -> [Int] {
        switch kind {
        case .riseFall:
            switch mood {
            case .bright: return [0, 1, 2, 4, 3, 2, 1, 0]
            case .dark: return [2, 0, 2, 0, -1, 0, 2, 0]
            case .tense: return [0, 3, 1, 4, 2, 5, 1, 0]
            case .neutral: return [0, 1, 2, 4, 3, 2, 1, 0]
            }
        case .questionAnswer:
            switch mood {
            case .bright: return [0, 2, 4, 2, 3, 1, 0, 2]
            case .dark: return [0, 2, 0, -1, 0, 2, 0, -3]
            case .tense: return [0, 2, 5, 2, 4, 1, 0, -1]
            case .neutral: return [0, 2, 4, 2, 3, 1, 0, 2]
            }
        case .stepwiseClimb:
            switch mood {
            case .bright: return [0, 1, 2, 1, 3, 2, 4, 3]
            case .dark: return [0, 1, 0, 2, 1, 0, 2, 0]
            case .tense: return [0, 2, 1, 3, 2, 4, 1, 0]
            case .neutral: return [0, 1, 2, 1, 3, 2, 4, 2]
            }
        case .arch:
            switch mood {
            case .bright: return [0, 2, 4, 5, 4, 2, 0, 2]
            case .dark: return [0, 2, 3, 2, 0, -1, 0, 2]
            case .tense: return [0, 3, 5, 4, 2, 5, 1, 0]
            case .neutral: return [0, 2, 4, 5, 4, 2, 0, 2]
            }
        case .zigzag:
            switch mood {
            case .bright: return [0, 2, 1, 4, 2, 3, 1, 0]
            case .dark: return [2, 0, 3, 0, 2, -1, 0, 2]
            case .tense: return [0, 3, 1, 4, 2, 5, 1, 0]
            case .neutral: return [0, 3, 1, 4, 2, 3, 1, 0]
            }
        case .fallRise:
            switch mood {
            case .bright: return [2, 0, 1, 2, 4, 2, 0, 2]
            case .dark: return [4, 2, 0, -1, 0, 2, 0, -3]
            case .tense: return [4, 1, 0, 3, 0, 5, 2, 0]
            case .neutral: return [4, 2, 0, 1, 2, 4, 2, 0]
            }
        case .highLanding:
            switch mood {
            case .bright: return [2, 4, 3, 2, 0, 2, 4, 2]
            case .dark: return [2, 0, 2, 0, -3, 0, 2, 0]
            case .tense: return [4, 3, 1, 5, 2, 0, 4, 1]
            case .neutral: return [4, 3, 2, 0, 2, 4, 3, 2]
            }
        case .plunge:
            switch mood {
            case .bright: return [4, 2, 0, 2, 0, 2, 1, 0] // unused in bright pool
            case .dark: return [4, 2, 0, -1, 0, -3, 0, 2]
            case .tense: return [5, 2, 0, -1, 0, 2, 5, 0]
            case .neutral: return [5, 2, 0, -1, 0, 2, 1, 0]
            }
        case .leapResolve:
            switch mood {
            case .bright: return [0, 4, 2, 0, 5, 2, 0, 2]
            case .dark: return [0, 4, 2, 0, 2, 0, -1, 0]
            case .tense: return [0, 4, 1, 5, 2, 0, 5, -1]
            case .neutral: return [0, 4, 2, 0, 5, 2, 0, 2]
            }
        case .neighborDip:
            switch mood {
            case .bright: return [2, 1, 0, 2, 4, 2, 0, 2]
            case .dark: return [0, 2, 0, -1, 0, 2, 0, 0]
            case .tense: return [2, 0, 3, 1, 4, 0, 2, -1]
            case .neutral: return [2, 1, 0, 2, 4, 2, 0, 2]
            }
        }
    }

    /// Step 2: opening degrees allowed per mood (relative to current chord).
    private static func startDegreePool(for mood: Catalog.Mood) -> [Int] {
        switch mood {
        case .bright:
            return [0, 2, 4, 7]
        case .dark:
            // Prefer root / third / low color; avoid bright high 7ths.
            return [0, 2, -3, 4, 0, 2]
        case .tense:
            return [0, 2, 5, -1, 4, 7]
        case .neutral:
            // Mostly stable; occasional mild color.
            return [0, 2, 4, 0, 2, 4, -1]
        }
    }

    /// Mood pitch hygiene after contour / bias.
    private static func sanitizeRelative(_ relative: Int, mood: Catalog.Mood) -> Int {
        switch mood {
        case .bright:
            if relative == -1 || relative == -3 { return 0 }
            return relative
        case .dark:
            // Keep dark phrases from soaring.
            if relative >= 6 { return 4 }
            return relative
        case .tense, .neutral:
            return relative
        }
    }

    private static func preferChordTone(_ relative: Int, strongBeat: Bool, mood: Catalog.Mood) -> Int {
        guard strongBeat else { return relative }
        let tones: [Int]
        switch mood {
        case .bright:
            tones = [0, 2, 4, 7]
        case .dark:
            tones = [0, 2, 4, -3]
        case .tense:
            tones = [0, 2, 5, 4, -1, 7]
        case .neutral:
            tones = [0, 2, 4, 7]
        }
        return tones.min(by: { abs($0 - relative) < abs($1 - relative) }) ?? 0
    }

    /// SplitMix64-style mix so consecutive seeds diverge in family picks.
    private static func mix(_ seed: UInt64, salt: UInt64) -> UInt64 {
        var x = seed &+ salt &* 0x9E37_79B9_7F4A_7C15
        x ^= x >> 30
        x &*= 0xBF58_476D_1CE4_E5B9
        x ^= x >> 27
        x &*= 0x94D0_49BB_1331_11EB
        x ^= x >> 31
        return x
    }
}

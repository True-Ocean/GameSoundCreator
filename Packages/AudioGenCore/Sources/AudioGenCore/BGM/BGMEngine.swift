import AVFoundation
import Foundation

/// Structural choices that determine how a BGM feels before timbre and DSP are applied.
/// This intentionally excludes root transposition so a mere key change cannot be treated
/// as a meaningfully different pattern.
public struct BGMVariationSignature: Equatable, Sendable {
    public let compositionStyle: BGMCompositionStyle
    public let mode: MusicalMode
    public let progression: [Int]
    public let melodyRhythmID: Int
    public let melodyContourID: Int
    public let motifBars: Int
    public let kickPatternID: Int
    public let snarePatternID: Int
    public let bassPatternID: Int
}

public struct BGMEngine: Sendable {
    public init() {}

    /// Returns the structural profile for a recipe without rendering audio.
    public func variationSignature(for recipe: BGMRecipe) -> BGMVariationSignature {
        let bars = max(4, (recipe.params.bars / 4) * 4)
        let progressionPick = Int((recipe.params.seed &* 0x9E37_79B9) >> 17) % 128
        let compositionStyle = MusicTheory.compositionStyle(
            moodId: recipe.params.moodId,
            seed: recipe.params.seed
        )
        let progression = MusicTheory.progression(
            for: recipe.preset,
            moodId: recipe.params.moodId,
            pick: progressionPick,
            style: compositionStyle
        )
        let melodyDensity = min(1, max(0, recipe.params.density * 0.45 + recipe.params.rhythm * 0.55))
        let sceneBias: MotifSceneBias = recipe.preset == .battleNormal ? .battle : .menu
        let instrument = InstrumentPalette.from(instrumentId: recipe.params.instrumentId)
        let melody = MelodyComposer.compose(
            bars: bars,
            progression: progression,
            density: melodyDensity,
            moodId: recipe.params.moodId,
            melodyEnabled: recipe.params.melody,
            melodyChanceScale: instrument.melodyChanceScale,
            seed: recipe.params.seed,
            sceneBias: sceneBias,
            style: compositionStyle,
            melodicCoherence: recipe.params.melodicCoherence
        )
        var rng = SeededGenerator(seed: recipe.params.seed)
        let kickPatternID = Int(rng.unit() * 5)
        let snarePatternID = Int(rng.unit() * 4)
        return BGMVariationSignature(
            compositionStyle: compositionStyle,
            mode: MusicTheory.variationMode(
                base: recipe.params.key.mode,
                moodId: recipe.params.moodId,
                seed: recipe.params.seed
            ),
            progression: progression,
            melodyRhythmID: melody.rhythmId,
            melodyContourID: melody.contourId,
            motifBars: melody.motifBars,
            kickPatternID: kickPatternID,
            snarePatternID: snarePatternID,
            bassPatternID: Int(recipe.params.seed % 3)
        )
    }

    /// Scores two patterns by musical structure rather than their raw waveform.
    public func structuralDistance(between lhs: BGMRecipe, and rhs: BGMRecipe) -> Int {
        let a = variationSignature(for: lhs)
        let b = variationSignature(for: rhs)
        var score = a.compositionStyle == b.compositionStyle ? 0 : 10
        score += a.mode == b.mode ? 0 : 5
        score += zip(a.progression, b.progression).reduce(0) { $0 + ($1.0 == $1.1 ? 0 : 2) }
        score += a.melodyRhythmID == b.melodyRhythmID ? 0 : 3
        score += a.melodyContourID == b.melodyContourID ? 0 : 3
        score += a.motifBars == b.motifBars ? 0 : 2
        score += a.kickPatternID == b.kickPatternID ? 0 : 1
        score += a.snarePatternID == b.snarePatternID ? 0 : 1
        score += a.bassPatternID == b.bassPatternID ? 0 : 1
        return score
    }

    /// Chooses the candidate that is structurally furthest from the current BGM.
    public func distinctSeed(from candidates: [UInt64], comparedTo current: BGMRecipe) -> UInt64? {
        candidates.max { lhs, rhs in
            var left = current
            left.params.seed = lhs
            var right = current
            right.params.seed = rhs
            return structuralDistance(between: current, and: left)
                < structuralDistance(between: current, and: right)
        }
    }

    public func generate(_ recipe: BGMRecipe) -> AVAudioPCMBuffer {
        let sampleRate = AudioFormatDefaults.sampleRate
        let bpm = Double(recipe.params.tempoBpm)
        let secondsPerBeat = 60.0 / bpm
        let stepsPerBar = 16
        let stepFrames = max(1, Int((secondsPerBeat / 4.0 * sampleRate).rounded()))
        let framesPerBar = stepsPerBar * stepFrames
        let progressionCycle = 4
        let bars = max(progressionCycle, (recipe.params.bars / progressionCycle) * progressionCycle)
        let frames = bars * framesPerBar

        var samples = [Float](repeating: 0, count: frames)
        var rng = SeededGenerator(seed: recipe.params.seed)

        // Seed-mixed pick explores more progression families / rotations.
        let progressionPick = Int((recipe.params.seed &* 0x9E37_79B9) >> 17) % 128
        let compositionStyle = MusicTheory.compositionStyle(
            moodId: recipe.params.moodId,
            seed: recipe.params.seed
        )
        let progression = MusicTheory.progression(
            for: recipe.preset,
            moodId: recipe.params.moodId,
            pick: progressionPick,
            style: compositionStyle
        )
        let mood = MoodPalette.from(
            moodId: recipe.params.moodId,
            brightness: recipe.params.brightness,
            energy: recipe.params.energy,
            density: recipe.params.density
        )
        let instrument = InstrumentPalette.from(instrumentId: recipe.params.instrumentId)
        let energy = recipe.params.energy
        let density = recipe.params.density
        let rhythm = recipe.params.rhythm
        let pitch = recipe.params.pitchSemitones
        // User pitch + mild seed transpose (mode preserved) so 別パターン shifts key family.
        let seedTranspose = MusicTheory.seedTransposeSemitones(seed: recipe.params.seed)
        let root = ((recipe.params.key.root + pitch + seedTranspose) % 12 + 12) % 12
        let key = MusicalKey(
            root: root,
            mode: MusicTheory.variationMode(
                base: recipe.params.key.mode,
                moodId: recipe.params.moodId,
                seed: recipe.params.seed
            )
        )

        // Rhythm slider drives drum subdivision / fills (audible sparse ↔ busy).
        let hatEvery: Int
        if rhythm < 0.34 {
            hatEvery = 4
        } else if rhythm < 0.67 {
            hatEvery = 2
        } else {
            hatEvery = 1
        }
        let kickEvery = rhythm < 0.4 ? 8 : 4
        let kickPattern = kickSteps(pick: Int(rng.unit() * 5), every: kickEvery)
        let snarePattern = snareSteps(pick: Int(rng.unit() * 4))
        let fillChance = 0.15 + 0.7 * rhythm
        let fillBars = Set((0..<bars).compactMap { bar -> Int? in
            (bar % 4 == 3 && rng.unit() > (1 - fillChance)) ? bar : nil
        })
        let drumAmpScale = 0.25 + 0.95 * rhythm

        let mute = min(0.95, max(0, mood.mute + instrument.muteBias))
        let chordOctave = max(2, min(6, mood.chordOctave + instrument.chordOctaveBias))
        let leadOctave = max(3, min(7, mood.leadOctave + instrument.leadOctaveBias))

        // Blend scene density with rhythm so busy rhythm also feeds melody activity.
        let melodyDensity = min(1, max(0, density * 0.45 + rhythm * 0.55))
        let sceneBias: MotifSceneBias
        switch recipe.preset {
        case .battleNormal: sceneBias = .battle
        case .menuMain: sceneBias = .menu
        }
        let melodyPlan = MelodyComposer.compose(
            bars: bars,
            progression: progression,
            density: melodyDensity,
            moodId: recipe.params.moodId,
            melodyEnabled: recipe.params.melody,
            melodyChanceScale: instrument.melodyChanceScale,
            seed: recipe.params.seed,
            sceneBias: sceneBias,
            style: compositionStyle,
            melodicCoherence: recipe.params.melodicCoherence
        )
        var melodyStarts: [Int: [MelodyNote]] = [:]
        for note in melodyPlan.notes {
            let key = note.bar * stepsPerBar + note.step
            melodyStarts[key, default: []].append(note)
        }
        let form = melodyPlan.form

        var chordIndex = 0
        for bar in 0..<bars {
            let section = form.sectionIndex(bar: bar, totalBars: bars)
            let arrange = MelodyComposer.arrangementScale(
                form: form,
                section: section,
                moodId: recipe.params.moodId
            )
            let chordDegree = progression[chordIndex % progression.count]
            chordIndex += 1
            let sectionLeadOctave = max(3, min(7, leadOctave + arrange.leadOctaveBias))
            let triad = MusicTheory.triadMIDI(
                root: key.root,
                chordDegree: chordDegree,
                octave: chordOctave,
                mode: key.mode
            )
            let bassRoot = MusicTheory.midi(
                root: key.root,
                degree: chordDegree,
                octave: max(1, chordOctave - 2),
                mode: key.mode
            )
            let isFill = fillBars.contains(bar) || {
                guard arrange.forceFill else { return false }
                let sectionLen = max(1, bars / form.sectionCount)
                return (bar + 1) % sectionLen == 0
            }()

            for step in 0..<stepsPerBar {
                let start = bar * framesPerBar + step * stepFrames
                let sectionDrum = drumAmpScale * arrange.drum

                if kickPattern.contains(step) {
                    addKick(
                        &samples,
                        at: start,
                        sampleRate: sampleRate,
                        amp: mood.drumKick * instrument.drumAmpScale * sectionDrum
                    )
                }
                if snarePattern.contains(step) || (isFill && step >= 12 && step % 2 == 0) {
                    addSnare(
                        &samples,
                        at: start,
                        sampleRate: sampleRate,
                        amp: mood.drumSnare * instrument.drumAmpScale * sectionDrum,
                        rng: &rng
                    )
                }
                let sectionHatEvery = arrange.chordSparse ? max(hatEvery, 4) : hatEvery
                if step % sectionHatEvery == 0 {
                    addHat(
                        &samples,
                        at: start,
                        sampleRate: sampleRate,
                        amp: mood.drumHat * instrument.drumAmpScale * instrument.hatAmpScale * sectionDrum,
                        rng: &rng
                    )
                }

                if step % 2 == 0 {
                    let walk: Int
                    if instrument.bassRootHeavy {
                        // Stay near the root; occasional fifth for motion.
                        walk = (step % 8 == 4) ? 4 : 0
                    } else {
                        walk = bassWalk(step: step, pick: Int(recipe.params.seed % 3))
                    }
                    let note = MusicTheory.midi(
                        root: key.root,
                        degree: chordDegree + walk,
                        octave: max(1, chordOctave - 2),
                        mode: key.mode
                    )
                    let midi = (!instrument.bassRootHeavy && step % 8 == 6) ? bassRoot + 7 : note
                    addTone(
                        &samples,
                        at: start,
                        sampleRate: sampleRate,
                        freq: MusicTheory.freq(midi: midi),
                        duration: Double(stepFrames * 2) / sampleRate * 0.85 * instrument.bassDurationScale,
                        amp: mood.bassAmp * instrument.bassAmpScale * (0.85 + 0.3 * energy),
                        shape: instrument.bassShape,
                        mute: mute,
                        envelope: instrument.bassEnv,
                        fm: instrument.bassFM,
                        tail: instrument.bassTail
                    )
                }

                let chordHits: Set<Int>
                if instrument.sustainChords || mute > 0.4 {
                    chordHits = arrange.chordSparse ? [0] : (rhythm < 0.35 ? [0] : [0, 8])
                } else if arrange.chordSparse {
                    chordHits = [0]
                } else if rhythm > 0.66 {
                    chordHits = [0, 4, 8, 12]
                } else if rhythm > 0.33 {
                    chordHits = [0, 8]
                } else {
                    chordHits = [0]
                }
                if chordHits.contains(step) {
                    let chordDur = secondsPerBeat * (instrument.sustainChords || mute > 0.4 ? 1.35 : 0.45)
                        * instrument.chordDurationScale
                    for (i, midi) in triad.enumerated() {
                        let upperScale = 1 - instrument.chordUpperAtten * Float(i) / Float(max(1, triad.count - 1))
                        let chordAmp = mood.chordAmp * instrument.chordAmpScale * upperScale
                            * (0.7 + 0.4 * rhythm)
                        if instrument.pianoVoice {
                            addPianoTone(
                                &samples,
                                at: start,
                                sampleRate: sampleRate,
                                freq: MusicTheory.freq(midi: midi),
                                duration: chordDur,
                                amp: chordAmp,
                                ringOut: instrument.chordTail.ringOut,
                                hammerScale: 0.55
                            )
                        } else {
                            addTone(
                                &samples,
                                at: start,
                                sampleRate: sampleRate,
                                freq: MusicTheory.freq(midi: midi),
                                duration: chordDur,
                                amp: chordAmp,
                                shape: instrument.chordShape,
                                mute: mute,
                                envelope: instrument.chordEnv,
                                fm: instrument.chordFM,
                                tail: instrument.chordTail
                            )
                        }
                    }
                }

                if let leadNotes = melodyStarts[bar * stepsPerBar + step] {
                    for lead in leadNotes {
                        let midi = MusicTheory.midi(
                            root: key.root,
                            degree: lead.degree,
                            octave: sectionLeadOctave,
                            mode: key.mode
                        )
                        let durSteps = Double(lead.durationSteps)
                        let leadDur = Double(stepFrames) / sampleRate * durSteps * 0.92
                            * instrument.leadDurationScale
                        let leadAmp = mood.leadAmp * instrument.leadAmpScale * lead.velocity
                        if instrument.pianoVoice {
                            addPianoTone(
                                &samples,
                                at: start,
                                sampleRate: sampleRate,
                                freq: MusicTheory.freq(midi: midi),
                                duration: leadDur,
                                amp: leadAmp,
                                ringOut: instrument.leadTail.ringOut,
                                hammerScale: 1.0
                            )
                        } else {
                            addTone(
                                &samples,
                                at: start,
                                sampleRate: sampleRate,
                                freq: MusicTheory.freq(midi: midi),
                                duration: leadDur,
                                amp: leadAmp,
                                shape: instrument.leadShape,
                                mute: mute * 0.7,
                                envelope: instrument.leadEnv,
                                fm: instrument.leadFM,
                                tail: instrument.leadTail
                            )
                        }
                    }
                }
            }
        }

        let cutoffHz = mood.filterCutoffHz * instrument.filterCutoffScale
        let reverbMix = min(0.5, max(0, mood.reverbMix + instrument.reverbMixBias))
        SpaceFX.applyLowpass(&samples, cutoffHz: cutoffHz, sampleRate: sampleRate)
        SpaceFX.applyShortReverb(
            &samples,
            mix: reverbMix,
            decay: mood.reverbDecay,
            sampleRate: sampleRate
        )

        applyLoopCrossfade(&samples, fadeSamples: max(1, Int(0.003 * sampleRate)))
        Mastering.apply(&samples, targetPeak: 0.86, drive: 1.05, fadeOutTail: false)

        return PCMBufferFactory().makeBuffer(
            frameCount: AVAudioFrameCount(samples.count),
            sampleRate: sampleRate
        ) { frame in
            samples[frame]
        }
    }

    private func kickSteps(pick: Int, every: Int) -> Set<Int> {
        switch pick % 5 {
        case 0: return Set(stride(from: 0, to: 16, by: every))
        case 1: return [0, 6, 8, 14]
        case 2: return [0, 4, 8, 10, 12]
        case 3: return [0, 3, 8, 11]
        default: return [0, 8]
        }
    }

    private func snareSteps(pick: Int) -> Set<Int> {
        switch pick % 4 {
        case 0: return [4, 12]
        case 1: return [4, 11, 12]
        case 2: return [4, 10, 12]
        default: return [4, 7, 12]
        }
    }

    private func bassWalk(step: Int, pick: Int) -> Int {
        switch pick {
        case 0: return (step % 8 == 4) ? 2 : 0
        case 1: return [0, 0, 2, 4, 0, 2, 3, 0][(step / 2) % 8]
        default: return (step % 4 == 2) ? 4 : 0
        }
    }

    private func addKick(_ samples: inout [Float], at start: Int, sampleRate: Double, amp: Float) {
        let length = Int(0.18 * sampleRate)
        var phase = 0.0
        for i in 0..<length {
            let idx = start + i
            guard idx < samples.count else { break }
            let t = Double(i) / sampleRate
            let env = Float(exp(-t * 18))
            let freq = 140.0 * exp(-t * 12) + 40
            phase += freq / sampleRate
            samples[idx] += SynthDSP.osc(.sine, phase: phase) * env * amp
        }
    }

    private func addSnare(
        _ samples: inout [Float],
        at start: Int,
        sampleRate: Double,
        amp: Float,
        rng: inout SeededGenerator
    ) {
        let length = Int(0.12 * sampleRate)
        var phase = 0.0
        for i in 0..<length {
            let idx = start + i
            guard idx < samples.count else { break }
            let t = Double(i) / sampleRate
            let env = Float(exp(-t * 28))
            phase += 180.0 / sampleRate
            let tone = SynthDSP.osc(.triangle, phase: phase) * 0.35
            let noise = rng.signedUnit() * 0.65
            samples[idx] += (tone + noise) * env * amp
        }
    }

    private func addHat(
        _ samples: inout [Float],
        at start: Int,
        sampleRate: Double,
        amp: Float,
        rng: inout SeededGenerator
    ) {
        let length = Int(0.04 * sampleRate)
        for i in 0..<length {
            let idx = start + i
            guard idx < samples.count else { break }
            let t = Double(i) / sampleRate
            let env = Float(exp(-t * 70))
            samples[idx] += rng.signedUnit() * env * amp
        }
    }

    /// Retro piano: hammer click/noise + additive partials with staggered exponential decay.
    private func addPianoTone(
        _ samples: inout [Float],
        at start: Int,
        sampleRate: Double,
        freq: Double,
        duration: Double,
        amp: Float,
        ringOut: Double,
        hammerScale: Float
    ) {
        let totalDuration = duration + max(0, ringOut)
        let length = max(1, Int(totalDuration * sampleRate))
        // Higher partials die faster — the core of a piano-like envelope.
        // Mild stretch on upper partials ≈ string inharmonicity (kept subtle for retro clarity).
        let partials: [(ratio: Double, level: Float, tau: Double)] = [
            (1.0, 1.00, 0.62),
            (2.0, 0.48, 0.32),
            (3.01, 0.22, 0.16),
            (4.02, 0.10, 0.09),
            (5.04, 0.04, 0.05),
        ]
        var phases = [Double](repeating: 0, count: partials.count)
        var clickPhase = 0.0
        let attack = 0.0012
        let bodyTau = 0.52

        for i in 0..<length {
            let idx = start + i
            guard idx < samples.count else { break }
            let t = Double(i) / sampleRate

            let gate: Float
            if t < attack {
                gate = Float(t / max(attack, 0.0001))
            } else {
                var level = Float(exp(-(t - attack) / bodyTau))
                let fadeStart = totalDuration * 0.86
                if t > fadeStart, totalDuration > fadeStart {
                    level *= Float(max(0, 1 - (t - fadeStart) / (totalDuration - fadeStart)))
                }
                gate = level
            }

            var body: Float = 0
            for p in partials.indices {
                phases[p] += freq * partials[p].ratio / sampleRate
                let pEnv = Float(exp(-t / partials[p].tau))
                body += SynthDSP.osc(.sine, phase: phases[p]) * partials[p].level * pEnv
            }
            body *= 0.42

            // Hammer: short noise + bright partial burst (key strike).
            var hammer: Float = 0
            if t < 0.014 {
                let hEnv = Float(exp(-t * 220))
                let noise = hashNoise(start &+ i)
                clickPhase += min(freq * 7.5, 6_500) / sampleRate
                let tick = SynthDSP.osc(.sine, phase: clickPhase) * 0.55
                hammer = (noise * 0.55 + tick) * hEnv * 0.4 * hammerScale
            }

            samples[idx] += (body + hammer) * gate * amp
        }
    }

    /// Deterministic bipolar noise for hammer strikes (seed-stable, no RNG plumbing).
    private func hashNoise(_ x: Int) -> Float {
        var v = UInt32(bitPattern: Int32(truncatingIfNeeded: x))
        v &+= 0x9E37_79B9
        v ^= v >> 16
        v &*= 0x85EB_CA6B
        v ^= v >> 13
        v &*= 0xC2B2_AE35
        v ^= v >> 16
        return Float(Int32(bitPattern: v) & 0x7FFF) / 16_383.5 - 1
    }

    private func addTone(
        _ samples: inout [Float],
        at start: Int,
        sampleRate: Double,
        freq: Double,
        duration: Double,
        amp: Float,
        shape: WaveShape,
        mute: Float,
        envelope: ADSR,
        fm: FMTone = .off,
        tail: ToneTail = .none
    ) {
        let ringOut = max(0, tail.ringOut)
        let totalDuration = duration + ringOut
        let length = max(1, Int(totalDuration * sampleRate))
        var carrierPhase = 0.0
        var modulatorPhase = 0.0
        let useRing = ringOut > 0.0001
        // High sustain + ringOut = held body then soft tail (bass). Low sustain = pluck ring (music box).
        let sustainRing = useRing && envelope.sustain >= 0.35
        let release = min(envelope.release, max(0.02, duration * 0.4))
        let env = ADSR(
            attack: min(envelope.attack, duration * 0.45),
            decay: envelope.decay,
            sustain: envelope.sustain,
            release: release
        )
        let useFM = fm.isActive
        let fmDecay = tail.fmDecay
        for i in 0..<length {
            let idx = start + i
            guard idx < samples.count else { break }
            let t = Double(i) / sampleRate
            carrierPhase += freq / sampleRate

            let e: Float
            if sustainRing {
                let atk = min(envelope.attack, max(0.0005, duration * 0.2))
                if t < atk {
                    e = atk > 0 ? Float(t / atk) : 1
                } else if t < duration {
                    let decayEnd = atk + max(0.001, envelope.decay)
                    if t < decayEnd {
                        let u = (t - atk) / max(0.001, envelope.decay)
                        e = 1 - (1 - envelope.sustain) * Float(u)
                    } else {
                        e = envelope.sustain
                    }
                } else {
                    let tau = max(0.08, envelope.release)
                    var level = envelope.sustain * Float(exp(-(t - duration) / tau))
                    let fadeStart = totalDuration * 0.9
                    if t > fadeStart, totalDuration > fadeStart {
                        level *= Float(max(0, 1 - (t - fadeStart) / (totalDuration - fadeStart)))
                    }
                    e = level
                }
            } else if useRing {
                // Short strike, then exponential ring (decay = tau). Clear overlapping tones.
                let atk = min(envelope.attack, max(0.0005, totalDuration * 0.08))
                if t < atk {
                    e = atk > 0 ? Float(t / atk) : 1
                } else {
                    let tau = max(0.05, envelope.decay)
                    var level = Float(exp(-(t - atk) / tau))
                    let fadeStart = totalDuration * 0.88
                    if t > fadeStart, totalDuration > fadeStart {
                        level *= Float(max(0, 1 - (t - fadeStart) / (totalDuration - fadeStart)))
                    }
                    e = level
                }
            } else {
                e = env.level(at: t, duration: duration)
            }

            var index = fm.index
            if useFM, fmDecay > 0.0001 {
                index *= exp(-t / fmDecay)
            }
            // As FM dies, lean toward pure sine so the ring stays clear.
            let fmRemain = useFM && fm.index > 0.0001 ? Float(min(1, index / fm.index)) : 0
            let softMute = min(1, mute + (1 - mute) * (1 - fmRemain) * (useFM && fmDecay > 0.0001 ? 0.85 : 0))

            let raw: Float
            if useFM, index > 0.0001 {
                modulatorPhase += freq * fm.ratio / sampleRate
                raw = SynthDSP.fmOsc(
                    shape: shape,
                    carrierPhase: carrierPhase,
                    modulatorPhase: modulatorPhase,
                    index: index
                )
            } else {
                raw = SynthDSP.osc(shape, phase: carrierPhase)
            }
            let soft = SynthDSP.osc(.sine, phase: carrierPhase)
            samples[idx] += SynthDSP.mix(raw, soft, t: softMute) * e * amp
        }
    }

    private func applyLoopCrossfade(_ samples: inout [Float], fadeSamples: Int) {
        let fade = min(samples.count / 8, max(1, fadeSamples))
        guard fade > 1, samples.count > fade * 2 else { return }
        for i in 0..<fade {
            let t = Float(i) / Float(fade - 1)
            let endIdx = samples.count - fade + i
            samples[endIdx] = samples[endIdx] * (1 - t) + samples[i] * t
        }
    }
}

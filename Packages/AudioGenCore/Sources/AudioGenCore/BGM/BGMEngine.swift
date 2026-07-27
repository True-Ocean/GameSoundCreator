import AVFoundation
import Foundation

public struct BGMEngine: Sendable {
    public init() {}

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

        let progressionPick = Int(rng.unit() * 64)
        let progression = MusicTheory.progression(
            for: recipe.preset,
            moodId: recipe.params.moodId,
            pick: progressionPick
        )
        let palette = MoodPalette.from(
            moodId: recipe.params.moodId,
            brightness: recipe.params.brightness,
            energy: recipe.params.energy,
            density: recipe.params.density
        )

        // Drum pattern family from seed (more variety).
        let kickPattern = kickSteps(pick: Int(rng.unit() * 5), every: rng.unit() > 0.5 ? 4 : 8)
        let snarePattern = snareSteps(pick: Int(rng.unit() * 4))
        let hatEvery = rng.unit() > 0.45 ? 2 : 4
        let fillBars = Set((0..<bars).compactMap { bar -> Int? in
            (bar % 4 == 3 && rng.unit() > 0.35) ? bar : nil
        })

        let energy = recipe.params.energy
        let density = recipe.params.density
        let key = recipe.params.key

        var chordIndex = 0
        for bar in 0..<bars {
            let chordDegree = progression[chordIndex % progression.count]
            chordIndex += 1
            let triad = MusicTheory.triadMIDI(
                root: key.root,
                chordDegree: chordDegree,
                octave: palette.chordOctave,
                mode: key.mode
            )
            let bassRoot = MusicTheory.midi(
                root: key.root,
                degree: chordDegree,
                octave: max(1, palette.chordOctave - 2),
                mode: key.mode
            )
            let isFill = fillBars.contains(bar)

            for step in 0..<stepsPerBar {
                let start = bar * framesPerBar + step * stepFrames

                if kickPattern.contains(step) {
                    addKick(&samples, at: start, sampleRate: sampleRate, amp: palette.drumKick)
                }
                if snarePattern.contains(step) || (isFill && step >= 12 && step % 2 == 0) {
                    addSnare(&samples, at: start, sampleRate: sampleRate, amp: palette.drumSnare, rng: &rng)
                }
                if step % hatEvery == 0 {
                    addHat(&samples, at: start, sampleRate: sampleRate, amp: palette.drumHat, rng: &rng)
                }

                if step % 2 == 0 {
                    let walk = bassWalk(step: step, pick: Int(recipe.params.seed % 3))
                    let note = MusicTheory.midi(
                        root: key.root,
                        degree: chordDegree + walk,
                        octave: max(1, palette.chordOctave - 2),
                        mode: key.mode
                    )
                    let midi = (step % 8 == 6) ? bassRoot + (key.mode == .major ? 7 : 7) : note
                    addTone(
                        &samples,
                        at: start,
                        sampleRate: sampleRate,
                        freq: MusicTheory.freq(midi: midi),
                        duration: Double(stepFrames * 2) / sampleRate * 0.85,
                        amp: palette.bassAmp * (0.85 + 0.3 * energy),
                        shape: palette.bassShape,
                        mute: palette.mute
                    )
                }

                // Chords: bright = arpeggio-ish more often; dark = held pads on downbeats
                let chordHits: Set<Int> = palette.mute > 0.4 ? [0, 8] : (density > 0.55 ? [0, 4, 8, 12] : [0, 8])
                if chordHits.contains(step) {
                    for (i, midi) in triad.enumerated() {
                        addTone(
                            &samples,
                            at: start,
                            sampleRate: sampleRate,
                            freq: MusicTheory.freq(midi: midi),
                            duration: secondsPerBeat * (palette.mute > 0.4 ? 1.1 : 0.45),
                            amp: palette.chordAmp / Float(1 + i) * (0.75 + 0.35 * density),
                            shape: palette.chordShape,
                            mute: palette.mute
                        )
                    }
                }

                if recipe.params.melody, step % 2 == 0, rng.unit() < palette.melodyChance {
                    let degreeSpread = palette.mute > 0.4 ? 3 : 6
                    let degree = chordDegree + Int(rng.unit() * Float(degreeSpread))
                    let midi = MusicTheory.midi(
                        root: key.root,
                        degree: degree,
                        octave: palette.leadOctave,
                        mode: key.mode
                    )
                    addTone(
                        &samples,
                        at: start,
                        sampleRate: sampleRate,
                        freq: MusicTheory.freq(midi: midi),
                        duration: Double(stepFrames) / sampleRate * (0.9 + Double(rng.unit())),
                        amp: palette.leadAmp,
                        shape: palette.leadShape,
                        mute: palette.mute * 0.7
                    )
                }
            }
        }

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

    private func addTone(
        _ samples: inout [Float],
        at start: Int,
        sampleRate: Double,
        freq: Double,
        duration: Double,
        amp: Float,
        shape: WaveShape,
        mute: Float
    ) {
        let length = max(1, Int(duration * sampleRate))
        var phase = 0.0
        let env = ADSR(attack: 0.01, decay: 0.05, sustain: 0.55, release: min(0.12, duration * 0.35))
        for i in 0..<length {
            let idx = start + i
            guard idx < samples.count else { break }
            let t = Double(i) / sampleRate
            phase += freq / sampleRate
            let e = env.level(at: t, duration: duration)
            let raw = SynthDSP.osc(shape, phase: phase)
            let soft = SynthDSP.osc(.sine, phase: phase)
            samples[idx] += SynthDSP.mix(raw, soft, t: mute) * e * amp
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

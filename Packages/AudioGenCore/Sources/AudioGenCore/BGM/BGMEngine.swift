import AVFoundation
import Foundation

public struct BGMEngine: Sendable {
    public init() {}

    public func generate(_ recipe: BGMRecipe) -> AVAudioPCMBuffer {
        let sampleRate = AudioFormatDefaults.sampleRate
        let bpm = Double(recipe.params.tempoBpm)
        let secondsPerBeat = 60.0 / bpm
        let stepsPerBar = 16
        // Exact grid: loop point lands on bar 1 beat 1 (no leftover samples).
        let stepFrames = max(1, Int((secondsPerBeat / 4.0 * sampleRate).rounded()))
        let framesPerBar = stepsPerBar * stepFrames
        // Snap to progression cycle (all current progressions are 4 bars).
        let progressionCycle = 4
        let bars = max(progressionCycle, (recipe.params.bars / progressionCycle) * progressionCycle)
        let frames = bars * framesPerBar

        var samples = [Float](repeating: 0, count: frames)
        var rng = SeededGenerator(seed: recipe.params.seed)

        let progressionPick = Int(rng.unit() * 4) % 4
        let progression = MusicTheory.progression(for: recipe.preset, pick: progressionPick)

        let energy = recipe.params.energy
        let density = recipe.params.density
        let key = recipe.params.key

        let kickEvery = rng.unit() > 0.5 ? 4 : 8
        let snareOn: Set<Int> = rng.unit() > 0.5 ? [4, 12] : [4, 11, 12]
        let hatDense = rng.unit() > 0.4

        var chordIndex = 0
        for bar in 0..<bars {
            let chordDegree = progression[chordIndex % progression.count]
            chordIndex += 1
            let triad = MusicTheory.triadMIDI(root: key.root, chordDegree: chordDegree, octave: 4, mode: key.mode)
            let bassRoot = MusicTheory.midi(root: key.root, degree: chordDegree, octave: 2, mode: key.mode)

            for step in 0..<stepsPerBar {
                let start = bar * framesPerBar + step * stepFrames

                if step % kickEvery == 0 {
                    addKick(&samples, at: start, sampleRate: sampleRate, amp: 0.35 + 0.45 * energy)
                }
                if snareOn.contains(step) {
                    addSnare(&samples, at: start, sampleRate: sampleRate, amp: 0.2 + 0.35 * energy, rng: &rng)
                }
                if hatDense ? (step % 2 == 0) : (step % 4 == 0) {
                    addHat(&samples, at: start, sampleRate: sampleRate, amp: 0.08 + 0.12 * energy, rng: &rng)
                }

                if step % 2 == 0 {
                    let walk = (step % 8 == 4) ? 2 : 0
                    let note = MusicTheory.midi(root: key.root, degree: chordDegree + walk, octave: 2, mode: key.mode)
                    let freq = MusicTheory.freq(midi: step % 8 == 6 ? bassRoot + 7 : note)
                    addTone(
                        &samples,
                        at: start,
                        sampleRate: sampleRate,
                        freq: freq,
                        duration: Double(stepFrames * 2) / sampleRate * 0.85,
                        amp: 0.18 + 0.22 * energy,
                        shape: .sine
                    )
                }

                if step == 0 || step == 8 {
                    for (i, midi) in triad.enumerated() {
                        let freq = MusicTheory.freq(midi: midi)
                        addTone(
                            &samples,
                            at: start,
                            sampleRate: sampleRate,
                            freq: freq,
                            duration: secondsPerBeat * (recipe.preset == .battleNormal ? 0.4 : 0.65),
                            amp: (0.08 + 0.1 * (1 - energy * 0.3)) / Float(1 + i) * (0.7 + 0.3 * density),
                            shape: recipe.preset == .menuMain ? .triangle : .saw
                        )
                    }
                }

                if recipe.params.melody, step % 2 == 0, rng.unit() < density * 0.55 {
                    let degree = chordDegree + Int(rng.unit() * 5)
                    let midi = MusicTheory.midi(root: key.root, degree: degree, octave: 5, mode: key.mode)
                    addTone(
                        &samples,
                        at: start,
                        sampleRate: sampleRate,
                        freq: MusicTheory.freq(midi: midi),
                        duration: Double(stepFrames) / sampleRate * (1.0 + Double(rng.unit()) * 0.8),
                        amp: 0.1 + 0.12 * density,
                        shape: .square
                    )
                }
            }
        }

        // Very short equal-power style blend at the seam only (keeps bar-line timing intact).
        applyLoopCrossfade(&samples, fadeSamples: max(1, Int(0.003 * sampleRate)))
        Mastering.apply(&samples, targetPeak: 0.86, drive: 1.05, fadeOutTail: false)

        return PCMBufferFactory().makeBuffer(
            frameCount: AVAudioFrameCount(samples.count),
            sampleRate: sampleRate
        ) { frame in
            samples[frame]
        }
    }

    // MARK: - Voices

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
        shape: WaveShape
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
            samples[idx] += SynthDSP.osc(shape, phase: phase) * e * amp
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

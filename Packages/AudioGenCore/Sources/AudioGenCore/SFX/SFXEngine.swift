import AVFoundation
import Foundation

public struct SFXEngine: Sendable {
    public init() {}

    public func generate(_ recipe: SFXRecipe) -> AVAudioPCMBuffer {
        let sampleRate = AudioFormatDefaults.sampleRate
        let frames = max(1, Int((Double(recipe.params.durationMs) / 1000.0) * sampleRate))
        var samples = [Float](repeating: 0, count: frames)
        var rng = SeededGenerator(seed: recipe.params.seed &+ UInt64(recipe.params.variation) &* 97_331)

        render(
            category: recipe.category,
            params: recipe.params,
            samples: &samples,
            sampleRate: sampleRate,
            rng: &rng
        )
        Mastering.apply(&samples, targetPeak: 0.82 + 0.12 * recipe.params.intensity)

        return PCMBufferFactory().makeBuffer(
            frameCount: AVAudioFrameCount(samples.count),
            sampleRate: sampleRate
        ) { frame in
            samples[frame]
        }
    }

    /// Seed-driven knobs that change the sound in an audible way (not just noise grain).
    private struct Pattern: Sendable {
        var pitchMul: Double
        var bright: Float
        var snap: Float
        var morph: Float
        var shapePick: Int
        var motifPick: Int

        static func draw(from rng: inout SeededGenerator) -> Pattern {
            Pattern(
                pitchMul: Double(rng.range(0.82, 1.28)),
                bright: rng.range(0.0, 1.0),
                snap: rng.range(0.0, 1.0),
                morph: rng.range(0.0, 1.0),
                shapePick: Int(rng.unit() * 4) % 4,
                motifPick: Int(rng.unit() * 4) % 4
            )
        }

        var shape: WaveShape {
            switch shapePick {
            case 0: return .sine
            case 1: return .triangle
            case 2: return .saw
            default: return .square
            }
        }
    }

    private func render(
        category: SFXCategory,
        params: SFXParams,
        samples: inout [Float],
        sampleRate: Double,
        rng: inout SeededGenerator
    ) {
        let pattern = Pattern.draw(from: &rng)
        let pitch = Double(params.pitch) * pattern.pitchMul
        let timbre = min(1, max(0, params.timbre * 0.55 + pattern.bright * 0.45))
        let intensity = params.intensity
        let duration = Double(samples.count) / sampleRate

        switch category {
        case .uiTap:
            renderClick(
                samples: &samples,
                sampleRate: sampleRate,
                freq: (1100 + 1400 * Double(pattern.bright)) * pitch,
                timbre: timbre,
                intensity: intensity,
                snap: pattern.snap,
                shape: pattern.shape,
                rng: &rng
            )
        case .uiConfirm:
            renderBlipUp(
                samples: &samples,
                sampleRate: sampleRate,
                base: (420 + 220 * Double(pattern.morph)) * pitch,
                sweep: 0.35 + 0.55 * Double(pattern.snap),
                timbre: timbre,
                intensity: intensity,
                shape: pattern.shape
            )
        case .uiCancel:
            renderBlipDown(
                samples: &samples,
                sampleRate: sampleRate,
                base: (360 + 200 * Double(pattern.morph)) * pitch,
                sweep: 0.25 + 0.5 * Double(pattern.snap),
                timbre: timbre,
                intensity: intensity,
                shape: pattern.shape
            )
        case .cardDraw:
            renderPaperNoise(
                samples: &samples,
                sampleRate: sampleRate,
                pitch: pitch,
                timbre: timbre,
                intensity: intensity,
                morph: pattern.morph,
                rng: &rng
            )
        case .cardPlay:
            renderWhooshHit(
                samples: &samples,
                sampleRate: sampleRate,
                pitch: pitch,
                timbre: timbre,
                intensity: intensity,
                hitAt: 0.25 + 0.5 * Double(pattern.morph),
                rng: &rng
            )
        case .attackLight:
            renderNoiseBurstDown(
                samples: &samples,
                sampleRate: sampleRate,
                pitch: pitch,
                timbre: timbre,
                intensity: intensity,
                heavy: false,
                startMul: 0.75 + 0.7 * Double(pattern.morph),
                decayMul: 0.7 + 0.9 * Double(pattern.snap),
                rng: &rng
            )
        case .attackHeavy:
            renderNoiseBurstDown(
                samples: &samples,
                sampleRate: sampleRate,
                pitch: pitch,
                timbre: timbre,
                intensity: intensity,
                heavy: true,
                startMul: 0.7 + 0.8 * Double(pattern.morph),
                decayMul: 0.65 + 0.9 * Double(pattern.snap),
                rng: &rng
            )
        case .skillCast:
            renderRisingSparkle(
                samples: &samples,
                sampleRate: sampleRate,
                pitch: pitch,
                timbre: timbre,
                intensity: intensity,
                rise: 0.6 + 1.1 * Double(pattern.morph),
                sparkle: pattern.bright,
                rng: &rng
            )
        case .damageTake:
            renderDamage(
                samples: &samples,
                sampleRate: sampleRate,
                pitch: pitch,
                timbre: timbre,
                intensity: intensity,
                drop: 0.35 + 0.55 * Double(pattern.snap),
                rng: &rng
            )
        case .heal:
            renderHealArp(
                samples: &samples,
                sampleRate: sampleRate,
                pitch: pitch,
                timbre: timbre,
                intensity: intensity,
                motif: pattern.motifPick,
                shape: pattern.shape
            )
        case .victory:
            renderFanfare(
                samples: &samples,
                sampleRate: sampleRate,
                duration: duration,
                pitch: pitch,
                timbre: timbre,
                intensity: intensity,
                ascending: true,
                motif: pattern.motifPick,
                shape: pattern.shape
            )
        case .defeat:
            renderFanfare(
                samples: &samples,
                sampleRate: sampleRate,
                duration: duration,
                pitch: pitch,
                timbre: timbre,
                intensity: intensity,
                ascending: false,
                motif: pattern.motifPick,
                shape: pattern.shape
            )
        }
    }

    // MARK: - Renders

    private func renderClick(
        samples: inout [Float],
        sampleRate: Double,
        freq: Double,
        timbre: Float,
        intensity: Float,
        snap: Float,
        shape: WaveShape,
        rng: inout SeededGenerator
    ) {
        let decay = 0.025 + 0.05 * Double(1 - snap)
        let env = ADSR(attack: 0.001, decay: decay, sustain: 0.04, release: 0.02 + 0.04 * Double(1 - snap))
        let duration = Double(samples.count) / sampleRate
        var phase = 0.0
        let noiseAmt = 0.1 + 0.7 * timbre
        for i in samples.indices {
            let t = Double(i) / sampleRate
            let e = env.level(at: t, duration: duration)
            phase += freq / sampleRate
            let tone = SynthDSP.osc(shape, phase: phase)
            let noise = rng.signedUnit() * noiseAmt
            samples[i] = (tone * (1 - noiseAmt * 0.65) + noise) * e * (0.35 + 0.55 * intensity)
        }
    }

    private func renderBlipUp(
        samples: inout [Float],
        sampleRate: Double,
        base: Double,
        sweep: Double,
        timbre: Float,
        intensity: Float,
        shape: WaveShape
    ) {
        let env = ADSR(attack: 0.004, decay: 0.05 + 0.04 * (1 - Double(timbre)), sustain: 0.18, release: 0.05)
        let duration = Double(samples.count) / sampleRate
        var phase = 0.0
        for i in samples.indices {
            let t = Double(i) / sampleRate
            let prog = t / max(duration, 0.0001)
            let freq = base * (1.0 + sweep * prog)
            phase += freq / sampleRate
            let e = env.level(at: t, duration: duration)
            samples[i] = SynthDSP.osc(shape, phase: phase) * e * (0.3 + 0.5 * intensity)
        }
    }

    private func renderBlipDown(
        samples: inout [Float],
        sampleRate: Double,
        base: Double,
        sweep: Double,
        timbre: Float,
        intensity: Float,
        shape: WaveShape
    ) {
        let env = ADSR(attack: 0.004, decay: 0.05, sustain: 0.14, release: 0.05 + 0.04 * Double(1 - timbre))
        let duration = Double(samples.count) / sampleRate
        var phase = 0.0
        for i in samples.indices {
            let t = Double(i) / sampleRate
            let prog = t / max(duration, 0.0001)
            let freq = base * (1.0 - sweep * prog)
            phase += freq / sampleRate
            let e = env.level(at: t, duration: duration)
            samples[i] = SynthDSP.osc(shape, phase: phase) * e * (0.28 + 0.45 * intensity)
        }
    }

    private func renderPaperNoise(
        samples: inout [Float],
        sampleRate: Double,
        pitch: Double,
        timbre: Float,
        intensity: Float,
        morph: Float,
        rng: inout SeededGenerator
    ) {
        let duration = Double(samples.count) / sampleRate
        let env = ADSR(attack: 0.008 + 0.02 * Double(1 - morph), decay: 0.1, sustain: 0.2 + 0.2 * morph, release: 0.08)
        var hp: Float = 0
        var phase = 0.0
        let sweepStart = (650.0 + 700.0 * Double(morph)) * pitch
        for i in samples.indices {
            let t = Double(i) / sampleRate
            let prog = Float(t / max(duration, 0.0001))
            let n = rng.signedUnit()
            hp = SynthDSP.mix(hp, n, t: 0.2 + 0.5 * timbre)
            let filtered = n - hp * 0.85
            phase += (sweepStart * (1.0 - 0.25 * Double(prog) - 0.35 * Double(morph) * Double(prog))) / sampleRate
            let swoosh = SynthDSP.osc(.sine, phase: phase) * (0.12 + 0.35 * (1 - timbre))
            let e = env.level(at: t, duration: duration)
            samples[i] = (filtered * (0.5 + 0.4 * timbre) + swoosh) * e * (0.35 + 0.5 * intensity)
        }
    }

    private func renderWhooshHit(
        samples: inout [Float],
        sampleRate: Double,
        pitch: Double,
        timbre: Float,
        intensity: Float,
        hitAt: Double,
        rng: inout SeededGenerator
    ) {
        let duration = Double(samples.count) / sampleRate
        let hitTime = duration * min(0.85, max(0.15, hitAt))
        var phase = 0.0
        let thumpFreq = (160.0 + 140.0 * pitch)
        for i in samples.indices {
            let t = Double(i) / sampleRate
            let whooshEnv = Float(exp(-2.5 * t / duration)) * (0.35 + 0.5 * timbre)
            let noise = rng.signedUnit() * whooshEnv
            let hitDist = abs(t - hitTime)
            let hit = Float(exp(-hitDist * (50 + 60 * Double(intensity)))) * (0.45 + 0.45 * intensity)
            phase += thumpFreq / sampleRate
            let thump = SynthDSP.osc(.sine, phase: phase) * hit
            samples[i] = noise * 0.55 + thump
        }
    }

    private func renderNoiseBurstDown(
        samples: inout [Float],
        sampleRate: Double,
        pitch: Double,
        timbre: Float,
        intensity: Float,
        heavy: Bool,
        startMul: Double,
        decayMul: Double,
        rng: inout SeededGenerator
    ) {
        let duration = Double(samples.count) / sampleRate
        var phase = 0.0
        let startFreq = (heavy ? 280.0 : 520.0) * pitch * startMul
        let endFreq = (heavy ? 55.0 : 120.0) * pitch * (0.8 + 0.4 * (2 - startMul))
        let bodyMix: Float = heavy ? 0.65 : 0.4
        let decay = (heavy ? 2.0 : 3.6) * decayMul
        for i in samples.indices {
            let t = Double(i) / sampleRate
            let prog = t / max(duration, 0.0001)
            let freq = startFreq + (endFreq - startFreq) * prog
            phase += freq / sampleRate
            let env = Float(exp(-decay * prog))
            let tone = SynthDSP.osc(heavy ? .sine : .saw, phase: phase)
            let noise = rng.signedUnit() * (0.25 + 0.55 * timbre)
            let drive = 1 + intensity * (heavy ? 2.2 : 1.2)
            let noiseMix = 1 - bodyMix * 0.5
            let mixedInput = tone * bodyMix + noise * noiseMix
            let mixed = SynthDSP.softClip(mixedInput, drive: drive)
            samples[i] = mixed * env * (0.4 + 0.5 * intensity)
        }
    }

    private func renderRisingSparkle(
        samples: inout [Float],
        sampleRate: Double,
        pitch: Double,
        timbre: Float,
        intensity: Float,
        rise: Double,
        sparkle: Float,
        rng: inout SeededGenerator
    ) {
        let duration = Double(samples.count) / sampleRate
        var phase1 = 0.0
        var phase2 = 0.2
        let f0 = (240.0 + 180.0 * Double(sparkle)) * pitch
        for i in samples.indices {
            let t = Double(i) / sampleRate
            let prog = t / max(duration, 0.0001)
            let f1 = f0 + 900.0 * rise * prog * pitch
            let f2 = f0 * 1.8 + 1400.0 * rise * prog * pitch
            phase1 += f1 / sampleRate
            phase2 += f2 / sampleRate
            let env = Float(sin(Double.pi * min(1, prog * 1.05)))
            let sparkleAmt = rng.signedUnit() * (0.06 + 0.28 * sparkle) * env
            let tone = SynthDSP.osc(.sine, phase: phase1) * 0.55
                + SynthDSP.osc(.triangle, phase: phase2) * (0.25 + 0.2 * timbre)
            samples[i] = (tone + sparkleAmt) * env * (0.35 + 0.5 * intensity)
        }
    }

    private func renderDamage(
        samples: inout [Float],
        sampleRate: Double,
        pitch: Double,
        timbre: Float,
        intensity: Float,
        drop: Double,
        rng: inout SeededGenerator
    ) {
        let duration = Double(samples.count) / sampleRate
        var phase = 0.0
        let start = (300.0 + 160.0 * drop) * pitch
        for i in samples.indices {
            let t = Double(i) / sampleRate
            let prog = t / max(duration, 0.0001)
            let freq = start * (1.0 - 0.55 * drop * prog)
            phase += freq / sampleRate
            let env = Float(exp(-(3.5 + 3.0 * drop) * prog))
            let tone = SynthDSP.osc(.saw, phase: phase)
            let grit = rng.signedUnit() * (0.2 + 0.5 * timbre)
            samples[i] = SynthDSP.softClip(tone * 0.55 + grit, drive: 1.5 + intensity) * env * (0.4 + 0.5 * intensity)
        }
    }

    private func renderHealArp(
        samples: inout [Float],
        sampleRate: Double,
        pitch: Double,
        timbre: Float,
        intensity: Float,
        motif: Int,
        shape: WaveShape
    ) {
        let duration = Double(samples.count) / sampleRate
        let motifs: [[Double]] = [
            [523.25, 659.25, 783.99, 1046.5],
            [392.0, 523.25, 659.25, 783.99],
            [659.25, 783.99, 1046.5, 1318.5],
            [523.25, 783.99, 659.25, 1046.5],
        ]
        let notes = motifs[motif % motifs.count].map { $0 * pitch }
        let noteLen = duration / Double(notes.count)
        for i in samples.indices {
            let t = Double(i) / sampleRate
            let idx = min(notes.count - 1, Int(t / max(noteLen, 0.0001)))
            let local = t - Double(idx) * noteLen
            let freq = notes[idx]
            let phase = freq * local
            let env = Float(exp(-local / max(noteLen * (0.35 + 0.25 * Double(timbre)), 0.01)))
            samples[i] = SynthDSP.osc(shape, phase: phase) * env * (0.28 + 0.45 * intensity)
        }
    }

    private func renderFanfare(
        samples: inout [Float],
        sampleRate: Double,
        duration: Double,
        pitch: Double,
        timbre: Float,
        intensity: Float,
        ascending: Bool,
        motif: Int,
        shape: WaveShape
    ) {
        let up: [[Double]] = [
            [392.0, 523.25, 659.25, 783.99],
            [440.0, 554.37, 659.25, 880.0],
            [349.23, 523.25, 698.46, 880.0],
            [523.25, 659.25, 783.99, 1046.5],
        ]
        let down: [[Double]] = [
            [392.0, 349.23, 293.66, 220.0],
            [440.0, 349.23, 293.66, 246.94],
            [523.25, 392.0, 329.63, 261.63],
            [349.23, 293.66, 246.94, 196.0],
        ]
        let table = ascending ? up : down
        let notes = table[motif % table.count].map { $0 * pitch }
        let noteLen = duration / Double(notes.count)
        for i in samples.indices {
            let t = Double(i) / sampleRate
            let idx = min(notes.count - 1, Int(t / max(noteLen, 0.0001)))
            let local = t - Double(idx) * noteLen
            let freq = notes[idx]
            let phase = freq * local
            let fifth = freq * 1.5 * local
            let env = ADSR(attack: 0.01, decay: 0.05, sustain: 0.55, release: noteLen * 0.35)
                .level(at: local, duration: noteLen)
            let tone = SynthDSP.osc(shape, phase: phase) * 0.65
                + SynthDSP.osc(.sine, phase: fifth) * (0.15 + 0.2 * timbre)
            let darken: Float = ascending ? 1 : 0.7
            samples[i] = tone * env * darken * (0.3 + 0.45 * intensity)
        }
    }
}

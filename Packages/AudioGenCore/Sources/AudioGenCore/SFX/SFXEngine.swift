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
        layerRepeatedHits(count: recipe.params.count, samples: &samples)
        Mastering.apply(&samples, targetPeak: 0.82 + 0.12 * recipe.params.intensity)

        return PCMBufferFactory().makeBuffer(
            frameCount: AVAudioFrameCount(samples.count),
            sampleRate: sampleRate
        ) { frame in
            samples[frame]
        }
    }

    /// Overlay delayed copies so 「音数」 increases audible hits within the same duration.
    private func layerRepeatedHits(count: Int, samples: inout [Float]) {
        let hits = min(8, max(1, count))
        guard hits > 1, samples.count > 8 else { return }
        let base = samples
        let span = Double(samples.count) * 0.55
        for i in 1..<hits {
            let offset = Int(span * Double(i) / Double(hits))
            let amp = 0.7 / Float(i + 1) + 0.25
            var j = offset
            while j < samples.count {
                samples[j] += base[j - offset] * amp
                j += 1
            }
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
                samples: &samples, sampleRate: sampleRate,
                freq: (1100 + 1400 * Double(pattern.bright)) * pitch,
                timbre: timbre, intensity: intensity, snap: pattern.snap,
                shape: pattern.shape, rng: &rng
            )
        case .uiConfirm:
            renderBlipUp(
                samples: &samples, sampleRate: sampleRate,
                base: (420 + 220 * Double(pattern.morph)) * pitch,
                sweep: 0.35 + 0.55 * Double(pattern.snap),
                timbre: timbre, intensity: intensity, shape: pattern.shape
            )
        case .uiCancel:
            renderBlipDown(
                samples: &samples, sampleRate: sampleRate,
                base: (360 + 200 * Double(pattern.morph)) * pitch,
                sweep: 0.25 + 0.5 * Double(pattern.snap),
                timbre: timbre, intensity: intensity, shape: pattern.shape
            )
        case .uiBack:
            renderTwoToneDown(
                samples: &samples, sampleRate: sampleRate,
                high: (480 + 120 * Double(pattern.morph)) * pitch,
                low: (280 + 80 * Double(pattern.snap)) * pitch,
                timbre: timbre, intensity: intensity * 0.85, shape: pattern.shape
            )
        case .uiSwipe:
            renderNoiseSweep(
                samples: &samples, sampleRate: sampleRate,
                startFreq: (900 + 600 * Double(pattern.bright)) * pitch,
                endFreq: (280 + 200 * Double(pattern.morph)) * pitch,
                timbre: timbre, intensity: intensity, rng: &rng
            )
        case .uiDoubleTap:
            renderDoubleClick(
                samples: &samples, sampleRate: sampleRate,
                freq: (1000 + 900 * Double(pattern.bright)) * pitch,
                gap: 0.04 + 0.05 * Double(pattern.morph),
                timbre: timbre, intensity: intensity, shape: pattern.shape, rng: &rng
            )
        case .cardDraw:
            renderPaperNoise(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity,
                morph: pattern.morph, rng: &rng
            )
        case .cardPlay:
            renderWhooshHit(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity,
                hitAt: 0.25 + 0.5 * Double(pattern.morph), rng: &rng
            )
        case .cardShuffle:
            renderCardShuffle(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity,
                flutter: 6 + pattern.motifPick * 2, rng: &rng
            )
        case .cardFlip:
            renderCardFlip(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity,
                snap: pattern.snap, rng: &rng
            )
        case .cardDiscard:
            renderCardDiscard(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity, rng: &rng
            )
        case .attackLight:
            renderNoiseBurstDown(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity, heavy: false,
                startMul: 0.75 + 0.7 * Double(pattern.morph),
                decayMul: 0.7 + 0.9 * Double(pattern.snap), rng: &rng
            )
        case .attackHeavy:
            renderNoiseBurstDown(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity, heavy: true,
                startMul: 0.7 + 0.8 * Double(pattern.morph),
                decayMul: 0.65 + 0.9 * Double(pattern.snap), rng: &rng
            )
        case .attackSlash:
            renderSlash(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity,
                whip: 0.55 + 0.4 * Double(pattern.snap), rng: &rng
            )
        case .attackBash:
            renderBash(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity,
                thump: 0.5 + 0.4 * Double(pattern.morph), rng: &rng
            )
        case .attackBreak:
            renderBreak(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity,
                crackle: pattern.bright, rng: &rng
            )
        case .damageTake:
            renderDamage(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity,
                drop: 0.35 + 0.55 * Double(pattern.snap), rng: &rng
            )
        case .defend:
            renderDefendClang(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity,
                ring: 0.4 + 0.5 * Double(pattern.bright), shape: pattern.shape
            )
        case .skillCast:
            renderRisingSparkle(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity,
                rise: 0.6 + 1.1 * Double(pattern.morph),
                sparkle: pattern.bright, rng: &rng
            )
        case .magicFire:
            renderMagicFire(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity,
                roar: pattern.morph, rng: &rng
            )
        case .magicIce:
            renderMagicIce(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity,
                shimmer: pattern.bright, motif: pattern.motifPick
            )
        case .magicPoison:
            renderMagicPoison(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity,
                bubble: 4 + pattern.motifPick * 2, rng: &rng
            )
        case .heal:
            renderHealArp(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity,
                motif: pattern.motifPick, shape: pattern.shape
            )
        case .moveWalk:
            renderFootsteps(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity * 0.75,
                steps: 2, gap: 0.09 + 0.04 * Double(pattern.morph), rng: &rng
            )
        case .moveRun:
            renderFootsteps(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch * 1.15, timbre: timbre, intensity: intensity * 0.7,
                steps: 3, gap: 0.045 + 0.02 * Double(pattern.morph), rng: &rng
            )
        case .moveFly:
            renderFlyWhoosh(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity,
                flutter: pattern.snap, rng: &rng
            )
        case .gachaSpin:
            renderGachaSpin(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity,
                ticks: 5 + pattern.motifPick, rng: &rng
            )
        case .gachaRare:
            renderGachaRare(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity,
                motif: pattern.motifPick, sparkle: pattern.bright, rng: &rng
            )
        case .victory:
            renderFanfare(
                samples: &samples, sampleRate: sampleRate, duration: duration,
                pitch: pitch, timbre: timbre, intensity: intensity,
                ascending: true, motif: pattern.motifPick, shape: pattern.shape
            )
        case .defeat:
            renderFanfare(
                samples: &samples, sampleRate: sampleRate, duration: duration,
                pitch: pitch, timbre: timbre, intensity: intensity,
                ascending: false, motif: pattern.motifPick, shape: pattern.shape
            )
        }
    }

    // MARK: - UI

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

    private func renderTwoToneDown(
        samples: inout [Float],
        sampleRate: Double,
        high: Double,
        low: Double,
        timbre: Float,
        intensity: Float,
        shape: WaveShape
    ) {
        let duration = Double(samples.count) / sampleRate
        let split = duration * 0.42
        for i in samples.indices {
            let t = Double(i) / sampleRate
            let freq = t < split ? high : low
            let local = t < split ? t : t - split
            let localDur = t < split ? split : duration - split
            let phase = freq * local
            let env = ADSR(attack: 0.004, decay: 0.04, sustain: 0.2, release: localDur * 0.4)
                .level(at: local, duration: localDur)
            let soft = SynthDSP.osc(shape, phase: phase) * 0.7
                + SynthDSP.osc(.sine, phase: phase * 2) * (0.15 + 0.15 * timbre)
            samples[i] = soft * env * (0.28 + 0.4 * intensity)
        }
    }

    private func renderNoiseSweep(
        samples: inout [Float],
        sampleRate: Double,
        startFreq: Double,
        endFreq: Double,
        timbre: Float,
        intensity: Float,
        rng: inout SeededGenerator
    ) {
        let duration = Double(samples.count) / sampleRate
        var hp: Float = 0
        var phase = 0.0
        for i in samples.indices {
            let t = Double(i) / sampleRate
            let prog = t / max(duration, 0.0001)
            let freq = startFreq + (endFreq - startFreq) * prog
            phase += freq / sampleRate
            let n = rng.signedUnit()
            hp = SynthDSP.mix(hp, n, t: 0.15 + 0.45 * timbre)
            let band = n - hp * 0.9
            let tone = SynthDSP.osc(.sine, phase: phase) * (0.15 + 0.2 * (1 - timbre))
            let env = Float(sin(Double.pi * min(1, prog * 1.05)))
            samples[i] = (band * (0.55 + 0.35 * timbre) + tone) * env * (0.32 + 0.45 * intensity)
        }
    }

    private func renderDoubleClick(
        samples: inout [Float],
        sampleRate: Double,
        freq: Double,
        gap: Double,
        timbre: Float,
        intensity: Float,
        shape: WaveShape,
        rng: inout SeededGenerator
    ) {
        let duration = Double(samples.count) / sampleRate
        let clickDur = min(0.05, duration * 0.28)
        let times = [0.0, gap]
        for i in samples.indices {
            let t = Double(i) / sampleRate
            var sum: Float = 0
            for start in times {
                let local = t - start
                guard local >= 0, local < clickDur * 2 else { continue }
                let phase = freq * local
                let env = Float(exp(-local / max(clickDur * 0.55, 0.005)))
                let noise = rng.signedUnit() * (0.15 + 0.35 * timbre)
                sum += (SynthDSP.osc(shape, phase: phase) * 0.7 + noise) * env
            }
            samples[i] = sum * (0.35 + 0.5 * intensity)
        }
    }

    // MARK: - Card

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
        let thumpFreq = 160.0 + 140.0 * pitch
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

    private func renderCardShuffle(
        samples: inout [Float],
        sampleRate: Double,
        pitch: Double,
        timbre: Float,
        intensity: Float,
        flutter: Int,
        rng: inout SeededGenerator
    ) {
        let duration = Double(samples.count) / sampleRate
        let count = max(4, flutter)
        for i in samples.indices {
            let t = Double(i) / sampleRate
            let prog = t / max(duration, 0.0001)
            // Accelerating flutter of paper bursts.
            let rate = Double(count) * (0.7 + 1.4 * prog)
            let pulse = abs(sin(prog * Double.pi * rate))
            let burst = Float(pow(pulse, 4 + 6 * Double(1 - timbre)))
            var hp: Float = 0
            let n = rng.signedUnit()
            hp = SynthDSP.mix(hp, n, t: 0.25)
            let paper = (n - hp * 0.8) * burst
            let tickFreq = (700 + 900 * prog) * pitch
            let tick = SynthDSP.osc(.square, phase: tickFreq * t) * burst * (0.08 + 0.12 * (1 - timbre))
            let env = Float(sin(Double.pi * min(1, prog * 1.02)))
            samples[i] = (paper * (0.55 + 0.35 * timbre) + tick) * env * (0.35 + 0.45 * intensity)
        }
    }

    private func renderCardFlip(
        samples: inout [Float],
        sampleRate: Double,
        pitch: Double,
        timbre: Float,
        intensity: Float,
        snap: Float,
        rng: inout SeededGenerator
    ) {
        let duration = Double(samples.count) / sampleRate
        let snapAt = duration * (0.18 + 0.2 * Double(snap))
        var phase = 0.0
        for i in samples.indices {
            let t = Double(i) / sampleRate
            let whoosh = Float(exp(-4.5 * t / duration)) * rng.signedUnit() * (0.25 + 0.4 * timbre)
            let dist = abs(t - snapAt)
            let click = Float(exp(-dist * 90)) * (0.55 + 0.35 * intensity)
            phase += (1400 * pitch) / sampleRate
            let tip = SynthDSP.osc(.triangle, phase: phase) * click
            samples[i] = whoosh * 0.7 + tip
        }
    }

    private func renderCardDiscard(
        samples: inout [Float],
        sampleRate: Double,
        pitch: Double,
        timbre: Float,
        intensity: Float,
        rng: inout SeededGenerator
    ) {
        let duration = Double(samples.count) / sampleRate
        var phase = 0.0
        let thumpF = 90.0 * pitch
        for i in samples.indices {
            let t = Double(i) / sampleRate
            let prog = t / max(duration, 0.0001)
            phase += thumpF / sampleRate
            let thump = SynthDSP.osc(.sine, phase: phase) * Float(exp(-6 * prog))
            let scrape = rng.signedUnit() * Float(exp(-3.2 * prog)) * (0.2 + 0.45 * timbre)
            samples[i] = (thump * 0.65 + scrape) * (0.35 + 0.45 * intensity)
        }
    }

    // MARK: - Attack / combat

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

    private func renderSlash(
        samples: inout [Float],
        sampleRate: Double,
        pitch: Double,
        timbre: Float,
        intensity: Float,
        whip: Double,
        rng: inout SeededGenerator
    ) {
        let duration = Double(samples.count) / sampleRate
        var phase = 0.0
        let f0 = (1800 + 1200 * whip) * pitch
        for i in samples.indices {
            let t = Double(i) / sampleRate
            let prog = t / max(duration, 0.0001)
            // Fast downward metallic whip, little low body.
            let freq = f0 * (1.0 - 0.75 * prog)
            phase += freq / sampleRate
            let env = Float(exp(-(5.5 + 4 * whip) * prog))
            let blade = SynthDSP.osc(.saw, phase: phase) * 0.45
                + SynthDSP.osc(.square, phase: phase * 1.01) * 0.2
            let air = rng.signedUnit() * (0.15 + 0.4 * timbre) * env
            samples[i] = SynthDSP.softClip(blade + air, drive: 1.3 + intensity) * env * (0.4 + 0.45 * intensity)
        }
    }

    private func renderBash(
        samples: inout [Float],
        sampleRate: Double,
        pitch: Double,
        timbre: Float,
        intensity: Float,
        thump: Double,
        rng: inout SeededGenerator
    ) {
        let duration = Double(samples.count) / sampleRate
        var phase = 0.0
        let f0 = (90 + 70 * thump) * pitch
        for i in samples.indices {
            let t = Double(i) / sampleRate
            let prog = t / max(duration, 0.0001)
            let freq = f0 * (1.0 - 0.55 * prog)
            phase += freq / sampleRate
            let env = Float(exp(-(2.2 + 1.5 * thump) * prog))
            let body = SynthDSP.osc(.sine, phase: phase)
            let knock = SynthDSP.osc(.triangle, phase: phase * 2.3) * (0.15 + 0.2 * timbre)
            let grit = rng.signedUnit() * (0.08 + 0.2 * timbre) * env
            samples[i] = SynthDSP.softClip(body * 0.7 + knock + grit, drive: 1.8 + intensity) * env * (0.45 + 0.45 * intensity)
        }
    }

    private func renderBreak(
        samples: inout [Float],
        sampleRate: Double,
        pitch: Double,
        timbre: Float,
        intensity: Float,
        crackle: Float,
        rng: inout SeededGenerator
    ) {
        let duration = Double(samples.count) / sampleRate
        var phase = 0.0
        let crackAt = duration * 0.12
        for i in samples.indices {
            let t = Double(i) / sampleRate
            let prog = t / max(duration, 0.0001)
            let crackDist = abs(t - crackAt)
            let crack = Float(exp(-crackDist * 70)) * (0.7 + 0.3 * intensity)
            phase += (220 * pitch) / sampleRate
            let body = SynthDSP.osc(.sine, phase: phase) * crack * 0.5
            // Debris: sparse high noise after crack.
            let debrisGate = prog > 0.12 ? Float(exp(-2.5 * (prog - 0.12))) : 0
            let debris = rng.signedUnit() * debrisGate * (0.25 + 0.55 * crackle)
            let shard = SynthDSP.osc(.square, phase: (900 + 1400 * Double(crackle)) * pitch * t)
                * debrisGate * (0.08 + 0.12 * timbre)
            samples[i] = SynthDSP.softClip(body + debris + shard, drive: 1.6 + intensity) * (0.4 + 0.45 * intensity)
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

    private func renderDefendClang(
        samples: inout [Float],
        sampleRate: Double,
        pitch: Double,
        timbre: Float,
        intensity: Float,
        ring: Double,
        shape: WaveShape
    ) {
        let duration = Double(samples.count) / sampleRate
        var p1 = 0.0
        var p2 = 0.1
        let f1 = (520 + 280 * ring) * pitch
        let f2 = f1 * 1.498 // near perfect fifth metallic
        for i in samples.indices {
            let t = Double(i) / sampleRate
            let prog = t / max(duration, 0.0001)
            p1 += f1 / sampleRate
            p2 += f2 / sampleRate
            let env = Float(exp(-(2.8 + 2.0 * (1 - ring)) * prog))
            let clang = SynthDSP.osc(shape, phase: p1) * 0.55
                + SynthDSP.osc(.sine, phase: p2) * (0.25 + 0.25 * timbre)
            let attack = Float(exp(-prog * 40)) * 0.35
            samples[i] = (clang + SynthDSP.osc(.square, phase: p1 * 2) * attack * 0.15)
                * env * (0.35 + 0.45 * intensity)
        }
    }

    // MARK: - Magic

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

    private func renderMagicFire(
        samples: inout [Float],
        sampleRate: Double,
        pitch: Double,
        timbre: Float,
        intensity: Float,
        roar: Float,
        rng: inout SeededGenerator
    ) {
        let duration = Double(samples.count) / sampleRate
        var phase = 0.0
        var lp: Float = 0
        let f0 = (120 + 80 * Double(roar)) * pitch
        for i in samples.indices {
            let t = Double(i) / sampleRate
            let prog = t / max(duration, 0.0001)
            let freq = f0 * (1.0 + 1.8 * prog)
            phase += freq / sampleRate
            let n = rng.signedUnit()
            lp = SynthDSP.mix(lp, n, t: 0.08 + 0.2 * timbre) // low, crackly
            let crackle = abs(n) > (0.55 - 0.2 * roar) ? n * 0.55 : n * 0.12
            let body = SynthDSP.osc(.saw, phase: phase) * (0.25 + 0.25 * roar)
            let env = Float(sin(Double.pi * min(1, prog * 1.08)))
            samples[i] = SynthDSP.softClip(lp * 0.55 + crackle * 0.45 + body, drive: 1.4 + intensity)
                * env * (0.38 + 0.45 * intensity)
        }
    }

    private func renderMagicIce(
        samples: inout [Float],
        sampleRate: Double,
        pitch: Double,
        timbre: Float,
        intensity: Float,
        shimmer: Float,
        motif: Int
    ) {
        let duration = Double(samples.count) / sampleRate
        let freqs: [[Double]] = [
            [880, 1320, 1760, 2200],
            [988, 1480, 1976, 2637],
            [1046, 1568, 2093, 2637],
            [784, 1175, 1568, 2093],
        ]
        let notes = freqs[motif % freqs.count].map { $0 * pitch }
        let noteLen = duration / Double(notes.count)
        for i in samples.indices {
            let t = Double(i) / sampleRate
            let idx = min(notes.count - 1, Int(t / max(noteLen, 0.0001)))
            let local = t - Double(idx) * noteLen
            let freq = notes[idx]
            let phase = freq * local
            let env = Float(exp(-local / max(noteLen * 0.45, 0.01)))
            let glass = SynthDSP.osc(.sine, phase: phase)
                + SynthDSP.osc(.triangle, phase: phase * 2.01) * (0.2 + 0.25 * shimmer)
                + SynthDSP.osc(.sine, phase: phase * 3.02) * (0.08 + 0.12 * timbre)
            samples[i] = glass * env * (0.28 + 0.4 * intensity)
        }
    }

    private func renderMagicPoison(
        samples: inout [Float],
        sampleRate: Double,
        pitch: Double,
        timbre: Float,
        intensity: Float,
        bubble: Int,
        rng: inout SeededGenerator
    ) {
        let duration = Double(samples.count) / sampleRate
        var phase = 0.0
        let base = (140 + 60 * Double(bubble % 3)) * pitch
        for i in samples.indices {
            let t = Double(i) / sampleRate
            let prog = t / max(duration, 0.0001)
            let wobble = 1.0 + 0.35 * sin(t * Double.pi * 2 * Double(bubble))
            phase += (base * wobble) / sampleRate
            let env = Float(sin(Double.pi * min(1, prog * 1.05)))
            let tone = SynthDSP.osc(.triangle, phase: phase) * 0.45
            // Occasional bubble pops.
            let popGate = abs(sin(t * 18 + Double(bubble))) > 0.92 ? Float(1) : Float(0)
            let pop = rng.signedUnit() * popGate * (0.2 + 0.35 * timbre)
            let murk = SynthDSP.osc(.saw, phase: phase * 0.5) * (0.12 + 0.15 * timbre) * env
            samples[i] = (tone + pop + murk) * env * (0.32 + 0.4 * intensity)
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

    // MARK: - Movement

    private func renderFootsteps(
        samples: inout [Float],
        sampleRate: Double,
        pitch: Double,
        timbre: Float,
        intensity: Float,
        steps: Int,
        gap: Double,
        rng: inout SeededGenerator
    ) {
        let stepCount = max(1, steps)
        for i in samples.indices {
            let t = Double(i) / sampleRate
            var sum: Float = 0
            for s in 0..<stepCount {
                let start = Double(s) * gap
                let local = t - start
                guard local >= 0, local < 0.09 else { continue }
                let freq = (70 + 40 * pitch) * (1.0 + 0.08 * Double(s))
                let phase = freq * local
                let env = Float(exp(-local * 55))
                let body = SynthDSP.osc(.sine, phase: phase)
                let grit = rng.signedUnit() * (0.15 + 0.35 * timbre) * env
                sum += (body * 0.7 + grit) * env
            }
            samples[i] = sum * (0.35 + 0.4 * intensity)
        }
    }

    private func renderFlyWhoosh(
        samples: inout [Float],
        sampleRate: Double,
        pitch: Double,
        timbre: Float,
        intensity: Float,
        flutter: Float,
        rng: inout SeededGenerator
    ) {
        let duration = Double(samples.count) / sampleRate
        var phase = 0.0
        let f0 = (220 + 180 * Double(flutter)) * pitch
        for i in samples.indices {
            let t = Double(i) / sampleRate
            let prog = t / max(duration, 0.0001)
            let vib = 1.0 + 0.12 * sin(t * 28)
            phase += (f0 * vib * (1.0 + 0.4 * prog)) / sampleRate
            let env = Float(sin(Double.pi * min(1, prog * 1.05)))
            let air = rng.signedUnit() * (0.25 + 0.45 * timbre) * env
            let tone = SynthDSP.osc(.sine, phase: phase) * (0.2 + 0.2 * (1 - timbre))
            samples[i] = (air + tone) * env * (0.3 + 0.4 * intensity)
        }
    }

    // MARK: - Gacha

    private func renderGachaSpin(
        samples: inout [Float],
        sampleRate: Double,
        pitch: Double,
        timbre: Float,
        intensity: Float,
        ticks: Int,
        rng: inout SeededGenerator
    ) {
        let duration = Double(samples.count) / sampleRate
        let count = max(4, ticks)
        for i in samples.indices {
            let t = Double(i) / sampleRate
            let prog = t / max(duration, 0.0001)
            // Mechanical ratchet slowing down.
            let rate = Double(count) * (1.6 - 1.1 * prog)
            let phasePos = prog * rate
            let frac = phasePos - floor(phasePos)
            let tickEnv = Float(exp(-frac * 18))
            let freq = (600 + 500 * (1 - prog)) * pitch
            let click = SynthDSP.osc(.square, phase: freq * t) * tickEnv * 0.55
            let mech = rng.signedUnit() * tickEnv * (0.12 + 0.25 * timbre)
            let body = SynthDSP.osc(.sine, phase: (180 * pitch) * t) * tickEnv * 0.2
            let master = Float(sin(Double.pi * min(1, prog * 1.02)))
            samples[i] = (click + mech + body) * master * (0.35 + 0.45 * intensity)
        }
    }

    private func renderGachaRare(
        samples: inout [Float],
        sampleRate: Double,
        pitch: Double,
        timbre: Float,
        intensity: Float,
        motif: Int,
        sparkle: Float,
        rng: inout SeededGenerator
    ) {
        let duration = Double(samples.count) / sampleRate
        // Intro sparkle rise, then bright fanfare cascade.
        let split = duration * 0.35
        let notes: [[Double]] = [
            [523.25, 659.25, 783.99, 1046.5, 1318.5],
            [587.33, 740.0, 880.0, 1174.7, 1480.0],
            [659.25, 830.61, 987.77, 1318.5, 1661.2],
            [698.46, 880.0, 1046.5, 1396.9, 1760.0],
        ]
        let table = notes[motif % notes.count].map { $0 * pitch }
        for i in samples.indices {
            let t = Double(i) / sampleRate
            if t < split {
                let prog = t / max(split, 0.0001)
                let f = (400 + 1600 * prog) * pitch
                let env = Float(sin(Double.pi * 0.5 * prog))
                let spark = rng.signedUnit() * (0.1 + 0.35 * sparkle) * env
                let tone = SynthDSP.osc(.sine, phase: f * t) * 0.5
                    + SynthDSP.osc(.triangle, phase: f * 1.5 * t) * (0.15 + 0.2 * timbre)
                samples[i] = (tone + spark) * env * (0.35 + 0.4 * intensity)
            } else {
                let localT = t - split
                let localDur = duration - split
                let noteLen = localDur / Double(table.count)
                let idx = min(table.count - 1, Int(localT / max(noteLen, 0.0001)))
                let local = localT - Double(idx) * noteLen
                let freq = table[idx]
                let env = ADSR(attack: 0.008, decay: 0.04, sustain: 0.55, release: noteLen * 0.35)
                    .level(at: local, duration: noteLen)
                let tone = SynthDSP.osc(.square, phase: freq * local) * 0.45
                    + SynthDSP.osc(.sine, phase: freq * 1.5 * local) * (0.2 + 0.2 * timbre)
                let glitter = rng.signedUnit() * env * (0.05 + 0.15 * sparkle)
                samples[i] = (tone + glitter) * env * (0.35 + 0.45 * intensity)
            }
        }
    }

    // MARK: - Result

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

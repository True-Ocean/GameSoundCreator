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
        case .uiWarning:
            renderWarning(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity,
                repeats: 2 + pattern.motifPick
            )
        case .uiError:
            renderError(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity
            )
        case .uiUnlock:
            renderUnlock(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity, rng: &rng
            )
        case .uiText:
            renderTextTick(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity, rng: &rng
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
                hitAt: 0.55 + 0.25 * Double(pattern.morph),
                thumpWeight: 0.85, rng: &rng
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
        case .rewardCoin:
            renderCoin(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity,
                bounce: pattern.motifPick, rng: &rng
            )
        case .rewardChest:
            renderChestOpen(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity,
                sparkle: pattern.bright, rng: &rng
            )
        case .rewardLevelUp:
            renderLevelUp(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity,
                motif: pattern.motifPick
            )
        case .puzzleClear:
            renderPuzzleClear(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity, rng: &rng
            )
        case .puzzleCombo:
            renderCombo(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity,
                hits: 3 + pattern.motifPick
            )
        case .attackLight:
            renderNoiseBurstDown(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity, heavy: false,
                startMul: 0.75 + 0.7 * Double(pattern.morph),
                decayMul: 0.7 + 0.9 * Double(pattern.snap), rng: &rng
            )
        case .attackHeavy:
            renderHeavySmash(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity,
                windup: 0.28 + 0.2 * Double(pattern.morph),
                rumble: pattern.snap, rng: &rng
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
        case .attackBow:
            renderBowShot(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity,
                flight: 0.35 + 0.35 * Double(pattern.morph), rng: &rng
            )
        case .attackCritical:
            renderCritical(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity, rng: &rng
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
        case .defendParry:
            renderParry(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity,
                ring: pattern.bright, rng: &rng
            )
        case .skillCast:
            renderRisingSparkle(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity,
                rise: 0.35 + 0.7 * Double(pattern.morph),
                sparkle: pattern.bright * 0.75, rng: &rng
            )
        case .magicFire:
            renderMagicFire(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity,
                roar: pattern.morph, rng: &rng
            )
        case .magicIce:
            renderMagicFreeze(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity,
                crystallize: pattern.bright, morph: pattern.morph, rng: &rng
            )
        case .magicPoison:
            renderMagicPoison(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity,
                bubble: 4 + pattern.motifPick * 2, rng: &rng
            )
        case .magicStorm:
            renderMagicStorm(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity,
                gust: pattern.morph, rng: &rng
            )
        case .magicBeam:
            renderMagicBeam(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity,
                focus: 0.4 + 0.5 * Double(pattern.bright), rng: &rng
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
        case .moveJump:
            renderJump(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity,
                spring: 0.45 + 0.4 * Double(pattern.morph), rng: &rng
            )
        case .moveLand:
            renderLand(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity,
                weight: 0.4 + 0.45 * Double(pattern.snap), rng: &rng
            )
        case .moveDash:
            renderDash(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity,
                burst: pattern.snap, rng: &rng
            )
        case .moveSwim:
            renderSwim(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity,
                splash: pattern.bright, rng: &rng
            )
        case .moveDoor:
            renderDoorOpen(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity,
                creek: pattern.morph, rng: &rng
            )
        case .moveWarp:
            renderWarp(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity, rng: &rng
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
                sparkle: pattern.bright, morph: pattern.morph, rng: &rng
            )
        case .victory:
            renderVictoryFanfare(
                samples: &samples, sampleRate: sampleRate, duration: duration,
                pitch: pitch, timbre: timbre, intensity: intensity,
                motif: pattern.motifPick
            )
        case .defeat:
            renderDefeatFanfare(
                samples: &samples, sampleRate: sampleRate, duration: duration,
                pitch: pitch, timbre: timbre, intensity: intensity,
                motif: pattern.motifPick
            )
        case .fanfareSting:
            renderJaJaan(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity,
                motif: pattern.motifPick
            )
        case .fanfareCorrect:
            renderPingPong(
                samples: &samples, sampleRate: sampleRate,
                pitch: pitch, timbre: timbre, intensity: intensity,
                spacing: 0.02 + 0.03 * Double(pattern.morph)
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

    private func renderWarning(
        samples: inout [Float], sampleRate: Double, pitch: Double, timbre: Float,
        intensity: Float, repeats: Int
    ) {
        let duration = Double(samples.count) / sampleRate
        let hits = max(2, repeats)
        for i in samples.indices {
            let t = Double(i) / sampleRate
            let position = min(hits - 1, Int(t / max(duration / Double(hits), 0.001)))
            let local = t - Double(position) * duration / Double(hits)
            let hitDuration = duration / Double(hits)
            let phase = (960.0 + Double(position % 2) * 80) * pitch * local
            let env = ADSR(attack: 0.002, decay: 0.025, sustain: 0.12, release: 0.025)
                .level(at: local, duration: hitDuration)
            let volume = 0.25 + 0.42 * intensity
            let softness = 0.75 + 0.25 * (1 - timbre)
            samples[i] = SynthDSP.osc(.square, phase: phase) * env * volume * softness
        }
    }

    private func renderError(
        samples: inout [Float], sampleRate: Double, pitch: Double, timbre: Float, intensity: Float
    ) {
        let duration = Double(samples.count) / sampleRate
        for i in samples.indices {
            let t = Double(i) / sampleRate
            let first = t < duration * 0.48
            let local = first ? t : t - duration * 0.52
            let localDuration = duration * 0.42
            let frequency = (first ? 235.0 : 185.0) * pitch
            let phase = frequency * local
            let dissonant = SynthDSP.osc(.square, phase: phase) * 0.72
                + SynthDSP.osc(.triangle, phase: phase * 1.059) * (0.18 + 0.18 * timbre)
            let env = ADSR(attack: 0.003, decay: 0.03, sustain: 0.25, release: 0.04)
                .level(at: local, duration: localDuration)
            samples[i] = dissonant * env * (0.28 + 0.42 * intensity)
        }
    }

    private func renderUnlock(
        samples: inout [Float], sampleRate: Double, pitch: Double, timbre: Float,
        intensity: Float, rng: inout SeededGenerator
    ) {
        let duration = Double(samples.count) / sampleRate
        for i in samples.indices {
            let t = Double(i) / sampleRate
            let clickNoise = Double(rng.signedUnit()) * 0.45 + 0.55
            let click = exp(-t * 55) * clickNoise
            let release = max(0, (t - duration * 0.18) / max(duration * 0.82, 0.001))
            let phase = (520.0 + 390.0 * release) * pitch * max(0, t - duration * 0.18)
            let chimeEnv = ADSR(attack: 0.005, decay: 0.06, sustain: 0.18, release: 0.12)
                .level(at: max(0, t - duration * 0.18), duration: duration * 0.82)
            let chime = SynthDSP.osc(.triangle, phase: phase) + SynthDSP.osc(.sine, phase: phase * 2) * (0.2 + 0.2 * timbre)
            samples[i] = Float(click * 0.42) * (0.3 + 0.45 * intensity)
                + chime * chimeEnv * (0.3 + 0.45 * intensity)
        }
    }

    private func renderTextTick(
        samples: inout [Float], sampleRate: Double, pitch: Double, timbre: Float,
        intensity: Float, rng: inout SeededGenerator
    ) {
        for i in samples.indices {
            let t = Double(i) / sampleRate
            let env = exp(-t * (48 + 35 * Double(timbre)))
            let phase = 1500.0 * pitch * t
            let noise = rng.signedUnit() * (0.12 + 0.3 * timbre)
            samples[i] = (SynthDSP.osc(.triangle, phase: phase) * 0.72 + noise) * Float(env) * (0.16 + 0.22 * intensity)
        }
    }

    // MARK: - Reward / Puzzle

    private func renderCoin(
        samples: inout [Float], sampleRate: Double, pitch: Double, timbre: Float,
        intensity: Float, bounce: Int, rng: inout SeededGenerator
    ) {
        let duration = Double(samples.count) / sampleRate
        let hits = 2 + bounce % 3
        for i in samples.indices {
            let t = Double(i) / sampleRate
            var value: Float = 0
            for hit in 0..<hits {
                let start = Double(hit) * duration * 0.18
                let local = t - start
                guard local >= 0 else { continue }
                let env = exp(-local * (18 + Double(hit) * 6))
                let jitter = Double(rng.range(-25, 25))
                let frequency = (1450.0 + Double(hit) * 180 + jitter) * pitch
                let phase = frequency * local
                value += Float(env) * (SynthDSP.osc(.sine, phase: phase) * 0.72
                    + SynthDSP.osc(.sine, phase: phase * 2.71) * (0.18 + 0.16 * timbre))
            }
            samples[i] = value * (0.24 + 0.4 * intensity)
        }
    }

    private func renderChestOpen(
        samples: inout [Float], sampleRate: Double, pitch: Double, timbre: Float,
        intensity: Float, sparkle: Float, rng: inout SeededGenerator
    ) {
        let duration = Double(samples.count) / sampleRate
        for i in samples.indices {
            let t = Double(i) / sampleRate
            let latchNoise = Double(rng.signedUnit()) * 0.45 + 0.5
            let latch = exp(-t * 45) * latchNoise
            let progress = max(0, (t - duration * 0.14) / max(duration * 0.86, 0.001))
            let phase = (390.0 + 690.0 * progress) * pitch * max(0, t - duration * 0.14)
            let env = Float(sin(Double.pi * min(1, progress))) * Float(exp(-progress * 1.25))
            let shimmer = SynthDSP.osc(.triangle, phase: phase) + SynthDSP.osc(.sine, phase: phase * 1.5) * (0.18 + 0.25 * sparkle)
            samples[i] = (Float(latch) * 0.4 + shimmer * env) * (0.28 + 0.45 * intensity)
        }
    }

    private func renderLevelUp(
        samples: inout [Float], sampleRate: Double, pitch: Double, timbre: Float,
        intensity: Float, motif: Int
    ) {
        let duration = Double(samples.count) / sampleRate
        let notes = motif.isMultiple(of: 2) ? [0.0, 4.0, 7.0, 12.0] : [0.0, 3.0, 7.0, 12.0]
        for i in samples.indices {
            let t = Double(i) / sampleRate
            var value: Float = 0
            for (index, semitones) in notes.enumerated() {
                let start = Double(index) * duration * 0.17
                let local = t - start
                guard local >= 0 else { continue }
                let frequency = 440.0 * pow(2, semitones / 12) * pitch
                let env = ADSR(attack: 0.004, decay: 0.04, sustain: 0.22, release: 0.12)
                    .level(at: local, duration: duration - start)
                let phase = frequency * local
                value += (SynthDSP.osc(.triangle, phase: phase) + SynthDSP.osc(.sine, phase: phase * 2) * (0.1 + 0.2 * timbre)) * env
            }
            samples[i] = value * (0.17 + 0.3 * intensity)
        }
    }

    private func renderPuzzleClear(
        samples: inout [Float], sampleRate: Double, pitch: Double, timbre: Float,
        intensity: Float, rng: inout SeededGenerator
    ) {
        let duration = Double(samples.count) / sampleRate
        for i in samples.indices {
            let t = Double(i) / sampleRate
            let progress = t / max(duration, 0.001)
            let phase = (310.0 + 740.0 * progress * progress) * pitch * t
            let suctionAmount = Float(1 - progress) * (0.3 + 0.45 * timbre)
            let suction = rng.signedUnit() * suctionAmount
            let env = Float(sin(Double.pi * min(1, progress)))
            samples[i] = (SynthDSP.osc(.sine, phase: phase) * 0.65 + suction) * env * (0.28 + 0.4 * intensity)
        }
    }

    private func renderCombo(
        samples: inout [Float], sampleRate: Double, pitch: Double, timbre: Float,
        intensity: Float, hits: Int
    ) {
        let duration = Double(samples.count) / sampleRate
        for i in samples.indices {
            let t = Double(i) / sampleRate
            var value: Float = 0
            for hit in 0..<hits {
                let start = Double(hit) * duration * 0.13
                let local = t - start
                guard local >= 0 else { continue }
                let phase = (520.0 + Double(hit) * 135) * pitch * local
                let env = Float(exp(-local * 17))
                value += (SynthDSP.osc(.square, phase: phase) * 0.7 + SynthDSP.osc(.sine, phase: phase * 2) * (0.12 + 0.15 * timbre)) * env
            }
            samples[i] = value * (0.2 + 0.28 * intensity)
        }
    }

    private func renderCritical(
        samples: inout [Float], sampleRate: Double, pitch: Double, timbre: Float,
        intensity: Float, rng: inout SeededGenerator
    ) {
        let duration = Double(samples.count) / sampleRate
        for i in samples.indices {
            let t = Double(i) / sampleRate
            let noise = Double(rng.signedUnit()) * Double(0.35 + 0.35 * timbre)
            let thump = sin(2 * Double.pi * 105 * pitch * t)
            let impact = exp(-t * 24) * (noise + thump)
            let sparkleLocal = max(0, t - duration * 0.09)
            let sparkle = sin(2 * Double.pi * 2100 * pitch * sparkleLocal) * exp(-sparkleLocal * 17)
            samples[i] = Float(impact * 0.72 + sparkle * 0.5) * (0.34 + 0.48 * intensity)
        }
    }

    private func renderParry(
        samples: inout [Float], sampleRate: Double, pitch: Double, timbre: Float,
        intensity: Float, ring: Float, rng: inout SeededGenerator
    ) {
        for i in samples.indices {
            let t = Double(i) / sampleRate
            let snap = exp(-t * 65) * Double(rng.signedUnit()) * 0.45
            let env = exp(-t * (7.5 - 2.5 * Double(ring)))
            let metallic = sin(2 * Double.pi * 980 * pitch * t) + sin(2 * Double.pi * 1475 * pitch * t) * 0.58
            let metalAmount = 0.55 + 0.2 * Double(timbre)
            let sample = snap * 0.4 + metallic * env * metalAmount
            samples[i] = Float(sample) * (0.27 + 0.43 * intensity)
        }
    }

    private func renderWarp(
        samples: inout [Float], sampleRate: Double, pitch: Double, timbre: Float,
        intensity: Float, rng: inout SeededGenerator
    ) {
        let duration = Double(samples.count) / sampleRate
        for i in samples.indices {
            let t = Double(i) / sampleRate
            let progress = t / max(duration, 0.001)
            let departure = max(0, 1 - progress * 2)
            let arrival = max(0, progress * 2 - 1)
            let departPhase = (1250.0 - 950.0 * progress) * pitch * t
            let arriveLocal = max(0, t - duration * 0.5)
            let arrivePhase = (320.0 + 900.0 * arrival) * pitch * arriveLocal
            let noise = rng.signedUnit() * Float(departure) * (0.3 + 0.35 * timbre)
            let tone = SynthDSP.osc(.sine, phase: departPhase) * Float(departure) * 0.55
                + SynthDSP.osc(.triangle, phase: arrivePhase) * Float(arrival) * 0.72
            samples[i] = (noise + tone) * (0.3 + 0.45 * intensity)
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
        thumpWeight: Float = 0.55,
        rng: inout SeededGenerator
    ) {
        let duration = Double(samples.count) / sampleRate
        let hitTime = duration * min(0.85, max(0.15, hitAt))
        var phase = 0.0
        let thumpFreq = 120.0 + 100.0 * pitch
        let tw = min(1, max(0.2, thumpWeight))
        for i in samples.indices {
            let t = Double(i) / sampleRate
            let whooshEnv = Float(exp(-3.2 * t / duration)) * (0.25 + 0.35 * timbre)
            let noise = rng.signedUnit() * whooshEnv
            let hitDist = abs(t - hitTime)
            let hit = Float(exp(-hitDist * (55 + 70 * Double(intensity)))) * (0.5 + 0.45 * intensity)
            phase += thumpFreq / sampleRate
            let thump = SynthDSP.osc(.sine, phase: phase) * hit
            samples[i] = noise * (1 - tw * 0.55) + thump * tw
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
        let snapAt = duration * (0.22 + 0.25 * Double(snap))
        var phase = 0.0
        for i in samples.indices {
            let t = Double(i) / sampleRate
            // Light paper flutter, then bright high snap (distinct from card_play thump).
            let whoosh = Float(exp(-5.5 * t / duration)) * rng.signedUnit() * (0.12 + 0.22 * timbre)
            let dist = abs(t - snapAt)
            let click = Float(exp(-dist * 120)) * (0.65 + 0.3 * intensity)
            phase += (1800 * pitch) / sampleRate
            let tip = SynthDSP.osc(.triangle, phase: phase) * click
                + SynthDSP.osc(.sine, phase: phase * 2.2) * click * 0.35
            samples[i] = whoosh * 0.45 + tip
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

    /// Heavy attack: wind-up whoosh → low smash → rumble (distinct from bash thump).
    private func renderHeavySmash(
        samples: inout [Float],
        sampleRate: Double,
        pitch: Double,
        timbre: Float,
        intensity: Float,
        windup: Double,
        rumble: Float,
        rng: inout SeededGenerator
    ) {
        let duration = Double(samples.count) / sampleRate
        let hitAt = duration * min(0.55, max(0.22, windup))
        var phase = 0.0
        var rumblePhase = 0.0
        let smashFreq = (70 + 45 * Double(rumble)) * pitch
        for i in samples.indices {
            let t = Double(i) / sampleRate
            let prog = t / max(duration, 0.0001)
            var sum: Float = 0
            if t < hitAt {
                let local = t / max(hitAt, 0.0001)
                let whoosh = rng.signedUnit() * Float(local) * (0.2 + 0.35 * timbre)
                let rise = SynthDSP.osc(.saw, phase: (180 + 220 * local) * pitch * t)
                    * Float(local) * 0.2
                sum = whoosh + rise
            } else {
                let local = t - hitAt
                let localProg = local / max(duration - hitAt, 0.0001)
                phase += (smashFreq * (1.0 - 0.45 * localProg)) / sampleRate
                rumblePhase += (38 * pitch) / sampleRate
                let env = Float(exp(-(1.6 + 1.2 * Double(rumble)) * localProg))
                let body = SynthDSP.osc(.sine, phase: phase) * 0.7
                let sub = SynthDSP.osc(.sine, phase: rumblePhase) * (0.25 + 0.25 * rumble) * env
                let grit = rng.signedUnit() * (0.12 + 0.25 * timbre) * env
                sum = SynthDSP.softClip(body + sub + grit, drive: 2.0 + intensity) * env
            }
            let master = prog < 0.05 ? Float(prog / 0.05) : 1
            samples[i] = sum * master * (0.42 + 0.48 * intensity)
        }
    }

    /// ビュン（放ち）→ シュー（飛行）→ ブスッ（刺さる）
    private func renderBowShot(
        samples: inout [Float],
        sampleRate: Double,
        pitch: Double,
        timbre: Float,
        intensity: Float,
        flight: Double,
        rng: inout SeededGenerator
    ) {
        let duration = Double(samples.count) / sampleRate
        let releaseEnd = duration * 0.16
        let impactAt = duration * min(0.88, max(0.55, 0.58 + flight * 0.22))
        var twangPhase = 0.0
        var flyPhase = 0.0
        var hp: Float = 0
        for i in samples.indices {
            let t = Double(i) / sampleRate
            var sum: Float = 0

            // 1) ビュン — sharp string release with fast falling twang.
            if t < releaseEnd {
                let local = t / max(releaseEnd, 0.0001)
                let twangF = (1400 - 900 * local) * pitch
                twangPhase += twangF / sampleRate
                let env = Float(exp(-local * 14))
                let string = SynthDSP.osc(.triangle, phase: twangPhase) * 0.55
                    + SynthDSP.osc(.sine, phase: twangPhase * 2.1) * 0.25
                let pluck = rng.signedUnit() * Float(exp(-local * 40)) * 0.35
                sum += (string + pluck) * env
            }

            // 2) シュー — sustained air whoosh while the arrow flies.
            if t >= releaseEnd * 0.35, t < impactAt {
                let flyT = t - releaseEnd * 0.35
                let flyDur = max(impactAt - releaseEnd * 0.35, 0.0001)
                let flyProg = flyT / flyDur
                let n = rng.signedUnit()
                hp = SynthDSP.mix(hp, n, t: 0.12 + 0.25 * timbre)
                let air = (n - hp * 0.85) * (0.28 + 0.35 * timbre)
                let whistleF = (700 - 280 * flyProg) * pitch
                flyPhase += whistleF / sampleRate
                let whistle = SynthDSP.osc(.sine, phase: flyPhase) * (0.12 + 0.1 * (1 - timbre))
                let flyEnv = Float(sin(Double.pi * min(1, flyProg * 1.05))) * (0.55 + 0.35 * (1 - Float(flyProg)))
                sum += (air + whistle) * flyEnv
            }

            // 3) ブスッ — short dull pierce / flesh impact.
            let pierceLocal = t - impactAt
            if pierceLocal >= 0, pierceLocal < 0.12 {
                let thumpF = 110.0 * pitch
                let thumpEnv = Float(exp(-pierceLocal * 45))
                let body = SynthDSP.osc(.sine, phase: thumpF * pierceLocal) * thumpEnv * 0.7
                let flesh = rng.signedUnit() * Float(exp(-pierceLocal * 55)) * (0.25 + 0.35 * timbre)
                let tip = SynthDSP.osc(.triangle, phase: (380 * pitch) * pierceLocal)
                    * Float(exp(-pierceLocal * 70)) * 0.25
                sum += body + flesh + tip
            }

            samples[i] = SynthDSP.softClip(sum, drive: 1.15 + 0.4 * intensity) * (0.38 + 0.45 * intensity)
        }
    }

    /// Sword slash: audible blade-whoosh arc + brief metal flash (not a ピューン whistle).
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
        var metalPhase = 0.0
        var lp: Float = 0
        var bp: Float = 0
        // Peak of the cut a bit before halfway — acceleration into the swing.
        let peakAt = 0.32 + 0.12 * whip
        for i in samples.indices {
            let t = Double(i) / sampleRate
            let prog = t / max(duration, 0.0001)

            // Arc envelope: clearly hear the swing start → peak → stop.
            let rise = prog / max(peakAt, 0.001)
            let fall = (1 - prog) / max(1 - peakAt, 0.001)
            let arc = Float(min(rise, fall))
            let env = max(0, arc * arc) // punchier peak

            let n = rng.signedUnit()
            // Two-pole-ish noise: blade cutting air (broadband, not a pitched tone).
            lp = SynthDSP.mix(lp, n, t: 0.08 + 0.15 * timbre)
            let mid = n - lp
            bp = SynthDSP.mix(bp, mid, t: 0.25 + 0.2 * (1 - Float(whip)))
            let whoosh = (mid * 0.65 + bp * 0.45) * env * (0.55 + 0.35 * timbre)

            // Brightness rides the swing: duller on entry, sharper at peak, dulls out.
            let brightGate = env * Float(0.5 + 0.5 * sin(Double.pi * min(1, prog * 1.05)))
            let edge = (n - bp) * brightGate * (0.2 + 0.25 * Float(whip))

            // Short metal flash near the peak only (~40ms) — 「キン」not「ピューン」.
            let peakDist = abs(prog - peakAt)
            let metalEnv = Float(exp(-peakDist * 28)) * env
            let metalF = (1200 + 600 * whip) * pitch
            metalPhase += metalF / sampleRate
            let metal = SynthDSP.osc(.triangle, phase: metalPhase) * metalEnv * 0.22
                + SynthDSP.osc(.square, phase: metalPhase * 1.5) * metalEnv * 0.08

            // Light body so the cut has weight without becoming a bash.
            let body = SynthDSP.osc(.sine, phase: (140 * pitch) * t)
                * env * Float(exp(-prog * 3.5)) * 0.18

            let mixed = whoosh + edge + metal + body
            samples[i] = SynthDSP.softClip(mixed, drive: 1.35 + 0.7 * intensity)
                * (0.42 + 0.48 * intensity)
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

    /// Freeze: ピキピキ accelerating crystal cracks as the target ices over.
    private func renderMagicFreeze(
        samples: inout [Float],
        sampleRate: Double,
        pitch: Double,
        timbre: Float,
        intensity: Float,
        crystallize: Float,
        morph: Float,
        rng: inout SeededGenerator
    ) {
        let duration = Double(samples.count) / sampleRate
        // Three clear ピキッ events (slight timing jitter from seed).
        let crackCount = 3
        let bases: [Double] = [0.22, 0.48, 0.72]
        let crackTimes: [Double] = (0..<crackCount).map { k in
            let jitter = (Double(rng.unit()) - 0.5) * 0.06
            return duration * min(0.85, max(0.12, bases[k] + jitter + 0.04 * Double(morph)))
        }

        var bedPhase = 0.0
        var glassPhase = 0.0
        let bedStart = (220 + 80 * Double(morph)) * pitch
        let bedEnd = (70 + 30 * Double(crystallize)) * pitch

        for i in samples.indices {
            let t = Double(i) / sampleRate
            let prog = t / max(duration, 0.0001)
            let harden = Float(prog * prog) // ice takes hold
            let master = Float(sin(Double.pi * min(1, prog * 1.04)))

            // Cold bed: quiet contracting tone under the cracks.
            let bedF = bedStart + (bedEnd - bedStart) * Double(harden)
            bedPhase += bedF / sampleRate
            let bed = SynthDSP.osc(.sine, phase: bedPhase) * (0.12 + 0.18 * harden)
                * (0.35 + 0.65 * master)

            // Thin icy shimmer (not melodic) — glass grain.
            glassPhase += (1400 + 900 * Double(crystallize)) * pitch / sampleRate
            let shimmer = SynthDSP.osc(.triangle, phase: glassPhase)
                * (0.04 + 0.1 * crystallize) * harden * master
            let air = rng.signedUnit() * (0.03 + 0.08 * timbre) * (1 - harden * 0.6) * master

            // ピキッ ×3: each crack a bit brighter / sharper than the last.
            var cracks: Float = 0
            for (idx, ct) in crackTimes.enumerated() {
                let local = t - ct
                guard local >= 0, local < 0.055 else { continue }
                let brightness = 0.45 + 0.275 * Float(idx) // 0.45 / 0.725 / 1.0
                let pingF = (1600 + 1200 * Double(brightness) + 350 * Double(crystallize)) * pitch
                let env = Float(exp(-local * (48 + 28 * Double(brightness))))
                let ping = SynthDSP.osc(.sine, phase: pingF * local) * 0.65
                    + SynthDSP.osc(.triangle, phase: pingF * 2.2 * local) * 0.3
                let chip = rng.signedUnit() * Float(exp(-local * 80)) * (0.22 + 0.28 * timbre)
                cracks += (ping + chip) * env * (0.7 + 0.35 * brightness)
            }

            // Final solid lock — ice fully set.
            var lock: Float = 0
            if prog > 0.82 {
                let local = (prog - 0.82) / 0.18
                let lockEnv = Float(exp(-local * 6)) * Float(sin(Double.pi * min(1, local * 1.2)))
                lock = SynthDSP.osc(.sine, phase: (920 * pitch) * t) * lockEnv * 0.28
                    + SynthDSP.osc(.triangle, phase: (1380 * pitch) * t) * lockEnv * 0.12
            }

            samples[i] = (bed + shimmer + air + cracks * (0.85 + 0.25 * crystallize) + lock)
                * (0.34 + 0.46 * intensity)
        }
    }

    private func renderMagicStorm(
        samples: inout [Float],
        sampleRate: Double,
        pitch: Double,
        timbre: Float,
        intensity: Float,
        gust: Float,
        rng: inout SeededGenerator
    ) {
        let duration = Double(samples.count) / sampleRate
        var lp: Float = 0
        var phase = 0.0
        for i in samples.indices {
            let t = Double(i) / sampleRate
            let prog = t / max(duration, 0.0001)
            let n = rng.signedUnit()
            lp = SynthDSP.mix(lp, n, t: 0.05 + 0.12 * timbre)
            let rumble = lp * (0.45 + 0.35 * gust)
            let howlF = (90 + 70 * Double(gust)) * pitch * (1.0 + 0.25 * sin(t * 3.5))
            phase += howlF / sampleRate
            let howl = SynthDSP.osc(.sine, phase: phase) * (0.12 + 0.15 * (1 - timbre))
            let gustPulse = Float(0.55 + 0.45 * sin(t * Double.pi * (2.5 + 2 * Double(gust))))
            let env = Float(sin(Double.pi * min(1, prog * 1.05)))
            samples[i] = (rumble * gustPulse + howl + n * 0.08) * env * (0.35 + 0.45 * intensity)
        }
    }

    private func renderMagicBeam(
        samples: inout [Float],
        sampleRate: Double,
        pitch: Double,
        timbre: Float,
        intensity: Float,
        focus: Double,
        rng: inout SeededGenerator
    ) {
        let duration = Double(samples.count) / sampleRate
        var phase = 0.0
        var phase2 = 0.2
        let f0 = (380 + 260 * focus) * pitch
        for i in samples.indices {
            let t = Double(i) / sampleRate
            let prog = t / max(duration, 0.0001)
            let attack = min(1, prog / 0.08)
            let release = prog > 0.85 ? Float((1 - prog) / 0.15) : 1
            let vib = 1.0 + 0.015 * sin(t * 40)
            phase += (f0 * vib) / sampleRate
            phase2 += (f0 * 1.5 * vib) / sampleRate
            let core = SynthDSP.osc(.sine, phase: phase) * 0.55
                + SynthDSP.osc(.saw, phase: phase2) * (0.08 + 0.12 * Float(focus))
            let floor = rng.signedUnit() * (0.04 + 0.1 * timbre)
            samples[i] = (core + floor) * Float(attack) * release * (0.35 + 0.45 * intensity)
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

    private func renderJump(
        samples: inout [Float],
        sampleRate: Double,
        pitch: Double,
        timbre: Float,
        intensity: Float,
        spring: Double,
        rng: inout SeededGenerator
    ) {
        let duration = Double(samples.count) / sampleRate
        var phase = 0.0
        let f0 = (280 + 160 * spring) * pitch
        for i in samples.indices {
            let t = Double(i) / sampleRate
            let prog = t / max(duration, 0.0001)
            // Rising spring tone + soft air.
            let freq = f0 * (1.0 + 1.4 * prog)
            phase += freq / sampleRate
            let env = Float(exp(-prog * 3.2)) * Float(sin(Double.pi * min(1, prog * 1.3)))
            let boing = SynthDSP.osc(.sine, phase: phase) * 0.55
                + SynthDSP.osc(.triangle, phase: phase * 1.01) * 0.2
            let air = rng.signedUnit() * env * (0.1 + 0.2 * timbre)
            samples[i] = (boing + air) * env * (0.35 + 0.4 * intensity)
        }
    }

    private func renderLand(
        samples: inout [Float],
        sampleRate: Double,
        pitch: Double,
        timbre: Float,
        intensity: Float,
        weight: Double,
        rng: inout SeededGenerator
    ) {
        let duration = Double(samples.count) / sampleRate
        var phase = 0.0
        let thumpF = (70 + 50 * weight) * pitch
        for i in samples.indices {
            let t = Double(i) / sampleRate
            let prog = t / max(duration, 0.0001)
            phase += (thumpF * (1.0 - 0.45 * prog)) / sampleRate
            let env = Float(exp(-prog * (5.5 + 3 * weight)))
            let body = SynthDSP.osc(.sine, phase: phase) * 0.7
            let grit = rng.signedUnit() * env * (0.15 + 0.3 * timbre)
            samples[i] = (body + grit) * env * (0.4 + 0.45 * intensity)
        }
    }

    private func renderDash(
        samples: inout [Float],
        sampleRate: Double,
        pitch: Double,
        timbre: Float,
        intensity: Float,
        burst: Float,
        rng: inout SeededGenerator
    ) {
        let duration = Double(samples.count) / sampleRate
        var phase = 0.0
        var hp: Float = 0
        for i in samples.indices {
            let t = Double(i) / sampleRate
            let prog = t / max(duration, 0.0001)
            let n = rng.signedUnit()
            hp = SynthDSP.mix(hp, n, t: 0.15 + 0.25 * timbre)
            let whoosh = (n - hp * 0.8) * Float(exp(-prog * (3.5 + 2 * Double(burst))))
            phase += (420 + 500 * Double(burst)) * pitch * (1.0 + prog) / sampleRate
            let edge = SynthDSP.osc(.saw, phase: phase) * Float(exp(-prog * 6)) * 0.2
            samples[i] = (whoosh * (0.55 + 0.3 * timbre) + edge) * (0.38 + 0.42 * intensity)
        }
    }

    private func renderSwim(
        samples: inout [Float],
        sampleRate: Double,
        pitch: Double,
        timbre: Float,
        intensity: Float,
        splash: Float,
        rng: inout SeededGenerator
    ) {
        let duration = Double(samples.count) / sampleRate
        var lp: Float = 0
        var phase = 0.0
        for i in samples.indices {
            let t = Double(i) / sampleRate
            let prog = t / max(duration, 0.0001)
            let n = rng.signedUnit()
            lp = SynthDSP.mix(lp, n, t: 0.12 + 0.2 * timbre)
            let water = lp * (0.4 + 0.25 * splash)
            let bubbleGate = abs(sin(t * 14 + Double(splash))) > 0.88
            let bubble = bubbleGate ? abs(rng.signedUnit()) * (0.15 + 0.2 * splash) : 0
            phase += (90 + 40 * sin(t * 6)) * pitch / sampleRate
            let surge = SynthDSP.osc(.sine, phase: phase) * Float(sin(Double.pi * min(1, prog * 1.05))) * 0.15
            samples[i] = (water + bubble + surge) * (0.35 + 0.4 * intensity)
        }
    }

    private func renderDoorOpen(
        samples: inout [Float],
        sampleRate: Double,
        pitch: Double,
        timbre: Float,
        intensity: Float,
        creek: Float,
        rng: inout SeededGenerator
    ) {
        let duration = Double(samples.count) / sampleRate
        let latchAt = duration * 0.12
        var phase = 0.0
        for i in samples.indices {
            let t = Double(i) / sampleRate
            var sum: Float = 0
            // Latch click.
            let latchLocal = t - latchAt
            if abs(latchLocal) < 0.04 {
                sum += rng.signedUnit() * Float(exp(-abs(latchLocal) * 70)) * 0.45
            }
            // Wood creak / swing.
            if t > latchAt {
                let local = t - latchAt
                let localProg = local / max(duration - latchAt, 0.0001)
                let creakF = (180 + 120 * Double(creek) + 80 * sin(local * 9)) * pitch
                phase += creakF / sampleRate
                let env = Float(sin(Double.pi * min(1, localProg * 1.05)))
                sum += SynthDSP.osc(.saw, phase: phase) * env * (0.2 + 0.15 * timbre)
                sum += rng.signedUnit() * env * (0.06 + 0.1 * timbre)
            }
            samples[i] = sum * (0.35 + 0.4 * intensity)
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

    /// Gacha rare: rising sparkle expectation → shimmer release (no victory fanfare).
    private func renderGachaRare(
        samples: inout [Float],
        sampleRate: Double,
        pitch: Double,
        timbre: Float,
        intensity: Float,
        sparkle: Float,
        morph: Float,
        rng: inout SeededGenerator
    ) {
        let duration = Double(samples.count) / sampleRate
        let split = duration * (0.55 + 0.1 * Double(morph))
        for i in samples.indices {
            let t = Double(i) / sampleRate
            if t < split {
                let prog = t / max(split, 0.0001)
                let f = (320 + 1400 * prog) * pitch
                let env = Float(sin(Double.pi * 0.5 * prog))
                let spark = rng.signedUnit() * (0.12 + 0.4 * sparkle) * env
                let tone = SynthDSP.osc(.sine, phase: f * t) * 0.45
                    + SynthDSP.osc(.triangle, phase: f * 1.7 * t) * (0.1 + 0.2 * timbre)
                samples[i] = (tone + spark) * env * (0.35 + 0.4 * intensity)
            } else {
                let local = t - split
                let localDur = max(duration - split, 0.0001)
                let prog = local / localDur
                let burst = Float(exp(-prog * 4.5))
                let shimmer = rng.signedUnit() * burst * (0.2 + 0.45 * sparkle)
                let bell = SynthDSP.osc(.sine, phase: (1200 + 400 * Double(sparkle)) * pitch * local)
                    * burst * 0.45
                    + SynthDSP.osc(.triangle, phase: (1800 * pitch) * local) * burst * (0.15 + 0.15 * timbre)
                samples[i] = (bell + shimmer) * (0.38 + 0.42 * intensity)
            }
        }
    }

    // MARK: - Result / Fanfare

    /// テッテレー — short-short-short-long major clear jingle.
    private func renderVictoryFanfare(
        samples: inout [Float],
        sampleRate: Double,
        duration: Double,
        pitch: Double,
        timbre: Float,
        intensity: Float,
        motif: Int
    ) {
        let motifs: [[Double]] = [
            [392.0, 523.25, 659.25, 784.0],   // G C E G
            [523.25, 659.25, 783.99, 1046.5], // C E G C
            [440.0, 554.37, 659.25, 880.0],   // A C# E A
            [349.23, 440.0, 523.25, 698.46],  // F A C F
        ]
        let notes = motifs[motif % motifs.count].map { $0 * pitch }
        // Rhythm weights: テ・テ・テ・レー
        let weights: [Double] = [1, 1, 1, 2.4]
        let totalW = weights.reduce(0, +)
        var starts: [Double] = []
        var lens: [Double] = []
        var acc = 0.0
        for w in weights {
            starts.append(duration * acc / totalW)
            lens.append(duration * w / totalW)
            acc += w
        }

        for i in samples.indices {
            let t = Double(i) / sampleRate
            var sum: Float = 0
            for (idx, freq) in notes.enumerated() {
                let local = t - starts[idx]
                guard local >= 0, local < lens[idx] + 0.04 else { continue }
                let env = ADSR(attack: 0.008, decay: 0.04, sustain: idx == 3 ? 0.55 : 0.25, release: lens[idx] * 0.35)
                    .level(at: local, duration: lens[idx])
                // Brass-ish square + sine (classic game clear).
                let brass = SynthDSP.osc(.square, phase: freq * local) * 0.4
                    + SynthDSP.osc(.sine, phase: freq * local) * 0.35
                    + SynthDSP.osc(.sine, phase: freq * 1.5 * local) * (0.12 + 0.15 * timbre)
                sum += brass * env
            }
            samples[i] = SynthDSP.softClip(sum, drive: 1.15 + 0.35 * intensity) * (0.34 + 0.45 * intensity)
        }
    }

    /// デデデーン — descending sad sting, last note longer.
    private func renderDefeatFanfare(
        samples: inout [Float],
        sampleRate: Double,
        duration: Double,
        pitch: Double,
        timbre: Float,
        intensity: Float,
        motif: Int
    ) {
        let motifs: [[Double]] = [
            [392.0, 349.23, 293.66, 220.0],   // G F D A
            [440.0, 392.0, 329.63, 246.94],   // A G E B
            [523.25, 440.0, 349.23, 261.63],  // C A F C
            [349.23, 311.13, 246.94, 185.0],  // F Eb B G
        ]
        let notes = motifs[motif % motifs.count].map { $0 * pitch }
        let weights: [Double] = [1, 1, 1, 2.6]
        let totalW = weights.reduce(0, +)
        var starts: [Double] = []
        var lens: [Double] = []
        var acc = 0.0
        for w in weights {
            starts.append(duration * acc / totalW)
            lens.append(duration * w / totalW)
            acc += w
        }

        for i in samples.indices {
            let t = Double(i) / sampleRate
            var sum: Float = 0
            for (idx, freq) in notes.enumerated() {
                let local = t - starts[idx]
                guard local >= 0, local < lens[idx] + 0.05 else { continue }
                let env = ADSR(attack: 0.01, decay: 0.05, sustain: idx == 3 ? 0.4 : 0.2, release: lens[idx] * 0.4)
                    .level(at: local, duration: lens[idx])
                let tone = SynthDSP.osc(.triangle, phase: freq * local) * 0.45
                    + SynthDSP.osc(.sine, phase: freq * local) * 0.35
                    + SynthDSP.osc(.sine, phase: freq * 0.5 * local) * (0.12 + 0.1 * timbre)
                sum += tone * env
            }
            samples[i] = sum * 0.72 * (0.3 + 0.4 * intensity)
        }
    }

    /// ジャジャーン — two-hit dramatic major chord reveal.
    private func renderJaJaan(
        samples: inout [Float],
        sampleRate: Double,
        pitch: Double,
        timbre: Float,
        intensity: Float,
        motif: Int
    ) {
        let duration = Double(samples.count) / sampleRate
        // Open major chords (C / D / G / F).
        let chords: [[Double]] = [
            [261.63, 329.63, 392.0, 523.25],
            [293.66, 369.99, 440.0, 587.33],
            [196.0, 246.94, 293.66, 392.0],
            [174.61, 220.0, 261.63, 349.23],
        ]
        let chord = chords[motif % chords.count].map { $0 * pitch }
        let hit1 = 0.0
        let hit2 = duration * 0.22

        for i in samples.indices {
            let t = Double(i) / sampleRate
            var sum: Float = 0
            for (hitIdx, start) in [hit1, hit2].enumerated() {
                let local = t - start
                guard local >= 0 else { continue }
                let hitDur = hitIdx == 0 ? duration * 0.28 : duration - start
                let env = ADSR(
                    attack: 0.012,
                    decay: hitIdx == 0 ? 0.08 : 0.12,
                    sustain: hitIdx == 0 ? 0.2 : 0.5,
                    release: hitDur * 0.4
                ).level(at: local, duration: hitDur)
                let weight: Float = hitIdx == 0 ? 0.75 : 1.0
                for (n, freq) in chord.enumerated() {
                    let amp: Float = n == 0 ? 0.28 : (n == chord.count - 1 ? 0.3 : 0.2)
                    // Brass / orchestral sting character.
                    sum += SynthDSP.osc(.saw, phase: freq * local) * amp * 0.45 * weight * env
                    sum += SynthDSP.osc(.square, phase: freq * local) * amp * 0.25 * weight * env
                    sum += SynthDSP.osc(.sine, phase: freq * 1.5 * local) * amp * (0.15 + 0.15 * timbre) * weight * env
                }
            }
            samples[i] = SynthDSP.softClip(sum, drive: 1.25 + 0.5 * intensity) * (0.32 + 0.45 * intensity)
        }
    }

    /// Japanese ピンポーン (doorbell / quiz correct): high short ピン → lower ringing ポーン.
    private func renderPingPong(
        samples: inout [Float],
        sampleRate: Double,
        pitch: Double,
        timbre: Float,
        intensity: Float,
        spacing: Double
    ) {
        let duration = Double(samples.count) / sampleRate
        // Typical intercom peaks ~850Hz then ~680Hz (high → low, ~major 3rd).
        let pinFreq = 880.0 * pitch   // A5 — ピン
        let ponFreq = 698.46 * pitch  // F5 — ポーン
        let pinDur = min(0.16, duration * 0.32)
        let ponStart = pinDur + max(0.015, min(0.05, spacing))
        let ponDur = max(0.22, duration - ponStart)

        for i in samples.indices {
            let t = Double(i) / sampleRate
            var sum: Float = 0

            // ピン — shorter, brighter, soft attack.
            if t < pinDur + 0.08 {
                let local = t
                let env = ADSR(attack: 0.012, decay: 0.05, sustain: 0.15, release: 0.07)
                    .level(at: local, duration: pinDur)
                let tone = SynthDSP.osc(.sine, phase: pinFreq * local) * 0.7
                    + SynthDSP.osc(.sine, phase: pinFreq * 2 * local) * (0.08 + 0.1 * (1 - timbre))
                sum += tone * env
            }

            // ポーン — lower, longer ring (the recognizable 「ポーン」).
            if t >= ponStart {
                let local = t - ponStart
                let env = ADSR(attack: 0.014, decay: 0.08, sustain: 0.35, release: ponDur * 0.45)
                    .level(at: local, duration: ponDur)
                let tone = SynthDSP.osc(.sine, phase: ponFreq * local) * 0.72
                    + SynthDSP.osc(.sine, phase: ponFreq * 2 * local) * (0.1 + 0.12 * (1 - timbre))
                    + SynthDSP.osc(.triangle, phase: ponFreq * local) * (0.06 * timbre)
                sum += tone * env
            }

            samples[i] = sum * (0.36 + 0.42 * intensity)
        }
    }
}

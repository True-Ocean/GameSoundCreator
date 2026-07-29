import Foundation

/// Post-mix tone/space processing for Phase 3.5-C.
/// Designed to be loop-safe (circular indexing / warmup passes).
public enum SpaceFX {
    /// One-pole low-pass. Double-pass warmup keeps loop seams stable.
    public static func applyLowpass(
        _ samples: inout [Float],
        cutoffHz: Double,
        sampleRate: Double
    ) {
        guard samples.count > 1 else { return }
        let nyquist = sampleRate * 0.5
        let cutoff = min(max(cutoffHz, 120), nyquist * 0.92)
        // Near-Nyquist → essentially bypass.
        if cutoff > nyquist * 0.88 { return }

        let a = exp(-2 * Double.pi * cutoff / sampleRate)
        let b = Float(1 - a)
        let af = Float(a)

        func process(state: inout Float, x: Float) -> Float {
            state = b * x + af * state
            return state
        }

        var state: Float = 0
        let warm = min(samples.count, max(256, Int(sampleRate * 0.04)))
        let start = samples.count - warm
        for i in start..<samples.count {
            _ = process(state: &state, x: samples[i])
        }
        for i in samples.indices {
            samples[i] = process(state: &state, x: samples[i])
        }
    }

    /// Short circular room: early reflections + light comb feedback.
    /// `mix` 0…~0.55, `decay` controls feedback / tail length feel.
    public static func applyShortReverb(
        _ samples: inout [Float],
        mix: Float,
        decay: Float,
        sampleRate: Double
    ) {
        let wetMix = min(0.55, max(0, mix))
        guard wetMix > 0.012, samples.count > 128 else { return }

        let n = samples.count
        let decayClamped = min(0.82, max(0.18, decay))
        let dry = samples

        // Early reflection delays (~18–52 ms).
        let tapMs: [Double] = [18, 27, 36, 47]
        let tapGains: [Float] = [0.42, 0.32, 0.24, 0.18].map { $0 * (0.55 + 0.45 * decayClamped) }
        let taps = tapMs.map { max(2, Int($0 * 0.001 * sampleRate)) % max(2, n - 1) }

        var early = [Float](repeating: 0, count: n)
        for i in 0..<n {
            var sum = dry[i]
            for (delay, gain) in zip(taps, tapGains) {
                let j = (i - delay + n) % n
                sum += dry[j] * gain
            }
            early[i] = sum
        }

        // One circular comb for a short wash (2 passes ≈ settle).
        let combDelay = max(2, Int(0.041 * sampleRate)) % max(2, n - 1)
        let feedback = 0.22 * decayClamped
        var comb = early
        for _ in 0..<2 {
            var next = comb
            for i in 0..<n {
                let delayed = comb[(i - combDelay + n) % n]
                next[i] = early[i] + delayed * feedback
            }
            comb = next
        }

        // Damp highs on wet path so it doesn't hiss.
        applyLowpass(&comb, cutoffHz: 2_800 + 1_400 * Double(decayClamped), sampleRate: sampleRate)

        let dryGain = 1 - wetMix * 0.85
        for i in 0..<n {
            samples[i] = dry[i] * dryGain + comb[i] * wetMix
        }
    }
}

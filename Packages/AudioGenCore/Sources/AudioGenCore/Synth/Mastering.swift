import Foundation

public enum Mastering {
    /// Peak-normalize then soft-limit. Mutates in place.
    public static func apply(
        _ samples: inout [Float],
        targetPeak: Float = 0.89,
        drive: Float = 1.15,
        fadeOutTail: Bool = true
    ) {
        guard !samples.isEmpty else { return }

        var peak: Float = 0
        for s in samples {
            peak = max(peak, abs(s))
        }
        if peak > 0.0001 {
            let gain = targetPeak / peak
            for i in samples.indices {
                samples[i] *= gain
            }
        }

        for i in samples.indices {
            samples[i] = SynthDSP.softClip(samples[i], drive: drive)
        }

        // One-shot SE only. Looping BGM must keep the bar-line energy at the end.
        guard fadeOutTail else { return }

        let fade = min(samples.count, Int(0.003 * AudioFormatDefaults.sampleRate))
        if fade > 1 {
            let start = samples.count - fade
            for i in 0..<fade {
                let t = Float(i) / Float(fade - 1)
                samples[start + i] *= (1 - t)
            }
        }
    }
}

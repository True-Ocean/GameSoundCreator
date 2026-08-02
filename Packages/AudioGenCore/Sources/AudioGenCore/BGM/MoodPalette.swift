import Foundation

/// Audible style knobs derived from catalog mood.
struct MoodPalette: Sendable {
    var chordShape: WaveShape
    var bassShape: WaveShape
    var leadShape: WaveShape
    var chordOctave: Int
    var leadOctave: Int
    var drumKick: Float
    var drumSnare: Float
    var drumHat: Float
    var chordAmp: Float
    var bassAmp: Float
    var leadAmp: Float
    /// Softens highs by mixing toward sine (0 = full harmonic, 1 = very muted).
    var mute: Float
    var melodyChance: Float
    /// Post-mix low-pass target (Hz). Lower = darker / less chip-tune.
    var filterCutoffHz: Double
    /// Short reverb wet amount (0…~0.4).
    var reverbMix: Float
    /// Reverb feedback / tail feel (0…1).
    var reverbDecay: Float

    static func from(moodId: String, brightness: Float, energy: Float, density: Float) -> MoodPalette {
        let mood = Catalog.Mood(rawValue: moodId) ?? .neutral
        switch mood {
        case .bright:
            return MoodPalette(
                chordShape: .triangle,
                bassShape: .sine,
                leadShape: .square,
                chordOctave: 5,
                leadOctave: 6,
                drumKick: 0.25 + 0.25 * energy,
                drumSnare: 0.15 + 0.2 * energy,
                drumHat: 0.12 + 0.2 * brightness,
                chordAmp: 0.14,
                bassAmp: 0.14,
                leadAmp: 0.16 + 0.1 * density,
                mute: 0.05,
                melodyChance: 0.45 + 0.4 * density,
                filterCutoffHz: 4_800 + 1_200 * Double(brightness),
                reverbMix: 0.10 + 0.06 * brightness,
                reverbDecay: 0.32
            )
        case .tense:
            return MoodPalette(
                chordShape: .saw,
                bassShape: .saw,
                leadShape: .square,
                chordOctave: 4,
                leadOctave: 5,
                drumKick: 0.45 + 0.45 * energy,
                drumSnare: 0.35 + 0.4 * energy,
                drumHat: 0.14 + 0.2 * energy,
                chordAmp: 0.11,
                bassAmp: 0.22,
                leadAmp: 0.12 + 0.1 * density,
                mute: 0.15,
                melodyChance: 0.35 + 0.35 * density,
                filterCutoffHz: 3_600 + 800 * Double(energy),
                reverbMix: 0.09 + 0.04 * energy,
                reverbDecay: 0.28
            )
        case .dark:
            // Somber but still audible on phone speakers (avoid sub-bass mud).
            return MoodPalette(
                chordShape: .sine,
                bassShape: .sine,
                leadShape: .triangle,
                chordOctave: 4,
                leadOctave: 5,
                drumKick: 0.3 + 0.2 * energy,
                drumSnare: 0.12 + 0.15 * energy,
                drumHat: 0.05 + 0.08 * energy,
                chordAmp: 0.15,
                bassAmp: 0.18,
                leadAmp: 0.12 + 0.1 * density,
                mute: 0.35 + 0.2 * (1 - brightness),
                melodyChance: 0.22 + 0.28 * density,
                filterCutoffHz: 2_400 + 1_100 * Double(brightness),
                reverbMix: 0.22 + 0.08 * (1 - brightness),
                reverbDecay: 0.5
            )
        case .neutral:
            return MoodPalette(
                chordShape: .triangle,
                bassShape: .sine,
                leadShape: .square,
                chordOctave: 4,
                leadOctave: 5,
                drumKick: 0.35 + 0.35 * energy,
                drumSnare: 0.22 + 0.28 * energy,
                drumHat: 0.08 + 0.12 * energy,
                chordAmp: 0.12,
                bassAmp: 0.18,
                leadAmp: 0.1 + 0.1 * density,
                mute: 0.2,
                melodyChance: 0.3 + 0.35 * density,
                filterCutoffHz: 3_200 + 600 * Double(brightness),
                reverbMix: 0.16,
                reverbDecay: 0.4
            )
        }
    }

    func voice(_ shape: WaveShape, phase: Double) -> Float {
        let raw = SynthDSP.osc(shape, phase: phase)
        let soft = SynthDSP.osc(.sine, phase: phase)
        return SynthDSP.mix(raw, soft, t: mute)
    }
}

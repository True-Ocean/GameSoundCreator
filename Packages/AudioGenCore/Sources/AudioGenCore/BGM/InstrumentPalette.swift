import Foundation

/// Timbre / envelope / layer weights for a BGM instrument preset.
struct InstrumentPalette: Sendable {
    var chordShape: WaveShape
    var bassShape: WaveShape
    var leadShape: WaveShape
    var chordEnv: ADSR
    var bassEnv: ADSR
    var leadEnv: ADSR
    var chordAmpScale: Float
    var bassAmpScale: Float
    var leadAmpScale: Float
    var chordDurationScale: Double
    var bassDurationScale: Double
    var leadDurationScale: Double
    /// Added to mood mute (clamped later).
    var muteBias: Float
    var leadOctaveBias: Int
    var chordOctaveBias: Int
    var melodyChanceScale: Float
    /// Prefer sustained chord hits (pads) vs rhythmic stabs.
    var sustainChords: Bool
    /// Multiplies mood filter cutoff (lower = darker).
    var filterCutoffScale: Double
    /// Added to mood reverb mix (clamped later).
    var reverbMixBias: Float

    static func from(instrumentId: String) -> InstrumentPalette {
        switch Catalog.Instrument.resolve(instrumentId) {
        case .leadSynth:
            return InstrumentPalette(
                chordShape: .triangle,
                bassShape: .saw,
                leadShape: .square,
                chordEnv: ADSR(attack: 0.01, decay: 0.08, sustain: 0.45, release: 0.1),
                bassEnv: ADSR(attack: 0.005, decay: 0.06, sustain: 0.55, release: 0.08),
                leadEnv: ADSR(attack: 0.005, decay: 0.05, sustain: 0.5, release: 0.08),
                chordAmpScale: 0.9,
                bassAmpScale: 1.0,
                leadAmpScale: 1.25,
                chordDurationScale: 0.9,
                bassDurationScale: 0.95,
                leadDurationScale: 1.05,
                muteBias: -0.05,
                leadOctaveBias: 0,
                chordOctaveBias: 0,
                melodyChanceScale: 1.15,
                sustainChords: false,
                filterCutoffScale: 1.12,
                reverbMixBias: -0.02
            )
        case .piano:
            return InstrumentPalette(
                chordShape: .triangle,
                bassShape: .sine,
                leadShape: .triangle,
                chordEnv: ADSR(attack: 0.002, decay: 0.22, sustain: 0.12, release: 0.18),
                bassEnv: ADSR(attack: 0.002, decay: 0.18, sustain: 0.15, release: 0.14),
                leadEnv: ADSR(attack: 0.001, decay: 0.28, sustain: 0.08, release: 0.2),
                chordAmpScale: 1.05,
                bassAmpScale: 0.85,
                leadAmpScale: 1.15,
                chordDurationScale: 1.15,
                bassDurationScale: 1.0,
                leadDurationScale: 1.25,
                muteBias: 0.12,
                leadOctaveBias: 0,
                chordOctaveBias: 1,
                melodyChanceScale: 1.0,
                sustainChords: false,
                filterCutoffScale: 1.0,
                reverbMixBias: 0.05
            )
        case .pad:
            return InstrumentPalette(
                chordShape: .sine,
                bassShape: .sine,
                leadShape: .triangle,
                chordEnv: ADSR(attack: 0.18, decay: 0.25, sustain: 0.75, release: 0.35),
                bassEnv: ADSR(attack: 0.08, decay: 0.15, sustain: 0.7, release: 0.25),
                leadEnv: ADSR(attack: 0.12, decay: 0.2, sustain: 0.55, release: 0.3),
                chordAmpScale: 1.35,
                bassAmpScale: 0.9,
                leadAmpScale: 0.7,
                chordDurationScale: 1.8,
                bassDurationScale: 1.3,
                leadDurationScale: 1.4,
                muteBias: 0.28,
                leadOctaveBias: -1,
                chordOctaveBias: 0,
                melodyChanceScale: 0.55,
                sustainChords: true,
                filterCutoffScale: 0.72,
                reverbMixBias: 0.14
            )
        case .bass:
            return InstrumentPalette(
                chordShape: .triangle,
                bassShape: .saw,
                leadShape: .sine,
                chordEnv: ADSR(attack: 0.02, decay: 0.1, sustain: 0.35, release: 0.12),
                bassEnv: ADSR(attack: 0.008, decay: 0.1, sustain: 0.65, release: 0.1),
                leadEnv: ADSR(attack: 0.01, decay: 0.08, sustain: 0.35, release: 0.1),
                chordAmpScale: 0.55,
                bassAmpScale: 1.55,
                leadAmpScale: 0.55,
                chordDurationScale: 0.85,
                bassDurationScale: 1.15,
                leadDurationScale: 0.85,
                muteBias: 0.08,
                leadOctaveBias: -1,
                chordOctaveBias: -1,
                melodyChanceScale: 0.45,
                sustainChords: false,
                filterCutoffScale: 0.58,
                reverbMixBias: -0.04
            )
        }
    }
}

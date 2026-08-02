import Foundation

/// Extra ring beyond the gated note length, plus optional FM-index decay.
struct ToneTail: Sendable, Equatable {
    /// Seconds written after the scheduled note duration (overlapping clear decay).
    var ringOut: Double
    /// FM index exponential time constant in seconds; 0 keeps index constant.
    var fmDecay: Double

    static let none = ToneTail(ringOut: 0, fmDecay: 0)

    init(ringOut: Double = 0, fmDecay: Double = 0) {
        self.ringOut = max(0, ringOut)
        self.fmDecay = max(0, fmDecay)
    }

    var isActive: Bool { ringOut > 0.0001 || fmDecay > 0.0001 }
}

/// Timbre / envelope / FM / layer roles for a BGM instrument preset.
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

    // MARK: Phase 3.5-D — FM + layer roles

    var chordFM: FMTone
    var bassFM: FMTone
    var leadFM: FMTone
    /// Scales kick / snare / hat together.
    var drumAmpScale: Float
    /// Extra attenuation on upper chord notes (0 = equal, higher = root-dominant).
    var chordUpperAtten: Float
    /// When true, bass walks less and stays nearer the root.
    var bassRootHeavy: Bool
    /// Soften hats for pad-like beds.
    var hatAmpScale: Float
    var chordTail: ToneTail
    var bassTail: ToneTail
    var leadTail: ToneTail
    /// When true, lead/chord use the dedicated hammer + partial-decay piano voice.
    var pianoVoice: Bool

    static func from(instrumentId: String) -> InstrumentPalette {
        switch Catalog.Instrument.resolve(instrumentId) {
        case .leadSynth:
            // Retro square lead: punchy attack, moderated FM, short ring so edges aren't clicky.
            return InstrumentPalette(
                chordShape: .triangle,
                bassShape: .saw,
                leadShape: .square,
                chordEnv: ADSR(attack: 0.01, decay: 0.08, sustain: 0.4, release: 0.1),
                bassEnv: ADSR(attack: 0.005, decay: 0.06, sustain: 0.55, release: 0.08),
                leadEnv: ADSR(attack: 0.01, decay: 0.1, sustain: 0.5, release: 0.15),
                chordAmpScale: 0.6,
                bassAmpScale: 0.95,
                leadAmpScale: 1.4,
                chordDurationScale: 0.85,
                bassDurationScale: 0.95,
                leadDurationScale: 1.05,
                muteBias: 0.08,
                leadOctaveBias: 0,
                chordOctaveBias: 0,
                melodyChanceScale: 1.25,
                sustainChords: false,
                filterCutoffScale: 1.0,
                reverbMixBias: 0.04,
                chordFM: FMTone(ratio: 1.0, index: 0.35),
                bassFM: FMTone(ratio: 0.5, index: 0.25),
                leadFM: FMTone(ratio: 2.0, index: 0.85),
                drumAmpScale: 1.0,
                chordUpperAtten: 0.35,
                bassRootHeavy: false,
                hatAmpScale: 0.85,
                chordTail: .none,
                bassTail: .none,
                leadTail: ToneTail(ringOut: 0.06, fmDecay: 0.16),
                pianoVoice: false
            )
        case .piano:
            // Dedicated piano voice (hammer + staggered partials). Palette sets mix/register only.
            return InstrumentPalette(
                chordShape: .triangle,
                bassShape: .sine,
                leadShape: .triangle,
                chordEnv: ADSR(attack: 0.002, decay: 0.3, sustain: 0.06, release: 0.16),
                bassEnv: ADSR(attack: 0.003, decay: 0.22, sustain: 0.18, release: 0.14),
                leadEnv: ADSR(attack: 0.001, decay: 0.45, sustain: 0.04, release: 0.18),
                chordAmpScale: 0.88,
                bassAmpScale: 0.95,
                leadAmpScale: 1.35,
                chordDurationScale: 0.95,
                bassDurationScale: 1.05,
                leadDurationScale: 0.95,
                muteBias: 0.05,
                leadOctaveBias: 0,
                chordOctaveBias: 0,
                melodyChanceScale: 1.05,
                sustainChords: false,
                filterCutoffScale: 1.08,
                reverbMixBias: 0.1,
                chordFM: FMTone(ratio: 2.0, index: 0.2),
                bassFM: FMTone(ratio: 1.0, index: 0.1),
                leadFM: FMTone(ratio: 2.0, index: 0.3),
                drumAmpScale: 0.75,
                chordUpperAtten: 0.35,
                bassRootHeavy: true,
                hatAmpScale: 0.7,
                chordTail: ToneTail(ringOut: 0.5, fmDecay: 0),
                bassTail: ToneTail(ringOut: 0.2, fmDecay: 0),
                leadTail: ToneTail(ringOut: 0.75, fmDecay: 0),
                pianoVoice: true
            )
        case .pad:
            // Soft bed: slow swell, clear mid register (readable on small speakers).
            return InstrumentPalette(
                chordShape: .sine,
                bassShape: .sine,
                leadShape: .triangle,
                chordEnv: ADSR(attack: 0.28, decay: 0.35, sustain: 0.82, release: 0.45),
                bassEnv: ADSR(attack: 0.14, decay: 0.2, sustain: 0.75, release: 0.32),
                leadEnv: ADSR(attack: 0.18, decay: 0.28, sustain: 0.48, release: 0.4),
                chordAmpScale: 1.35,
                bassAmpScale: 0.75,
                leadAmpScale: 0.85,
                chordDurationScale: 1.9,
                bassDurationScale: 1.25,
                leadDurationScale: 1.45,
                muteBias: 0.1,
                leadOctaveBias: 0,
                chordOctaveBias: 0,
                melodyChanceScale: 0.55,
                sustainChords: true,
                filterCutoffScale: 0.98,
                reverbMixBias: 0.18,
                chordFM: FMTone(ratio: 1.0, index: 0.4),
                bassFM: FMTone(ratio: 0.5, index: 0.12),
                leadFM: FMTone(ratio: 1.0, index: 0.25),
                drumAmpScale: 0.4,
                chordUpperAtten: 0.1,
                bassRootHeavy: true,
                hatAmpScale: 0.3,
                // ringOut must stay 0: active ring replaces ADSR and would kill pad sustain.
                chordTail: ToneTail(ringOut: 0, fmDecay: 0.5),
                bassTail: .none,
                leadTail: ToneTail(ringOut: 0, fmDecay: 0.4),
                pianoVoice: false
            )
        case .bass:
            // Low end is the star: growly bass FM, thin upper layers, punchy kick.
            return InstrumentPalette(
                chordShape: .triangle,
                bassShape: .saw,
                leadShape: .sine,
                chordEnv: ADSR(attack: 0.025, decay: 0.1, sustain: 0.28, release: 0.12),
                bassEnv: ADSR(attack: 0.006, decay: 0.12, sustain: 0.7, release: 0.11),
                leadEnv: ADSR(attack: 0.012, decay: 0.08, sustain: 0.3, release: 0.1),
                chordAmpScale: 0.42,
                bassAmpScale: 1.75,
                leadAmpScale: 0.42,
                chordDurationScale: 0.8,
                bassDurationScale: 1.2,
                leadDurationScale: 0.8,
                muteBias: 0.1,
                leadOctaveBias: -1,
                chordOctaveBias: -1,
                melodyChanceScale: 0.32,
                sustainChords: false,
                filterCutoffScale: 0.55,
                reverbMixBias: -0.05,
                chordFM: FMTone(ratio: 1.0, index: 0.2),
                bassFM: FMTone(ratio: 2.0, index: 0.9),
                leadFM: FMTone(ratio: 1.0, index: 0.2),
                drumAmpScale: 1.15,
                chordUpperAtten: 0.55,
                bassRootHeavy: true,
                hatAmpScale: 0.75,
                chordTail: .none,
                bassTail: .none,
                leadTail: .none,
                pianoVoice: false
            )
        case .musicBox:
            // Clear tine plucks: short gate, long exponential ring; FM dies into pure sine.
            // envelope.decay = exponential tau when ring-out is active.
            return InstrumentPalette(
                chordShape: .sine,
                bassShape: .sine,
                leadShape: .sine,
                chordEnv: ADSR(attack: 0.001, decay: 0.35, sustain: 0, release: 0.08),
                bassEnv: ADSR(attack: 0.004, decay: 0.22, sustain: 0, release: 0.08),
                leadEnv: ADSR(attack: 0.001, decay: 0.48, sustain: 0, release: 0.1),
                chordAmpScale: 0.28,
                bassAmpScale: 0.28,
                leadAmpScale: 1.65,
                chordDurationScale: 0.7,
                bassDurationScale: 0.75,
                leadDurationScale: 0.7,
                muteBias: 0.08,
                leadOctaveBias: 1,
                chordOctaveBias: 1,
                melodyChanceScale: 1.15,
                sustainChords: false,
                filterCutoffScale: 1.28,
                reverbMixBias: 0.16,
                chordFM: FMTone(ratio: 3.0, index: 0.4),
                bassFM: FMTone(ratio: 1.0, index: 0.06),
                leadFM: FMTone(ratio: 3.0, index: 0.9),
                drumAmpScale: 0.22,
                chordUpperAtten: 0.45,
                bassRootHeavy: true,
                hatAmpScale: 0.15,
                chordTail: ToneTail(ringOut: 0.75, fmDecay: 0.12),
                bassTail: ToneTail(ringOut: 0.3, fmDecay: 0.08),
                leadTail: ToneTail(ringOut: 1.35, fmDecay: 0.14),
                pianoVoice: false
            )
        case .organ:
            // Sustained church-like bed: slow attack, rich harmonics, soft drums.
            return InstrumentPalette(
                chordShape: .square,
                bassShape: .saw,
                leadShape: .square,
                chordEnv: ADSR(attack: 0.12, decay: 0.18, sustain: 0.82, release: 0.28),
                bassEnv: ADSR(attack: 0.08, decay: 0.14, sustain: 0.75, release: 0.22),
                leadEnv: ADSR(attack: 0.1, decay: 0.16, sustain: 0.7, release: 0.24),
                chordAmpScale: 1.35,
                bassAmpScale: 0.95,
                leadAmpScale: 0.95,
                chordDurationScale: 1.7,
                bassDurationScale: 1.3,
                leadDurationScale: 1.4,
                muteBias: 0.15,
                leadOctaveBias: 0,
                chordOctaveBias: 0,
                melodyChanceScale: 0.7,
                sustainChords: true,
                filterCutoffScale: 0.85,
                reverbMixBias: 0.12,
                chordFM: FMTone(ratio: 2.0, index: 0.55),
                bassFM: FMTone(ratio: 1.0, index: 0.3),
                leadFM: FMTone(ratio: 2.0, index: 0.65),
                drumAmpScale: 0.55,
                chordUpperAtten: 0.08,
                bassRootHeavy: true,
                hatAmpScale: 0.4,
                chordTail: .none,
                bassTail: .none,
                leadTail: .none,
                pianoVoice: false
            )
        case .guitar:
            // Bright plucks with mild bite; mid drums; adventure-friendly.
            return InstrumentPalette(
                chordShape: .triangle,
                bassShape: .triangle,
                leadShape: .saw,
                chordEnv: ADSR(attack: 0.003, decay: 0.2, sustain: 0.18, release: 0.16),
                bassEnv: ADSR(attack: 0.005, decay: 0.14, sustain: 0.35, release: 0.12),
                leadEnv: ADSR(attack: 0.002, decay: 0.24, sustain: 0.12, release: 0.18),
                chordAmpScale: 1.05,
                bassAmpScale: 0.9,
                leadAmpScale: 1.25,
                chordDurationScale: 1.1,
                bassDurationScale: 1.0,
                leadDurationScale: 1.2,
                muteBias: 0.05,
                leadOctaveBias: 0,
                chordOctaveBias: 0,
                melodyChanceScale: 1.1,
                sustainChords: false,
                filterCutoffScale: 1.08,
                reverbMixBias: 0.04,
                chordFM: FMTone(ratio: 2.0, index: 0.4),
                bassFM: FMTone(ratio: 1.0, index: 0.2),
                leadFM: FMTone(ratio: 2.5, index: 0.75),
                drumAmpScale: 0.92,
                chordUpperAtten: 0.2,
                bassRootHeavy: false,
                hatAmpScale: 0.85,
                chordTail: .none,
                bassTail: .none,
                leadTail: .none,
                pianoVoice: false
            )
        }
    }
}

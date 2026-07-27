import Foundation

/// Deterministic RNG (SplitMix64) for reproducible SFX.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    public mutating func unit() -> Float {
        Float(Double(next() >> 11) / Double(1 << 53))
    }

    public mutating func signedUnit() -> Float {
        unit() * 2 - 1
    }

    public mutating func range(_ min: Float, _ max: Float) -> Float {
        min + (max - min) * unit()
    }
}

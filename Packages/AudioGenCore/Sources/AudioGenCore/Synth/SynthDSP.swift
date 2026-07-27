import Foundation

public struct ADSR: Sendable {
    public var attack: Double
    public var decay: Double
    public var sustain: Float
    public var release: Double

    public init(attack: Double, decay: Double, sustain: Float, release: Double) {
        self.attack = max(0, attack)
        self.decay = max(0, decay)
        self.sustain = min(1, max(0, sustain))
        self.release = max(0, release)
    }

    public func level(at time: Double, duration: Double) -> Float {
        let releaseStart = max(0, duration - release)
        if time < attack {
            return attack > 0 ? Float(time / attack) : 1
        }
        if time < attack + decay {
            let t = (time - attack) / max(decay, 0.0001)
            return 1 - (1 - sustain) * Float(t)
        }
        if time < releaseStart {
            return sustain
        }
        if release <= 0 {
            return 0
        }
        let t = (time - releaseStart) / release
        return sustain * Float(max(0, 1 - t))
    }
}

public enum WaveShape: Sendable {
    case sine
    case square
    case saw
    case triangle
}

public enum SynthDSP {
    public static func osc(_ shape: WaveShape, phase: Double) -> Float {
        let p = phase - floor(phase)
        switch shape {
        case .sine:
            return Float(sin(2 * Double.pi * p))
        case .square:
            return p < 0.5 ? 1 : -1
        case .saw:
            return Float(2 * p - 1)
        case .triangle:
            return Float(p < 0.5 ? 4 * p - 1 : 3 - 4 * p)
        }
    }

    public static func softClip(_ x: Float, drive: Float = 1) -> Float {
        let d = max(0.1, drive)
        return tanh(x * d) / tanh(d)
    }

    public static func mix(_ a: Float, _ b: Float, t: Float) -> Float {
        a * (1 - t) + b * t
    }
}

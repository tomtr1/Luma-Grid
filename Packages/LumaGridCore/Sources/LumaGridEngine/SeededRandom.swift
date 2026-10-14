/// SplitMix64: a small, fast, well-distributed PRNG whose entire state is one UInt64.
/// The state is Codable so an interrupted game resumes with the same upcoming pieces,
/// and the algorithm is fixed here (not delegated to the standard library) so a seed
/// produces the same sequence on every Swift version and device.
public struct SplitMix64: RandomNumberGenerator, Hashable, Codable, Sendable {
    public private(set) var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform integer in `0..<upperBound` (multiply-high method; bias is negligible for small bounds).
    public mutating func nextInt(below upperBound: Int) -> Int {
        precondition(upperBound > 0, "upperBound must be positive")
        let product = next().multipliedFullWidth(by: UInt64(upperBound))
        return Int(product.high)
    }

    /// Uniform double in `0..<1`.
    public mutating func nextUnit() -> Double {
        Double(next() >> 11) * 0x1.0p-53
    }
}

/// Stable 64-bit FNV-1a hash, used to derive seeds from strings such as a daily-challenge date.
public enum StableHash {
    public static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}

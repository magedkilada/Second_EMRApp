import Foundation

enum GrowthMath {

    static func zScore(value: Double, L: Double, M: Double, S: Double) -> Double {
        guard value > 0, M > 0, S > 0 else { return .nan }

        // WHO numerical stability rule
        if abs(L) < 1e-7 {
            return log(value / M) / S
        } else {
            return (pow(value / M, L) - 1.0) / (L * S)
        }
    }

    static func percentile(fromZ z: Double) -> Double {
        normalCDF(z) * 100.0
    }

    private static func normalCDF(_ x: Double) -> Double {
        0.5 * (1.0 + erf(x / sqrt(2.0)))
    }
}

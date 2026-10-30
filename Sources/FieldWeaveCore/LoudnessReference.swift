import Foundation

/// A deterministic starting point for live level matching, not a music LUFS measurement.
/// Models pink stereo with 50% shared energy, then sums both ears with K weighting.
public enum LoudnessReference {
    public static func gainDb(matrix: [[[Double]]], sampleRate: Int) throws -> Double? {
        guard (8000...192000).contains(sampleRate), matrix.count == 2,
              matrix.allSatisfy({ $0.count == 2 && $0.allSatisfy {
                  !$0.isEmpty && $0.count <= 262143 && $0.allSatisfy(\.isFinite)
              } }) else { throw FieldError.invalid("Invalid loudness reference matrix") }
        let n = max(16384, NativeFFT.size(matrix.flatMap { $0 }.map(\.count).max()! * 2))
        let spectra = matrix.map { row in row.map { taps -> ([Double], [Double]) in
            var real = taps + Array(repeating: 0, count: n - taps.count)
            var imaginary = Array(repeating: 0.0, count: n)
            NativeFFT.transform(&real, &imaginary)
            return (real, imaginary)
        } }
        // Rate-dependent BS.1770 weighting coefficients; equations also documented by
        // https://github.com/jiixyj/libebur128/blob/master/ebur128/ebur128.c
        let k = tan(.pi * 1681.974450955533 / Double(sampleRate))
        let q = 0.7071752369554196, vh = pow(10, 3.999843853973347 / 20)
        let vb = pow(vh, 0.4996667741545416), a0 = 1 + k / q + k * k
        let shelfB = [(vh + vb * k / q + k * k) / a0, 2 * (k * k - vh) / a0, (vh - vb * k / q + k * k) / a0]
        let shelfA = [1, 2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0]
        let kh = tan(.pi * 38.13547087602444 / Double(sampleRate)), qh = 0.5003270373238773
        let highA = [1, 2 * (kh * kh - 1) / (1 + kh / qh + kh * kh), (1 - kh / qh + kh * kh) / (1 + kh / qh + kh * kh)]
        func power(_ coefficients: [Double], _ omega: Double) -> Double {
            let real = coefficients[0] + coefficients[1] * cos(omega) + coefficients[2] * cos(2 * omega)
            let imaginary = -coefficients[1] * sin(omega) - coefficients[2] * sin(2 * omega)
            return real * real + imaginary * imaginary
        }
        var energy = 0.0, reference = 0.0
        for bin in 1...n / 2 {
            let frequency = Double(bin * sampleRate) / Double(n)
            guard frequency >= 20, frequency <= min(20000, Double(sampleRate) * 0.49) else { continue }
            let omega = 2 * .pi * frequency / Double(sampleRate)
            let weight = power(shelfB, omega) / power(shelfA, omega)
                * power([1, -2, 1], omega) / power(highA, omega) / frequency
            var output = 0.0
            for row in spectra {
                let a = row[0], b = row[1]
                output += a.0[bin] * a.0[bin] + a.1[bin] * a.1[bin]
                    + b.0[bin] * b.0[bin] + b.1[bin] * b.1[bin]
                    + a.0[bin] * b.0[bin] + a.1[bin] * b.1[bin]
            }
            energy += weight * output / 2
            reference += weight
        }
        let ratio = energy / reference
        guard ratio.isFinite else { throw FieldError.invalid("Nonfinite loudness reference energy") }
        // A silent/cancelled filter stays silent; never try to restore removed information.
        return ratio > 1e-12 ? 10 * log10(ratio) : nil
    }
}

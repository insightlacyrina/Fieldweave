import Foundation
import FieldWeaveCore

public struct LoudnessCalibration: Equatable, Sendable {
    /// Fixed reserve relative to the user's preamp, shared by every sound setting.
    public static let reserveDb = -6.0
    public var targetGainDb: Double
    public var filterGainDb: Double
    public var ceilingDbfs: Double

    public init(matrix: [[[Double]]], configuration: FieldConfiguration) throws {
        let target = configuration.safety.preampDb + Self.reserveDb
        targetGainDb = target
        ceilingDbfs = min(-1, configuration.safety.ceilingDbfs)
        let response = try LoudnessReference.gainDb(matrix: matrix, sampleRate: configuration.sampleRate)
        filterGainDb = response.map { min(36, max(-60, target - $0)) } ?? 0
    }
}

/// Tracks the processing gain, rather than normalizing songs to an absolute volume.
/// Stereo channels always receive the same correction, preserving pan and ear balance.
public struct LoudnessBalance: Sendable {
    public private(set) var trimDb = 0.0
    public let calibration: LoudnessCalibration
    private var lastInputDb: Double?
    private var smoothedError = 0.0
    private var stableWindows = 0

    public init(calibration: LoudnessCalibration) { self.calibration = calibration }

    mutating func resetTrim(to value:Double) {
        self=LoudnessBalance(calibration:calibration)
        trimDb=min(12,max(-24,value))
    }

    public static func stereoRMS(_ levels: [Double]) -> Double? {
        guard levels.count == 2, levels.allSatisfy({ !$0.isNaN && $0 != .infinity }) else { return nil }
        let power = levels.reduce(0.0) { $0 + pow(10, $1 / 10) } / 2
        return power > 0 && power.isFinite ? 10 * log10(power) : nil
    }

    public mutating func observe(captureRMS: [Double], playbackRMS: [Double], playbackPeak: [Double], seconds: Double) -> Double? {
        guard seconds.isFinite, seconds > 0, seconds <= 2,
              let input = Self.stereoRMS(captureRMS), let output = Self.stereoRMS(playbackRMS),
              input > -70, output > -90, output - input > -60,
              playbackPeak.count == 2, playbackPeak.allSatisfy(\.isFinite) else {
            lastInputDb = nil; stableWindows = 0; smoothedError = 0
            return nil
        }
        defer { lastInputDb = input }
        // The capture and playback windows include device/FIR latency. Let attacks,
        // stops and filter reloads settle before comparing their average energies.
        guard let previous = lastInputDb, abs(previous - input) < 3 else {
            stableWindows = 0; smoothedError = 0; return nil
        }
        stableWindows += 1
        guard stableWindows >= 2 else { return nil }
        let error = calibration.targetGainDb - (output - input)
        let alpha = 1 - exp(-seconds / 1.5)
        smoothedError += alpha * (error - smoothedError)
        let peakMargin = calibration.ceilingDbfs - 1.5 - playbackPeak.max()!
        var step = min(seconds, max(-6 * seconds, smoothedError))
        if peakMargin < 0 { step = min(step, max(-6 * seconds, peakMargin)) }
        else { step = min(step, peakMargin) }
        if abs(error) < 0.25 && peakMargin >= 0 { return nil }
        let next = min(12, max(-24, trimDb + step))
        guard abs(next - trimDb) >= 0.05 else { return nil }
        trimDb = next
        return next
    }
}

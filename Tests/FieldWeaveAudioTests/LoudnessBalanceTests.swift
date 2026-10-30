import Foundation
import Testing
import FieldWeaveCore
@testable import FieldWeaveAudio

@Suite struct FieldWeaveLoudnessBalanceTests {
    func calibration(preamp:Double = -3) throws -> LoudnessCalibration {
        var c=FieldConfiguration();c.safety.preampDb=preamp
        return try LoudnessCalibration(matrix:[[[1],[0]],[[0],[1]]],configuration:c)
    }

    @Test func referenceHandlesRatesDelaysSilenceAndStereoGain() throws {
        for rate in [8000,44100,48000,96000,192000] {
            let neutral=try #require(try LoudnessReference.gainDb(matrix:[[[1],[0]],[[0],[1]]],sampleRate:rate))
            #expect(abs(neutral)<1e-10)
            let gain=try #require(try LoudnessReference.gainDb(matrix:[[[0,0,0.1],[0]],[[0],[0.1]]],sampleRate:rate))
            #expect(abs(gain+20)<1e-8)
        }
        #expect(try LoudnessReference.gainDb(matrix:[[[0],[0]],[[0],[0]]],sampleRate:48000)==nil)
        #expect(throws:(any Error).self) {try LoudnessReference.gainDb(matrix:[[[.nan]]],sampleRate:48000)}
    }

    @Test func scalarIRLevelsAndPreampHavePredictableResults() throws {
        for preamp in [-24.0,-12,-3,0] {
            for scalar in [0.01,0.1,1,5] {
                var c=FieldConfiguration();c.safety.preampDb=preamp
                let cal=try LoudnessCalibration(matrix:[[[scalar],[0]],[[0],[scalar]]],configuration:c)
                #expect(abs(20*log10(scalar)+cal.filterGainDb-(preamp-6))<1e-9)
            }
        }
        let cal=try LoudnessCalibration(matrix:[[[1e-5],[0]],[[0],[1e-5]]],configuration:FieldConfiguration())
        #expect(cal.filterGainDb==36)
        let silent=try LoudnessCalibration(matrix:[[[0],[0]],[[0],[0]]],configuration:FieldConfiguration())
        #expect(silent.filterGainDb==0)
    }

    @Test func feedbackConvergesWithoutChangingSongDynamicsOrStereoBalance() throws {
        for processingGain in [-17.0,-12,-5,0] {
            var balance=LoudnessBalance(calibration:try calibration())
            var output=0.0
            for window in 0..<100 {
                // A source level change must remain a source level change at playback.
                let input=window<50 ? -35.0:-45.0
                output=input+processingGain+balance.trimDb
                let prior=balance.trimDb
                _=balance.observe(captureRMS:[input,input-6],playbackRMS:[output,output-6],playbackPeak:[output+8,output+2],seconds:0.5)
                #expect(balance.trimDb-prior<=0.5+1e-9)
                #expect(balance.trimDb-prior >= -3-1e-9)
            }
            #expect(abs(output-(-45)-(-9))<0.5)
            #expect(abs(processingGain+balance.trimDb+9)<0.5)
        }
    }

    @Test func silenceDropoutsAndCancelledContentNeverIncreaseGain() throws {
        var balance=LoudnessBalance(calibration:try calibration())
        for input in [[-100.0,-100],[-Double.infinity,-Double.infinity],[Double.nan,-30]] {
            for _ in 0..<30 {#expect(balance.observe(captureRMS:input,playbackRMS:[-110,-110],playbackPeak:[-100,-100],seconds:0.5)==nil)}
        }
        for _ in 0..<20 {#expect(balance.observe(captureRMS:[-30,-30],playbackRMS:[-100,-100],playbackPeak:[-95,-95],seconds:0.5)==nil)}
        #expect(balance.trimDb==0)
        #expect(balance.observe(captureRMS:[-30,-30],playbackRMS:[-50,-50],playbackPeak:[-40,-40],seconds:10)==nil)
    }

    @Test func peakMarginWinsOverRMSMatchingAndStereoIsEnergySummed() throws {
        var balance=LoudnessBalance(calibration:try calibration())
        for _ in 0..<20 {_=balance.observe(captureRMS:[-20,-20],playbackRMS:[-40,-40],playbackPeak:[-1.0,-6],seconds:0.5)}
        #expect(balance.trimDb<0)
        #expect(balance.trimDb >= -24)
        let rms=try #require(LoudnessBalance.stereoRMS([-20,-Double.infinity]))
        #expect(abs(rms-(-23.010299956639813))<1e-9)
    }
}

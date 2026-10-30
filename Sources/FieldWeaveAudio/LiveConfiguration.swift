import Foundation
import FieldWeaveCore

public enum LiveConfiguration {
    public static func yaml(exportDirectory:URL,capture:AudioDevice,playback:AudioDevice)throws->String {
        let template=try String(contentsOf:exportDirectory.appendingPathComponent("camilladsp-coreaudio.yml"),encoding:.utf8)
        guard let range=template.range(of:"filters:\n") else{throw LiveAudioError.message("The FIR package has no convolution pipeline")}
        let configuration=try FieldConfiguration.read(from:exportDirectory.appendingPathComponent("configuration.json"))
        func quote(_ value:String)->String {"'"+value.replacingOccurrences(of:"'",with:"''")+"'"}
        var matrix=Array(repeating:Array(repeating:[Double](),count:2),count:2)
        for (name,row,col) in [("LL",0,0),("LR",1,0),("RL",0,1),("RR",1,1)] {
            let wav=try WAVFile.read(exportDirectory.appendingPathComponent(name+".wav"))
            guard wav.sampleRate==configuration.sampleRate,wav.channels.count==1 else {throw LiveAudioError.message("Invalid live FIR asset")}
            matrix[row][col]=wav.channels[0]
        }
        let calibration=try LoudnessCalibration(matrix:matrix,configuration:configuration)
        try FieldConfiguration.encoder.encode(calibrationRecord(calibration)).write(to:exportDirectory.appendingPathComponent("live-loudness.json"),options:.atomic)
        var filters=String(template[range.lowerBound...])
        filters=filters.replacingOccurrences(of:"filters:\n",with:"""
        filters:
          FWBalanceCalibration: {type: Gain, parameters: {gain: \(calibration.filterGainDb)}}
          FWBalanceTrim: {type: Volume, parameters: {fader: Aux1, ramp_time: 500, limit: 12}}
          FWBalanceCeiling: {type: Limiter, parameters: {soft_clip: false, clip_limit: \(calibration.ceilingDbfs)}}

        """)
        filters += "\n  - {type: Filter, channels: [0, 1], names: [FWBalanceCalibration, FWBalanceTrim, FWBalanceCeiling]}\n"
        for name in ["LL","LR","RL","RR"] {filters=filters.replacingOccurrences(of:"filename: '\(name).wav'",with:"filename: \(quote(exportDirectory.appendingPathComponent(name+".wav").path))")}
        return """
        description: 'FieldWeave managed stereo FIR playback'
        devices:
          samplerate: \(configuration.sampleRate)
          chunksize: 512
          queuelimit: 4
          silence_threshold: -120
          silence_timeout: 0
          enable_rate_adjust: true
          resampler: {type: AsyncSinc, profile: Balanced}
          target_level: 1024
          adjust_period: 3
          stop_on_rate_change: true
          volume_ramp_time: 300
          capture: {type: CoreAudio, channels: 2, device: \(quote(capture.name))}
          playback: {type: CoreAudio, channels: 2, device: \(quote(playback.name)), exclusive: false}
        \(filters)
        """
    }

    public static func calibration(compiled:CompiledField,configuration:FieldConfiguration)throws->LoudnessCalibration {
        try LoudnessCalibration(matrix:compiled.matrix,configuration:configuration)
    }

    private static func calibrationRecord(_ calibration:LoudnessCalibration)->[String:Double] {
        ["target_gain_db":calibration.targetGainDb,"filter_gain_db":calibration.filterGainDb,"ceiling_dbfs":calibration.ceilingDbfs]
    }
}

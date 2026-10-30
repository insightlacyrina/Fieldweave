import Foundation
import Darwin
import FieldWeaveCore
import FieldWeaveAudio

@main struct AudioCLI {
    @MainActor static func main()async {
        let arguments=Array(CommandLine.arguments.dropFirst())
        func option(_ name:String)->String? {guard let index=arguments.firstIndex(of:name),index+1<arguments.count else{return nil};return arguments[index+1]}
        func printJSON(_ value:Any) {if let data=try? JSONSerialization.data(withJSONObject:value,options:[.sortedKeys,.prettyPrinted]) {print(String(decoding:data,as:UTF8.self))}}
        do {
            guard let command=arguments.first else{throw LiveAudioError.message(usage)}
            switch command {
            case "devices":
                let devices=try AudioDeviceCatalog.devices()
                let list=try JSONSerialization.jsonObject(with:JSONEncoder().encode(devices))
                printJSON(["devices":list,"default_output_uid":try AudioDeviceCatalog.defaultOutput()?.uid ?? ""])
            case "restore":
                let controller=LiveAudioController(supportDirectory:option("--support").map{URL(fileURLWithPath:$0,isDirectory:true)})
                try controller.recoverInterruptedRoute();print(controller.status)
            case "run":
                guard arguments.count>1,let capture=option("--capture"),let playback=option("--playback") else{throw LiveAudioError.message(usage)}
                let configURL=URL(fileURLWithPath:arguments[1]).standardizedFileURL
                let config=try FieldConfiguration.read(from:configURL)
                let compiled=try FIRCompiler.compile(config,baseURL:configURL.deletingLastPathComponent())
                let controller=LiveAudioController(supportDirectory:option("--support").map{URL(fileURLWithPath:$0,isDirectory:true)})
                let settings=AudioRouteSettings(captureUID:capture,playbackUID:playback)
                let original=try AudioDeviceCatalog.defaultOutput()?.uid ?? ""
                let seconds=Double(option("--seconds") ?? "30") ?? 30
                var interrupted=false
                signal(SIGINT,SIG_IGN);signal(SIGTERM,SIG_IGN)
                let interrupt=DispatchSource.makeSignalSource(signal:SIGINT,queue:.main),terminate=DispatchSource.makeSignalSource(signal:SIGTERM,queue:.main)
                interrupt.setEventHandler{interrupted=true};terminate.setEventHandler{interrupted=true};interrupt.resume();terminate.resume()
                defer{interrupt.cancel();terminate.cancel();controller.stop()}
                try await controller.start(compiled:compiled,configuration:config,baseURL:configURL.deletingLastPathComponent(),settings:settings,routeSystemOutput:!arguments.contains("--no-route"))
                print("LIVE_READY \(controller.status)");fflush(stdout)
                let start=Date();var inputPeak:Double = -1000,outputPeak:Double = -1000,clipped=0
                var sequence=[configURL], measurements:[[String:Any]]=[]
                if let folder=option("--sequence") {
                    let children=try FileManager.default.contentsOfDirectory(at:URL(fileURLWithPath:folder),includingPropertiesForKeys:nil)
                    sequence += children.sorted{$0.lastPathComponent<$1.lastPathComponent}.map{$0.appendingPathComponent("configuration.json")}.filter{$0.standardizedFileURL != configURL}
                }
                for (index,url) in sequence.enumerated() {
                    guard controller.isRunning,!interrupted else{break}
                    let current=try FieldConfiguration.read(from:url)
                    if index>0 {
                        let field=try FIRCompiler.compile(current,baseURL:url.deletingLastPathComponent())
                        try await controller.update(compiled:field,configuration:current,baseURL:url.deletingLastPathComponent())
                    }
                    print("LIVE_CONFIG \(url.deletingLastPathComponent().lastPathComponent)");fflush(stdout)
                    let segmentStart=Date();var samples:[[String:Double]]=[]
                    while controller.isRunning,!interrupted,(seconds<=0 || Date().timeIntervalSince(segmentStart)<seconds) {
                        try await Task.sleep(nanoseconds:500_000_000)
                        inputPeak=max(inputPeak,controller.levels.capturePeak.max() ?? -1000);outputPeak=max(outputPeak,controller.levels.playbackPeak.max() ?? -1000);clipped=max(clipped,controller.levels.clippedSamples)
                        if let input=LoudnessBalance.stereoRMS(controller.levels.captureRMS),let output=LoudnessBalance.stereoRMS(controller.levels.playbackRMS),input > -100,output > -120 {
                            samples.append(["seconds":Date().timeIntervalSince(segmentStart),"input_rms_dbfs":input,"output_rms_dbfs":output,"gain_db":output-input,"trim_db":controller.levels.balanceTrimDb])
                        }
                    }
                    measurements.append(["configuration":url.path,"target_gain_db":current.safety.preampDb+LoudnessCalibration.reserveDb,"samples":samples])
                }
                let liveError=controller.errorMessage
                controller.stop()
                let report:[String:Any]=["seconds":Date().timeIntervalSince(start),"capture_peak_dbfs":inputPeak,"playback_peak_dbfs":outputPeak,"clipped_samples":clipped,"original_output_uid":original,"restored_output_uid":try AudioDeviceCatalog.defaultOutput()?.uid ?? "","error":liveError ?? controller.errorMessage ?? "","routed":!arguments.contains("--no-route"),"log_path":controller.logURL.path,"measurements":measurements]
                printJSON(report)
                if let output=option("--report") {try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:output),options:.atomic)}
                if let liveError {throw LiveAudioError.message(liveError)}
            default:throw LiveAudioError.message(usage)
            }
        } catch {fputs("\(error.localizedDescription)\n",stderr);exit(1)}
    }
    static let usage="""
    fieldweave-audio devices
    fieldweave-audio run CONFIG.json --capture DEVICE_UID --playback DEVICE_UID [--seconds 30] [--sequence PACKAGE_DIRECTORY] [--no-route] [--support DIR] [--report FILE]
    fieldweave-audio restore [--support DIR]
    run applies the compiled FIR matrix through CamillaDSP and restores the prior media output on exit. --no-route leaves the system output untouched.
    --sequence hot-loads each exported package using the same running controller; --seconds is the dwell per configuration. Reports include measured stereo RMS gain and automatic trim.
    """
}

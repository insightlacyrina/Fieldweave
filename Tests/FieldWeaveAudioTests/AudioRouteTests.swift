import Foundation
import Testing
import CoreAudio
import FieldWeaveCore
@testable import FieldWeaveAudio

@Suite struct FieldWeaveAudioRouteTests {
    func device(_ uid:String,_ name:String,_ input:Int,_ output:Int,virtual:Bool)->AudioDevice {
        AudioDevice(objectID:1,uid:uid,name:name,inputChannels:input,outputChannels:output,sampleRate:48000,transportType:virtual ? kAudioDeviceTransportTypeVirtual:kAudioDeviceTransportTypeUSB)
    }
    @Test func testRouteRequiresExactPhysicalOutputAndStereoLoopback()throws {
        let capture=device("capture","BlackHole 2ch",2,2,virtual:true),headphones=device("phones","NICEHCK NK1 Ultra",0,2,virtual:false),speakers=device("speakers","MacBook Speakers",0,2,virtual:false)
        let settings=AudioRouteSettings(captureUID:"capture",playbackUID:"phones")
        #expect(try settings.resolve(in:[capture,headphones,speakers]).playback.uid=="phones")
        #expect(throws:(any Error).self){try settings.resolve(in:[capture,speakers])}
        #expect(throws:(any Error).self){try AudioRouteSettings(captureUID:"capture",playbackUID:"capture").resolve(in:[capture,headphones])}
        #expect(throws:(any Error).self){try settings.resolve(in:[device("capture","Microphone",2,0,virtual:false),headphones])}
    }
    @Test func testDuplicateDeviceNamesAreRejected()throws {
        let capture=device("capture","BlackHole 2ch",2,2,virtual:true),headphones=device("phones","USB DAC",0,2,virtual:false),other=device("other","USB DAC",0,2,virtual:false)
        #expect(throws:(any Error).self){try AudioRouteSettings(captureUID:"capture",playbackUID:"phones").resolve(in:[capture,headphones,other])}
    }
    @Test func testGeneratedConfigurationUsesEveryMatrixRouteAndEscapesNames()throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("FieldWeaveAudioTests-"+UUID().uuidString,isDirectory:true)
        defer{try? FileManager.default.removeItem(at:root)}
        var config=FieldConfiguration();config.design.widthTaps=65
        let compiled=try FIRCompiler.compile(config,baseURL:root)
        try FieldExporter.export(compiled,configuration:config,to:root,baseURL:root)
        let yaml=try LiveConfiguration.yaml(exportDirectory:root,capture:device("capture","BlackHole 2ch",2,2,virtual:true),playback:device("phones","Listener's DAC",0,2,virtual:false))
        #expect(yaml.contains("device: 'Listener''s DAC'"));#expect(!yaml.contains("REPLACE_WITH"))
        #expect(yaml.contains("resampler: {type: AsyncSinc, profile: Balanced}"))
        for name in ["LL","LR","RL","RR"] {#expect(yaml.contains(root.appendingPathComponent(name+".wav").path))}
        #expect(yaml.contains("names: [LR]"));#expect(yaml.contains("names: [RL]"))
        #expect(yaml.contains("names: [FWBalanceCalibration, FWBalanceTrim, FWBalanceCeiling]"))
        #expect(yaml.contains("fader: Aux1, ramp_time: 500"))
        #expect(yaml.contains("clip_limit: -1.0"))
        #expect(FileManager.default.fileExists(atPath:root.appendingPathComponent("live-loudness.json").path))
        let engine="/usr/local/bin/camilladsp"
        if FileManager.default.isExecutableFile(atPath:engine) {
            // Use available real devices for syntax validation only; -c opens no audio.
            let checkURL=root.appendingPathComponent("live-check.yml")
            try yaml.write(to:checkURL,atomically:true,encoding:.utf8)
            let process=Process();process.executableURL=URL(fileURLWithPath:engine)
            process.arguments=["-c",checkURL.path]
            let pipe=Pipe();process.standardOutput=pipe;process.standardError=pipe
            try process.run();let data=pipe.fileHandleForReading.readDataToEndOfFile();process.waitUntilExit()
            #expect(process.terminationStatus==0,Comment(rawValue:String(decoding:data,as:UTF8.self)))
        }
    }
}

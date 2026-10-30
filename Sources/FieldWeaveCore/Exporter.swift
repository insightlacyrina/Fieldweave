import Foundation

public enum FieldExporter {
    public static func export(_ compiled:CompiledField,configuration:FieldConfiguration,to directory:URL,baseURL:URL)throws {
        try validateCompiled(compiled)
        try FIRCompiler.validate(configuration)
        guard compiled.report.sampleRate==configuration.sampleRate else{throw FieldError.invalid("Compiled sample rate does not match configuration")}
        let fm=FileManager.default,target=directory.standardizedFileURL,parent=target.deletingLastPathComponent()
        guard !fm.fileExists(atPath:target.path) else{throw FieldError.invalid("Export destination already exists; choose a new folder")}
        try fm.createDirectory(at:parent,withIntermediateDirectories:true)
        let staging=parent.appendingPathComponent(".fieldweave-export-"+UUID().uuidString,isDirectory:true);try fm.createDirectory(at:staging,withIntermediateDirectories:false)
        defer{try? fm.removeItem(at:staging)}
        var portable=configuration
        let assets=staging.appendingPathComponent("assets",isDirectory:true);var index=0
        func copyAsset(_ asset:IRAsset)throws->IRAsset {let source=URL(fileURLWithPath:asset.path,relativeTo:baseURL).standardizedFileURL.resolvingSymlinksInPath();guard source.pathExtension.lowercased()=="wav" else{throw FieldError.invalid("Export only supports WAV assets")};_ = try WAVFile.read(source);try fm.createDirectory(at:assets,withIntermediateDirectories:true);index+=1;let name="import-\(index).wav";try fm.copyItem(at:source,to:assets.appendingPathComponent(name));return IRAsset(path:"assets/"+name,channel:asset.channel)}
        if let originals=portable.headphone.fir {var copied:[String:IRAsset]=[:];for key in originals.keys.sorted(){copied[key]=try copyAsset(originals[key]!)};portable.headphone.fir=copied}
        if let originals=portable.externalization.paths {var copied:[String:IRAsset]=[:];for key in originals.keys.sorted(){copied[key]=try copyAsset(originals[key]!)};portable.externalization.paths=copied}
        for (key,row,col) in [("LL",0,0),("LR",1,0),("RL",0,1),("RR",1,1)] {try WAVFile.write(staging.appendingPathComponent(key+".wav"),sampleRate:compiled.report.sampleRate,channels:[compiled.matrix[row][col]])}
        try portable.jsonData().write(to:staging.appendingPathComponent("configuration.json"))
        try FieldConfiguration.encoder.encode(compiled.report).write(to:staging.appendingPathComponent("report.json"))
        if compiled.report.centerElevationDegrees != 0 {
            guard let profile=compiled.report.centerElevationProfile,
                  let bankURL=Bundle.module.url(forResource:"manifest",withExtension:"json",subdirectory:"Resources/CenterElevation")
                    ?? Bundle.module.url(forResource:"manifest",withExtension:"json",subdirectory:"CenterElevation"),
                  let bank=try JSONSerialization.jsonObject(with:Data(contentsOf:bankURL)) as? [String:Any],
                  let profiles=bank["profiles"] as? [[String:Any]],let selected=profiles.first(where:{$0["id"] as? String==profile}) else {
                throw FieldError.invalid("The center-height measurement provenance is unavailable")
            }
            let record:[String:Any]=["active_profile":profile,"active_elevation_degrees":compiled.report.centerElevationDegrees,
                                     "strategy":compiled.report.centerElevationStrategy,"bank_version":bank["version"] ?? 1,
                                     "repository":bank["repository"] ?? "", "commit":bank["commit"] ?? "",
                                     "license":bank["license"] ?? "", "measurement_profile":selected,
                                     "reopening":"Native editing requires FieldWeave 0.4 or later with this bundled bank. Final LL/LR/RL/RR WAVs already contain the height processing."]
            try JSONSerialization.data(withJSONObject:record,options:[.prettyPrinted,.sortedKeys]).write(to:staging.appendingPathComponent("center-height-provenance.json"))
            try fm.copyItem(at:bankURL.deletingLastPathComponent().appendingPathComponent("ATTRIBUTION.txt"),to:staging.appendingPathComponent("CENTER-HEIGHT-ATTRIBUTION.txt"))
        }
        let n=max(16384,NativeFFT.size(compiled.report.matrixTaps*2));let paths=[("LL",0,0),("LR",1,0),("RL",0,1),("RR",1,1)];let responses=paths.map{NativeFFT.magnitude(compiled.matrix[$0.1][$0.2],n:n)}
        var csv="frequency_hz,LL_magnitude,LR_magnitude,RL_magnitude,RR_magnitude\n";for k in 0...n/2 {csv+="\(Double(k)*Double(compiled.report.sampleRate)/Double(n)),"+responses.map{String($0[k])}.joined(separator:",")+"\n"};try csv.write(to:staging.appendingPathComponent("response.csv"),atomically:false,encoding:.utf8)
        let common="""
        filters:
          LL: {type: Conv, parameters: {type: Wav, filename: 'LL.wav', channel: 0}}
          LR: {type: Conv, parameters: {type: Wav, filename: 'LR.wav', channel: 0}}
          RL: {type: Conv, parameters: {type: Wav, filename: 'RL.wav', channel: 0}}
          RR: {type: Conv, parameters: {type: Wav, filename: 'RR.wav', channel: 0}}
        mixers:
          split:
            channels: {in: 2, out: 4}
            mapping:
              - {dest: 0, sources: [{channel: 0, gain: 1.0, scale: linear}]}
              - {dest: 1, sources: [{channel: 0, gain: 1.0, scale: linear}]}
              - {dest: 2, sources: [{channel: 1, gain: 1.0, scale: linear}]}
              - {dest: 3, sources: [{channel: 1, gain: 1.0, scale: linear}]}
          sum:
            channels: {in: 4, out: 2}
            mapping:
              - {dest: 0, sources: [{channel: 0, gain: 1.0, scale: linear}, {channel: 2, gain: 1.0, scale: linear}]}
              - {dest: 1, sources: [{channel: 1, gain: 1.0, scale: linear}, {channel: 3, gain: 1.0, scale: linear}]}
        pipeline:
          - {type: Mixer, name: split}
          - {type: Filter, channels: [0], names: [LL]}
          - {type: Filter, channels: [1], names: [LR]}
          - {type: Filter, channels: [2], names: [RL]}
          - {type: Filter, channels: [3], names: [RR]}
          - {type: Mixer, name: sum}
        """
        let realtime="""
        # Template only. Review both device names. Run CamillaDSP from this package directory.
        description: 'FieldWeave native Q -> Width -> Center -> Matrix IR -> Crossfeed -> Safety'
        devices:
          samplerate: \(compiled.report.sampleRate)
          chunksize: 256
          enable_rate_adjust: true
          capture: {type: CoreAudio, channels: 2, device: 'REPLACE_WITH_CAPTURE_DEVICE'}
          playback: {type: CoreAudio, channels: 2, device: 'REPLACE_WITH_PLAYBACK_DEVICE'}
        \(common)
        """
        let offline="""
        # Run CamillaDSP from this package directory. Supply stereo interleaved F64_LE input.f64.
        description: 'FieldWeave offline raw-file convolution'
        devices:
          samplerate: \(compiled.report.sampleRate)
          chunksize: 256
          capture: {type: RawFile, channels: 2, filename: 'input.f64', format: F64_LE, extra_samples: \(compiled.report.matrixTaps-1)}
          playback: {type: File, channels: 2, filename: 'camilla-output.f64', format: F64_LE}
        \(common)
        """
        try realtime.write(to:staging.appendingPathComponent("camilladsp-coreaudio.yml"),atomically:false,encoding:.utf8);try offline.write(to:staging.appendingPathComponent("camilladsp-offline.yml"),atomically:false,encoding:.utf8)
        try """
        FieldWeave portable FIR package
        
        configuration.json can be re-opened in FieldWeave; imported WAV assets are bundled under assets/.
        LL = left source -> left ear; LR = left source -> right ear;
        RL = right source -> left ear; RR = right source -> right ear.
        Each filter is mono IEEE Float32 WAV. FIR sample rate: \(compiled.report.sampleRate) Hz.
        CamillaDSP YAML files are templates; run from this directory so relative asset paths resolve.
        CoreAudio device names must be reviewed manually. Export does not install drivers or change routing.
        Offline CamillaDSP template uses interleaved F64_LE raw files, not WAV.
        response.csv contains linear magnitudes of the final four transfer paths.
        Active center-height designs include measured-donor provenance and CC BY 4.0 attribution.
        Height processing is already included in the four final FIR WAVs; it must not be applied again.
        
        """.write(to:staging.appendingPathComponent("README.txt"),atomically:false,encoding:.utf8)
        // A same-parent rename publishes all files together; an existing destination is rejected.
        guard !fm.fileExists(atPath:target.path) else{throw FieldError.invalid("Destination appeared during export")};try fm.moveItem(at:staging,to:target)
    }
}

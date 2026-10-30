import Foundation
import Combine
import AVFoundation
import Darwin
import FieldWeaveCore

public struct LiveAudioLevels: Equatable, Sendable {
    public var capturePeak:[Double]=[]
    public var playbackPeak:[Double]=[]
    public var captureRMS:[Double]=[]
    public var playbackRMS:[Double]=[]
    public var balanceTrimDb:Double=0
    public var clippedSamples:Int=0
    public var processingLoad:Double=0
    public init() {}
    public var hasInput:Bool {capturePeak.contains{$0.isFinite && $0 > -100}}
    public var hasOutput:Bool {playbackPeak.contains{$0.isFinite && $0 > -100}}
}

private struct RouteReceipt: Codable {
    var previousOutputUID:String
    var captureUID:String
    var playbackUID:String
    var processID:Int32
    var executablePath:String
    var ownsOutput:Bool
    var previousCaptureMute:AudioDeviceMuteState?
}

@MainActor public final class LiveAudioController: ObservableObject {
    @Published public private(set) var devices:[AudioDevice]=[]
    @Published public private(set) var isRunning=false
    @Published public private(set) var isStarting=false
    @Published public private(set) var status="Stopped"
    @Published public private(set) var errorMessage:String?
    @Published public private(set) var levels=LiveAudioLevels()
    @Published public private(set) var activeSettings:AudioRouteSettings?
    @Published public private(set) var activeConfiguration:FieldConfiguration?
    public let supportDirectory:URL
    public var settingsURL:URL {supportDirectory.appendingPathComponent("AudioRoute.json")}
    public var logURL:URL {supportDirectory.appendingPathComponent("LiveAudio.log")}
    private var receiptURL:URL {supportDirectory.appendingPathComponent("LiveAudioRoute.json")}
    private var process:Process?
    private var socket:CamillaSocket?
    private var monitor:Task<Void,Never>?
    private var runDirectory:URL?
    private var pendingExports:Set<URL>=[]
    private var generation=UUID()
    private var updateGeneration=UUID()
    private var receipt:RouteReceipt?
    private var logHandle:FileHandle?
    private var routeSystemOutput=true
    private var loudnessBalance:LoudnessBalance?
    private var balanceReadyAt=Date.distantFuture
    private var balanceTransition:UUID?

    public init(supportDirectory:URL?=nil) {
        self.supportDirectory=supportDirectory ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("FieldWeave",isDirectory:true)
        refreshDevices()
    }
    public func refreshDevices(){do{devices=try AudioDeviceCatalog.devices()}catch{errorMessage=error.localizedDescription}}
    public func savedSettings()->AudioRouteSettings? {try? AudioRouteSettings.load(from:settingsURL)}
    public func saveSettings(_ settings:AudioRouteSettings)throws {try settings.save(to:settingsURL)}

    /// Recover only a process recorded by this controller, never other CamillaDSP instances.
    public func recoverInterruptedRoute()throws {
        guard process==nil,FileManager.default.fileExists(atPath:receiptURL.path) else{return}
        let saved=try JSONDecoder().decode(RouteReceipt.self,from:Data(contentsOf:receiptURL))
        var path=[CChar](repeating:0,count:4096) // PROC_PIDPATHINFO_MAXSIZE = 4 * MAXPATHLEN on macOS.
        if proc_pidpath(saved.processID,&path,UInt32(path.count))>0 {
            let runningPath=String(cString:path)
            if URL(fileURLWithPath:runningPath).resolvingSymlinksInPath()==URL(fileURLWithPath:saved.executablePath).resolvingSymlinksInPath() {_ = kill(saved.processID,SIGTERM)}
        }
        try restore(saved)
        try FileManager.default.removeItem(at:receiptURL)
        status="Previous audio output restored"
    }

    public func start(compiled:CompiledField,configuration:FieldConfiguration,baseURL:URL,settings:AudioRouteSettings,routeSystemOutput:Bool=true)async throws {
        try validateSafety(compiled)
        guard !isStarting else{throw LiveAudioError.message("Audio is already starting")}
        if isRunning {stop();if let errorMessage {throw LiveAudioError.message(errorMessage)}}
        try recoverInterruptedRoute()
        errorMessage=nil;isStarting=true;status="Preparing live audio…"
        self.routeSystemOutput=routeSystemOutput
        let token=UUID();generation=token
        defer{if generation==token {isStarting=false}}
        do {
            refreshDevices()
            let route=try settings.resolve(in:devices)
            guard FileManager.default.isExecutableFile(atPath:settings.executablePath) else {throw LiveAudioError.message("CamillaDSP is not installed at \(settings.executablePath)")}
            switch AVCaptureDevice.authorizationStatus(for:.audio) {
            case .denied,.restricted:throw LiveAudioError.message("Allow FieldWeave microphone access in System Settings to capture the virtual audio device")
            case .notDetermined:
                guard await AVCaptureDevice.requestAccess(for:.audio) else{throw LiveAudioError.message("Microphone permission is required for virtual audio capture")}
            default:break
            }
            guard generation==token else{throw CancellationError()}
            let root=supportDirectory.appendingPathComponent("Live",isDirectory:true)
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
            let directory=root.appendingPathComponent(UUID().uuidString,isDirectory:true)
            pendingExports.insert(directory)
            defer {pendingExports.remove(directory);pruneExports()}
            try await Task.detached(priority:.userInitiated) {try FieldExporter.export(compiled,configuration:configuration,to:directory,baseURL:baseURL)}.value
            guard generation==token else{throw CancellationError()}
            let yaml=try LiveConfiguration.yaml(exportDirectory:directory,capture:route.capture,playback:route.playback)
            let yamlURL=directory.appendingPathComponent("live.yml")
            try yaml.write(to:yamlURL,atomically:true,encoding:.utf8)
            try checkConfiguration(executable:settings.executablePath,yamlURL:yamlURL)
            let port=Int.random(in:19000...39000)
            let child=Process();child.executableURL=URL(fileURLWithPath:settings.executablePath)
            child.arguments=["-a","127.0.0.1","-p",String(port),"-l","info","--gain1=-40",yamlURL.path];child.currentDirectoryURL=directory
            FileManager.default.createFile(atPath:logURL.path,contents:nil)
            let log=try FileHandle(forWritingTo:logURL);logHandle=log;child.standardOutput=log;child.standardError=log
            let previous=try AudioDeviceCatalog.defaultOutput()?.uid
            guard let previous else{throw LiveAudioError.message("Cannot determine the current output device")}
            process=child;runDirectory=directory
            child.terminationHandler={ [weak self] finished in Task {@MainActor in
                guard let self,self.process===finished else{return}
                self.fail("CamillaDSP stopped (exit \(finished.terminationStatus)). See \(self.logURL.path)")
            }}
            try child.run()
            let muteSnapshot=routeSystemOutput ? try AudioDeviceCatalog.muteState(uid:route.capture.uid):nil
            let saved=RouteReceipt(previousOutputUID:previous==route.capture.uid ? route.playback.uid:previous,captureUID:route.capture.uid,playbackUID:route.playback.uid,processID:child.processIdentifier,executablePath:settings.executablePath,ownsOutput:routeSystemOutput,previousCaptureMute:muteSnapshot)
            receipt=saved;try JSONEncoder().encode(saved).write(to:receiptURL,options:.atomic)
            status="Opening audio devices…"
            var connection:CamillaSocket?
            var lastError:Error=LiveAudioError.message("CamillaDSP did not start")
            for _ in 0..<14 {
                guard generation==token,child.isRunning else{throw LiveAudioError.message("CamillaDSP stopped during startup. See \(logURL.path)")}
                let candidate=CamillaSocket(port:port)
                do {
                    let configPath=try await candidate.value("GetConfigFilePath")
                    guard configPath==yamlURL.path else{throw LiveAudioError.message("The audio control port is occupied by another process")}
                    let state=try await candidate.value("GetState")
                    if state=="Running" || state=="Paused" {connection=candidate;break}
                    lastError=LiveAudioError.message("Audio state: \(state)")
                } catch {lastError=error}
                await candidate.close()
                try await Task.sleep(nanoseconds:250_000_000)
            }
            guard generation==token,let connection else{throw lastError}
            socket=connection
            // Re-resolve immediately before routing; unplugging must never select the default speakers.
            _ = try settings.resolve(in:AudioDeviceCatalog.devices())
            if routeSystemOutput {
                if let muteSnapshot {
                    try AudioDeviceCatalog.setMuteState(uid:route.capture.uid,state:AudioDeviceMuteState(inputMuted:muteSnapshot.inputMuted.map{_ in false},outputMuted:muteSnapshot.outputMuted.map{_ in false}))
                }
                try AudioDeviceCatalog.setDefaultOutput(uid:route.capture.uid)
            }
            try settings.save(to:settingsURL)
            loudnessBalance=LoudnessBalance(calibration:try LiveConfiguration.calibration(compiled:compiled,configuration:configuration))
            // Start quietly, then let the engine ramp the shared stereo fader.
            _ = try await connection.request("SetFaderVolume",argument:[1,0])
            guard generation==token else{throw CancellationError()}
            balanceReadyAt=Date().addingTimeInterval(1.5)
            isRunning=true;isStarting=false;activeSettings=settings;activeConfiguration=configuration;status="Listening · \(route.playback.name)"
            beginMonitoring(token:token)
        } catch {
            if generation==token {stop();errorMessage=error.localizedDescription;status="Audio needs attention"}
            throw error
        }
    }

    /// Applies the compiled FIR, followed by the app's always-on level balance and sample ceiling.
    public func update(compiled:CompiledField,configuration:FieldConfiguration,baseURL:URL)async throws {
        try validateSafety(compiled)
        let updateToken=UUID();updateGeneration=updateToken
        guard isRunning,let settings=activeSettings,let connection=socket else{return}
        if configuration.sampleRate != activeConfiguration?.sampleRate {
            try await start(compiled:compiled,configuration:configuration,baseURL:baseURL,settings:settings,routeSystemOutput:routeSystemOutput);return
        }
        let token=generation
        let route=try settings.resolve(in:AudioDeviceCatalog.devices())
        let directory=supportDirectory.appendingPathComponent("Live/"+UUID().uuidString,isDirectory:true)
        pendingExports.insert(directory)
        defer {pendingExports.remove(directory);pruneExports()}
        try await Task.detached(priority:.userInitiated) {try FieldExporter.export(compiled,configuration:configuration,to:directory,baseURL:baseURL)}.value
        guard generation==token,updateGeneration==updateToken,isRunning else{return}
        let yaml=try LiveConfiguration.yaml(exportDirectory:directory,capture:route.capture,playback:route.playback)
        let yamlURL=directory.appendingPathComponent("live.yml");try yaml.write(to:yamlURL,atomically:true,encoding:.utf8)
        try checkConfiguration(executable:settings.executablePath,yamlURL:yamlURL)
        let balance=LoudnessBalance(calibration:try LiveConfiguration.calibration(compiled:compiled,configuration:configuration))
        // Export can overlap, but fader/FIR commits must complete in order. A newer
        // request can supersede this one until SetConfig is sent; after that, record
        // the accepted pipeline before the next commit is allowed to begin.
        while balanceTransition != nil {
            try await Task.sleep(nanoseconds:25_000_000)
            guard generation==token,updateGeneration==updateToken,isRunning else{return}
        }
        guard generation==token,updateGeneration==updateToken,isRunning else{return}
        balanceTransition=updateToken
        balanceReadyAt = .distantFuture
        defer {if generation==token,balanceTransition==updateToken {balanceTransition=nil;balanceReadyAt=Date().addingTimeInterval(1.5)}}
        // A positive trim learned for an old filter must never reach a newly loaded
        // filter. Finish the stereo ramp before swapping calibration and FIR together.
        let heldTrim=min(0,loudnessBalance?.trimDb ?? 0)
        _ = try await connection.request("SetFaderVolume",argument:[1.0,heldTrim])
        guard generation==token,isRunning else{return}
        loudnessBalance?.resetTrim(to:heldTrim)
        try await Task.sleep(nanoseconds:550_000_000)
        guard generation==token,updateGeneration==updateToken,isRunning else{return}
        _ = try await connection.request("SetConfig",argument:yaml)
        guard generation==token,isRunning else{return}
        var accepted=false
        for _ in 0..<20 {
            let json=try await connection.value("GetConfigJson")
            guard generation==token,isRunning else{return}
            if let root=try JSONSerialization.jsonObject(with:Data(json.utf8)) as? [String:Any],
               let filters=root["filters"] as? [String:Any],let ll=filters["LL"] as? [String:Any],
               let parameters=ll["parameters"] as? [String:Any],
               parameters["filename"] as? String==directory.appendingPathComponent("LL.wav").path {
                accepted=true;break
            }
            try await Task.sleep(nanoseconds:25_000_000)
        }
        guard accepted else{throw LiveAudioError.message("CamillaDSP did not apply the new balanced pipeline")}
        _ = try await connection.request("SetFaderVolume",argument:[1,0])
        guard generation==token,isRunning else{return}
        loudnessBalance=balance;levels.balanceTrimDb=0
        activeConfiguration=configuration;runDirectory=directory;errorMessage=nil;status="Listening · \(route.playback.name)"
    }

    public func stop() {
        generation=UUID();updateGeneration=UUID();monitor?.cancel();monitor=nil;isStarting=false;isRunning=false
        loudnessBalance=nil;balanceReadyAt = .distantFuture;balanceTransition=nil
        let child=process;process=nil
        if let connection=socket {Task{await connection.close()}};socket=nil
        if let saved=receipt {do{try restore(saved);try? FileManager.default.removeItem(at:receiptURL);receipt=nil;errorMessage=nil}catch{errorMessage=error.localizedDescription}}
        if child?.isRunning==true {child?.terminate()}
        try? logHandle?.close();logHandle=nil
        activeSettings=nil;activeConfiguration=nil;levels=LiveAudioLevels();status=errorMessage==nil ? "Stopped · previous output restored":"Output restoration needs attention"
        pruneExports()
    }

    /// Keep the active matrix, in-flight exports, and three recent complete packages.
    private func pruneExports() {
        let fm=FileManager.default,root=supportDirectory.appendingPathComponent("Live",isDirectory:true)
        guard let children=try? fm.contentsOfDirectory(at:root,includingPropertiesForKeys:[.contentModificationDateKey],options:.skipsHiddenFiles) else{return}
        let completed=children.filter{UUID(uuidString:$0.lastPathComponent) != nil && fm.fileExists(atPath:$0.appendingPathComponent("configuration.json").path)}.sorted {
            ((try? $0.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }
        var keep=pendingExports.union(completed.prefix(3))
        if let runDirectory {keep.insert(runDirectory)}
        for directory in completed where !keep.contains(directory) {try? fm.removeItem(at:directory)}
    }

    private func restore(_ saved:RouteReceipt)throws {
        // Respect an output selection the user made while processing was running.
        var failures:[String]=[]
        do {if saved.ownsOutput,try AudioDeviceCatalog.defaultOutput()?.uid==saved.captureUID {try AudioDeviceCatalog.setDefaultOutput(uid:saved.previousOutputUID)}}
        catch{failures.append(error.localizedDescription)}
        // Attempt mute restoration even if the previous physical output was unplugged.
        if let mute=saved.previousCaptureMute {
            do {try AudioDeviceCatalog.setMuteState(uid:saved.captureUID,state:mute)}
            catch{failures.append(error.localizedDescription)}
        }
        if !failures.isEmpty {throw LiveAudioError.message(failures.joined(separator:"; "))}
    }
    private func fail(_ message:String) {stop();errorMessage=message;status="Audio stopped safely"}
    private func validateSafety(_ field:CompiledField)throws {
        guard field.report.boundedInputPeakBound.isFinite,field.report.boundedInputPeakBound<=1 else{throw LiveAudioError.message("The FIR may exceed full scale. Enable automatic headroom or reduce the preamp before live playback")}
    }
    private func checkConfiguration(executable:String,yamlURL:URL)throws {
        let child=Process();child.executableURL=URL(fileURLWithPath:executable);child.arguments=["-c",yamlURL.path]
        let output=Pipe();child.standardOutput=output;child.standardError=output
        try child.run();let data=output.fileHandleForReading.readDataToEndOfFile();child.waitUntilExit()
        guard child.terminationStatus==0 else{throw LiveAudioError.message("Invalid live audio configuration: \(String(decoding:data,as:UTF8.self))")}
    }
    private func beginMonitoring(token:UUID) {
        monitor=Task { [weak self] in
            while !Task.isCancelled {
                guard let self,self.generation==token,self.isRunning,let settings=self.activeSettings,let connection=self.socket else{return}
                do {
                    let all=try AudioDeviceCatalog.devices();_ = try settings.resolve(in:all)
                    self.devices=all
                    if self.routeSystemOutput,try AudioDeviceCatalog.defaultOutput()?.uid != settings.captureUID {self.stop();self.status="Stopped · output changed in macOS";return}
                    let state=try await connection.value("GetState")
                    guard self.generation==token,self.isRunning,!Task.isCancelled else{return}
                    guard ["Running","Paused","Starting"].contains(state) else {throw LiveAudioError.message("CamillaDSP is \(state). Reconnect the output and restart audio")}
                    let data=try await connection.request("GetSignalLevelsSinceLast")
                    guard self.generation==token,self.isRunning,!Task.isCancelled else{return}
                    if let root=try JSONSerialization.jsonObject(with:data) as? [String:Any],let response=root["GetSignalLevelsSinceLast"] as? [String:Any],let values=response["value"] as? [String:Any] {
                        self.levels.capturePeak=values["capture_peak"] as? [Double] ?? []
                        self.levels.playbackPeak=values["playback_peak"] as? [Double] ?? []
                        self.levels.captureRMS=values["capture_rms"] as? [Double] ?? []
                        self.levels.playbackRMS=values["playback_rms"] as? [Double] ?? []
                        if state=="Running",Date()>=self.balanceReadyAt,
                           let trim=self.loudnessBalance?.observe(captureRMS:self.levels.captureRMS,playbackRMS:self.levels.playbackRMS,playbackPeak:self.levels.playbackPeak,seconds:0.5) {
                            _ = try await connection.request("SetFaderVolume",argument:[1.0,trim])
                            guard self.generation==token,self.isRunning,!Task.isCancelled else{return}
                            self.levels.balanceTrimDb=trim
                        }
                    }
                    let clipped=try await connection.request("GetClippedSamples")
                    guard self.generation==token,self.isRunning,!Task.isCancelled else{return}
                    if let root=try JSONSerialization.jsonObject(with:clipped) as? [String:Any],let response=root["GetClippedSamples"] as? [String:Any] {self.levels.clippedSamples=response["value"] as? Int ?? 0}
                    if self.levels.clippedSamples>0 {throw LiveAudioError.message("Clipping detected. Lower the preamp or enable automatic headroom before restarting")}
                    self.status=self.levels.hasInput ? "Processing · \(all.first{$0.uid==settings.playbackUID}?.name ?? "Headphones")":"Listening · waiting for audio"
                } catch {
                    guard self.generation==token,!Task.isCancelled else{return};self.fail(error.localizedDescription);return
                }
                try? await Task.sleep(nanoseconds:500_000_000)
            }
        }
    }
}

import Foundation
import CoreAudio
import AudioToolbox

public struct AudioDevice: Codable, Equatable, Identifiable, Sendable {
    public var id: String { uid }
    public var objectID: UInt32
    public var uid: String
    public var name: String
    public var inputChannels: Int
    public var outputChannels: Int
    public var sampleRate: Double
    public var transportType: UInt32
    public var isAlive: Bool
    public var isVirtual: Bool { [kAudioDeviceTransportTypeVirtual,kAudioDeviceTransportTypeAggregate,kAudioDeviceTransportTypeAutoAggregate].contains(transportType) || ["blackhole", "background music", "parrot", "soundflower"].contains(where: {name.lowercased().contains($0)}) }
    public init(objectID:UInt32,uid:String,name:String,inputChannels:Int,outputChannels:Int,sampleRate:Double,transportType:UInt32,isAlive:Bool=true) {
        self.objectID=objectID;self.uid=uid;self.name=name;self.inputChannels=inputChannels;self.outputChannels=outputChannels;self.sampleRate=sampleRate;self.transportType=transportType;self.isAlive=isAlive
    }
}

/// Only virtual-device master mute controls; physical device gain is never changed.
public struct AudioDeviceMuteState: Codable, Equatable, Sendable {
    public var inputMuted:Bool?
    public var outputMuted:Bool?
    public init(inputMuted:Bool?=nil,outputMuted:Bool?=nil) {self.inputMuted=inputMuted;self.outputMuted=outputMuted}
}

public enum AudioDeviceCatalog {
    private static func address(_ selector: AudioObjectPropertySelector,scope:AudioObjectPropertyScope=kAudioObjectPropertyScopeGlobal)->AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector:selector,mScope:scope,mElement:kAudioObjectPropertyElementMain)
    }
    private static func scalar<T>(_ object:AudioObjectID,_ selector:AudioObjectPropertySelector,initial:T)->T {
        var a=address(selector),value=initial,size=UInt32(MemoryLayout<T>.size)
        let status=withUnsafeMutableBytes(of:&value){AudioObjectGetPropertyData(object,&a,0,nil,&size,$0.baseAddress!)}
        guard status==noErr else{return initial};return value
    }
    private static func string(_ object:AudioObjectID,_ selector:AudioObjectPropertySelector)->String {
        var a=address(selector),value:Unmanaged<CFString>?,size=UInt32(MemoryLayout<CFString?>.size)
        let status=withUnsafeMutableBytes(of:&value){AudioObjectGetPropertyData(object,&a,0,nil,&size,$0.baseAddress!)}
        guard status==noErr,let value else{return ""};return value.takeRetainedValue() as String
    }
    private static func channels(_ object:AudioObjectID,scope:AudioObjectPropertyScope)->Int {
        var a=address(kAudioDevicePropertyStreamConfiguration,scope:scope),size:UInt32=0
        guard AudioObjectGetPropertyDataSize(object,&a,0,nil,&size)==noErr,size>0 else{return 0}
        let memory=UnsafeMutableRawPointer.allocate(byteCount:Int(size),alignment:MemoryLayout<AudioBufferList>.alignment);defer{memory.deallocate()}
        guard AudioObjectGetPropertyData(object,&a,0,nil,&size,memory)==noErr else{return 0}
        return UnsafeMutableAudioBufferListPointer(memory.assumingMemoryBound(to:AudioBufferList.self)).reduce(0){$0+Int($1.mNumberChannels)}
    }
    public static func devices() throws->[AudioDevice] {
        var a=address(kAudioHardwarePropertyDevices),size:UInt32=0
        try check(AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),&a,0,nil,&size),"Read audio devices")
        var ids=[AudioObjectID](repeating:0,count:Int(size)/MemoryLayout<AudioObjectID>.size)
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&a,0,nil,&size,&ids),"Read audio devices")
        return ids.map {id in AudioDevice(objectID:id,uid:string(id,kAudioDevicePropertyDeviceUID),name:string(id,kAudioObjectPropertyName),inputChannels:channels(id,scope:kAudioDevicePropertyScopeInput),outputChannels:channels(id,scope:kAudioDevicePropertyScopeOutput),sampleRate:scalar(id,kAudioDevicePropertyNominalSampleRate,initial:Double(0)),transportType:scalar(id,kAudioDevicePropertyTransportType,initial:UInt32(0)),isAlive:scalar(id,kAudioDevicePropertyDeviceIsAlive,initial:UInt32(0)) != 0)}.sorted{$0.name.localizedStandardCompare($1.name) == .orderedAscending}
    }
    public static func defaultOutput() throws->AudioDevice? {
        let id=scalar(AudioObjectID(kAudioObjectSystemObject),kAudioHardwarePropertyDefaultOutputDevice,initial:UInt32(0))
        return try devices().first{$0.objectID==id}
    }
    public static func setDefaultOutput(uid:String) throws {
        guard let device=try devices().first(where:{$0.uid==uid && $0.isAlive && $0.outputChannels>0}) else {throw LiveAudioError.message("Output device is unavailable: \(uid)")}
        var a=address(kAudioHardwarePropertyDefaultOutputDevice),id=device.objectID
        try check(AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject),&a,0,nil,UInt32(MemoryLayout<AudioObjectID>.size),&id),"Change default audio output")
        guard try defaultOutput()?.uid==uid else{throw LiveAudioError.message("macOS did not apply the requested audio output")}
    }
    public static func muteState(uid:String)throws->AudioDeviceMuteState {
        guard let device=try devices().first(where:{$0.uid==uid && $0.isAlive && $0.isVirtual}) else{throw LiveAudioError.message("The virtual audio device is unavailable")}
        func read(_ scope:AudioObjectPropertyScope)throws->Bool? {
            var a=address(kAudioDevicePropertyMute,scope:scope)
            guard AudioObjectHasProperty(device.objectID,&a) else{return nil}
            var value:UInt32=0,size=UInt32(MemoryLayout<UInt32>.size)
            try check(AudioObjectGetPropertyData(device.objectID,&a,0,nil,&size,&value),"Read virtual audio mute")
            return value != 0
        }
        return try AudioDeviceMuteState(inputMuted:read(kAudioDevicePropertyScopeInput),outputMuted:read(kAudioDevicePropertyScopeOutput))
    }
    public static func setMuteState(uid:String,state:AudioDeviceMuteState)throws {
        guard let device=try devices().first(where:{$0.uid==uid && $0.isAlive && $0.isVirtual}) else{throw LiveAudioError.message("The virtual audio device is unavailable")}
        var failures:[String]=[]
        for (scope,muted) in [(kAudioDevicePropertyScopeInput,state.inputMuted),(kAudioDevicePropertyScopeOutput,state.outputMuted)] {
            guard let muted else{continue}
            do {
                var a=address(kAudioDevicePropertyMute,scope:scope),value:UInt32=muted ? 1:0
                var current:UInt32=0,size=UInt32(MemoryLayout<UInt32>.size)
                try check(AudioObjectGetPropertyData(device.objectID,&a,0,nil,&size,&current),"Read virtual audio mute")
                if (current != 0)==muted {continue}
                try check(AudioObjectSetPropertyData(device.objectID,&a,0,nil,size,&value),"Change virtual audio mute")
                try check(AudioObjectGetPropertyData(device.objectID,&a,0,nil,&size,&current),"Verify virtual audio mute")
                guard (current != 0)==muted else{throw LiveAudioError.message("The virtual audio mute control did not apply")}
            }catch{failures.append(error.localizedDescription)}
        }
        if !failures.isEmpty {throw LiveAudioError.message(failures.joined(separator:"; "))}
    }
    private static func check(_ status:OSStatus,_ action:String)throws{if status != noErr {throw LiveAudioError.message("\(action) failed (CoreAudio \(status))")}}
}

public enum LiveAudioError: LocalizedError {
    case message(String)
    public var errorDescription:String? {switch self {case .message(let text):return text}}
}

public struct AudioRouteSettings: Codable, Equatable, Sendable {
    public var captureUID: String
    public var playbackUID: String
    public var executablePath: String
    public var autoStart: Bool
    public init(captureUID:String,playbackUID:String,executablePath:String=AudioRouteSettings.installedCamillaDSP,autoStart:Bool=false) {
        self.captureUID=captureUID;self.playbackUID=playbackUID;self.executablePath=executablePath;self.autoStart=autoStart
    }
    public static var installedCamillaDSP:String { ["/opt/homebrew/bin/camilladsp","/usr/local/bin/camilladsp"].first{FileManager.default.isExecutableFile(atPath:$0)} ?? "/usr/local/bin/camilladsp" }
    public func resolve(in devices:[AudioDevice])throws->(capture:AudioDevice,playback:AudioDevice) {
        guard captureUID != playbackUID else{throw LiveAudioError.message("Capture and playback must use different devices")}
        guard let capture=devices.first(where:{$0.uid==captureUID && $0.isAlive && $0.inputChannels>=2 && $0.outputChannels>=2 && $0.isVirtual}) else {throw LiveAudioError.message("The selected stereo virtual capture device is unavailable")}
        guard let playback=devices.first(where:{$0.uid==playbackUID && $0.isAlive && $0.outputChannels>=2 && !$0.isVirtual}) else {throw LiveAudioError.message("The selected physical headphone output is unavailable; reconnect it before starting")}
        // CamillaDSP CoreAudio currently selects by name. Reject duplicate names rather than silently using another UID.
        guard devices.filter({$0.name==capture.name && $0.inputChannels>=2}).count==1,devices.filter({$0.name==playback.name && $0.outputChannels>=2}).count==1 else {throw LiveAudioError.message("Audio device names are ambiguous; rename the duplicate device in Audio MIDI Setup")}
        return(capture,playback)
    }
    public func save(to url:URL)throws {try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true);try JSONEncoder().encode(self).write(to:url,options:.atomic)}
    public static func load(from url:URL)throws->Self {try JSONDecoder().decode(Self.self,from:Data(contentsOf:url))}
}

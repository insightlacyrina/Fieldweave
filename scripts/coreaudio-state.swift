import Foundation
import CoreAudio
import AudioToolbox

func address(_ selector:UInt32,_ scope:UInt32=kAudioObjectPropertyScopeGlobal)->AudioObjectPropertyAddress {AudioObjectPropertyAddress(mSelector:selector,mScope:scope,mElement:kAudioObjectPropertyElementMain)}
func scalar<T>(_ device:UInt32,_ selector:UInt32,_ scope:UInt32=kAudioObjectPropertyScopeGlobal,_ initial:T)->T? {
    var a=address(selector,scope),size=UInt32(MemoryLayout<T>.size),value=initial
    guard AudioObjectHasProperty(device,&a),AudioObjectGetPropertyData(device,&a,0,nil,&size,&value)==0 else{return nil}
    return value
}
var a=address(kAudioHardwarePropertyDevices),size:UInt32=0
AudioObjectGetPropertyDataSize(1,&a,0,nil,&size)
var ids=[UInt32](repeating:0,count:Int(size)/4)
AudioObjectGetPropertyData(1,&a,0,nil,&size,&ids)
var results:[[String:Any]]=[]
for id in ids {
    var name:CFString="" as CFString,n=UInt32(MemoryLayout<CFString>.size),a=address(kAudioObjectPropertyName)
    AudioObjectGetPropertyData(id,&a,0,nil,&n,&name)
    var item:[String:Any]=["id":id,"name":name as String]
    for (label,scope) in [("input",kAudioDevicePropertyScopeInput),("output",kAudioDevicePropertyScopeOutput)] {
        if let value=scalar(id,kAudioDevicePropertyMute,scope,UInt32(0)) {item[label+"_mute"]=value}
        if let value=scalar(id,kAudioDevicePropertyVolumeScalar,scope,Float(0)) {item[label+"_volume"]=value}
    }
    results.append(item)
}
let data=try JSONSerialization.data(withJSONObject:["devices":results,"default_output_id":scalar(1,kAudioHardwarePropertyDefaultOutputDevice,kAudioObjectPropertyScopeGlobal,UInt32(0)) ?? 0],options:[.prettyPrinted,.sortedKeys])
print(String(decoding:data,as:UTF8.self))

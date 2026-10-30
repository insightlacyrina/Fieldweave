import Foundation

public struct WAVData: Sendable {
    public var sampleRate:Int
    public var channels:[[Double]]
    public init(sampleRate:Int,channels:[[Double]]){self.sampleRate=sampleRate;self.channels=channels}
}
public enum WAVFile {
    public static func read(_ url:URL)throws->WAVData {
        let attributes=try FileManager.default.attributesOfItem(atPath:url.path)
        guard let size=attributes[.size] as? NSNumber,size.int64Value<=268_435_456 else{throw FieldError.invalid("WAV exceeds 256 MiB import limit")}
        let data=try Data(contentsOf:url),b=[UInt8](data)
        func fail(_ message:String)->FieldError{.invalid("Invalid WAV: "+message)}
        func u16(_ p:Int)->Int{Int(b[p])|Int(b[p+1])<<8}
        func u32(_ p:Int)->UInt32{UInt32(b[p])|UInt32(b[p+1])<<8|UInt32(b[p+2])<<16|UInt32(b[p+3])<<24}
        func tag(_ p:Int)->String{String(bytes:b[p..<p+4],encoding:.ascii) ?? ""}
        guard b.count>=12,tag(0)=="RIFF",tag(8)=="WAVE",Int(u32(4))+8<=b.count else{throw fail("RIFF header")}
        let end=Int(u32(4))+8;var p=12,format=0,count=0,fs=0,bits=0,align=0,byteRate=0,payload:Range<Int>?
        while p+8<=end {let length=Int(u32(p+4)),start=p+8;guard length<=end-start else{throw fail("truncated chunk")}
            if tag(p)=="fmt " {guard length>=16,format==0 else{throw fail("format chunk")};format=u16(start);count=u16(start+2);fs=Int(u32(start+4));byteRate=Int(u32(start+8));align=u16(start+12);bits=u16(start+14)
                if format==0xfffe {guard length>=40,u16(start+16)>=22 else{throw fail("extensible format")};let guid=Array(b[start+24..<start+40]);guard Array(guid[2...]) == [0,0,0,0,16,0,128,0,0,170,0,56,155,113] else{throw fail("unsupported extensible GUID")};format=Int(guid[0])|Int(guid[1])<<8}
            } else if tag(p)=="data" {guard payload==nil else{throw fail("multiple data chunks")};payload=start..<start+length}
            p=start+length+(length%2)
        }
        guard let payload=payload,(1...32).contains(count),(8000...384000).contains(fs),[8,16,24,32,64].contains(bits),align==count*(bits/8),byteRate==fs*align,payload.count>0,payload.count%align==0 else{throw fail("empty data or inconsistent channels/rate/block alignment")}
        guard (format==1 && [8,16,24,32].contains(bits)) || (format==3 && [32,64].contains(bits)) else{throw fail("only PCM or IEEE float supported")}
        let frames=payload.count/align;guard frames<=50_000_000,frames*count<=64_000_000 else{throw fail("sample allocation limit")}
        var channels=Array(repeating:Array(repeating:0.0,count:frames),count:count)
        for frame in 0..<frames {for ch in 0..<count {let pos=payload.lowerBound+frame*align+ch*(bits/8);let value:Double
            if format==3 {if bits==32 {value=Double(Float(bitPattern:u32(pos)))} else {var raw:UInt64=0;for k in 0..<8{raw |= UInt64(b[pos+k]) << (8*k)};value=Double(bitPattern:raw)}} else {
                switch bits {case 8:value=(Double(b[pos])-128)/128
                case 16:value=Double(Int16(bitPattern:UInt16(u16(pos))))/32768
                case 24:var raw=Int32(b[pos])|Int32(b[pos+1])<<8|Int32(b[pos+2])<<16;if raw & 0x800000 != 0{raw |= ~0xffffff};value=Double(raw)/8388608
                default:value=Double(Int32(bitPattern:u32(pos)))/2147483648}
            }
            guard value.isFinite else{throw fail("nonfinite samples")};channels[ch][frame]=value
        }}
        return WAVData(sampleRate:fs,channels:channels)
    }
    public static func write(_ url:URL,sampleRate:Int,channels:[[Double]])throws {
        guard (8000...384000).contains(sampleRate),(1...32).contains(channels.count),let frames=channels.first?.count,frames>0,channels.allSatisfy({$0.count==frames && $0.allSatisfy({$0.isFinite && abs($0)<=Double(Float.greatestFiniteMagnitude)})}),frames*channels.count<=Int(UInt32.max-36)/4 else{throw FieldError.invalid("Cannot write invalid, empty, nonfinite, or oversized WAV")}
        var data=Data();func ascii(_ s:String){data.append(contentsOf:s.utf8)};func u16(_ n:Int){data.append(UInt8(n&255));data.append(UInt8((n>>8)&255))};func u32(_ n:UInt32){for shift in stride(from:0,to:32,by:8){data.append(UInt8((n>>shift)&255))}}
        let byteCount=frames*channels.count*4;ascii("RIFF");u32(UInt32(36+byteCount));ascii("WAVEfmt ");u32(16);u16(3);u16(channels.count);u32(UInt32(sampleRate));u32(UInt32(sampleRate*channels.count*4));u16(channels.count*4);u16(32);ascii("data");u32(UInt32(byteCount))
        for frame in 0..<frames {for ch in channels {u32(Float(ch[frame]).bitPattern)}};try data.write(to:url,options:.atomic)
    }
}

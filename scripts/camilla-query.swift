import Foundation

@main struct QueryCamilla {
    static func main() async throws {
        let port=CommandLine.arguments[1]
        let socket=URLSession.shared.webSocketTask(with:URL(string:"ws://127.0.0.1:\(port)")!)
        socket.resume()
        defer {socket.cancel(with:.normalClosure,reason:nil)}
        var records:[[String:Any]]=[]
        for _ in 0..<8 {
            for command in ["GetState","GetSignalLevels","GetSignalPeaksSinceStart","GetCaptureRate","GetClippedSamples","GetVolume","GetMute"] {
                let encoded=try JSONSerialization.data(withJSONObject:command,options:.fragmentsAllowed)
                try await socket.send(.string(String(decoding:encoded,as:UTF8.self)))
                let message=try await socket.receive()
                let data:Data
                switch message {case .data(let d):data=d;case .string(let s):data=Data(s.utf8);@unknown default:continue}
                if let value=try JSONSerialization.jsonObject(with:data) as? [String:Any] {records.append(value)}
            }
            try await Task.sleep(nanoseconds:500_000_000)
        }
        if CommandLine.arguments.contains("--balance") {
            for command in ["GetFaders","GetConfigJson"] {
                let data=try JSONSerialization.data(withJSONObject:command,options:.fragmentsAllowed)
                try await socket.send(.string(String(decoding:data,as:UTF8.self)))
                let reply=try await socket.receive()
                let bytes:Data
                switch reply {case .data(let value):bytes=value;case .string(let value):bytes=Data(value.utf8);@unknown default:continue}
                if let value=try JSONSerialization.jsonObject(with:bytes) as? [String:Any] {records.append(value)}
            }
        }
        let data=try JSONSerialization.data(withJSONObject:records,options:[.prettyPrinted,.sortedKeys])
        print(String(decoding:data,as:UTF8.self))
    }
}

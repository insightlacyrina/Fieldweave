import Foundation

actor CamillaSocket {
    let socket:URLSessionWebSocketTask
    private var tail:Task<Data,Error>?
    init(port:Int) {
        socket=URLSession.shared.webSocketTask(with:URL(string:"ws://127.0.0.1:\(port)")!)
        socket.resume()
    }
    func close(){socket.cancel(with:.goingAway,reason:nil);tail?.cancel()}
    func request(_ command:String,argument:Any?=nil)async throws->Data {
        let message=try JSONSerialization.data(withJSONObject:argument.map{[command:$0]} ?? command,options:.fragmentsAllowed)
        let prior=tail,socket=self.socket
        let next=Task<Data,Error> {
            _ = try? await prior?.value
            return try await withThrowingTaskGroup(of:Data.self) {group in
                group.addTask {
                    try await socket.send(.string(String(decoding:message,as:UTF8.self)))
                    switch try await socket.receive() {
                    case .data(let data):return data
                    case .string(let text):return Data(text.utf8)
                    @unknown default:throw LiveAudioError.message("Unrecognized CamillaDSP websocket response")
                    }
                }
                group.addTask {
                    try await Task.sleep(nanoseconds:2_000_000_000)
                    socket.cancel(with:.goingAway,reason:nil)
                    throw LiveAudioError.message("CamillaDSP did not respond within two seconds")
                }
                defer{group.cancelAll()}
                guard let data=try await group.next() else{throw LiveAudioError.message("CamillaDSP returned no response")}
                return data
            }
        }
        tail=next
        let data=try await next.value
        guard let root=try JSONSerialization.jsonObject(with:data) as? [String:Any],let response=root[command] as? [String:Any],response["result"] as? String=="Ok" else {throw LiveAudioError.message("CamillaDSP rejected \(command): \(String(decoding:data,as:UTF8.self))")}
        return data
    }
    func value(_ command:String)async throws->String {
        let data=try await request(command)
        guard let root=try JSONSerialization.jsonObject(with:data) as? [String:Any],let response=root[command] as? [String:Any] else{return ""}
        return response["value"] as? String ?? ""
    }
}

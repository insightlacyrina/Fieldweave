import SwiftUI
import FieldWeaveAudio

struct LiveAudioView: View {
    @ObservedObject var store:FieldStore
    @ObservedObject var audio:LiveAudioController
    private let donors = [35,29,32,49,60,86,13]
    private var locked:Bool { audio.isRunning || audio.isStarting }
    var body:some View {
        SectionCard(L("Live system audio")) {
            HStack(spacing:6) {
                Circle().fill(audio.isRunning ? Color.midBand:Color.gray).frame(width:6,height:6)
                Text(L(audio.status)).font(.system(size:10)).lineLimit(2)
            }
            if let route = store.audioRoute {
                Picker(L("Capture"),selection:Binding(get:{route.captureUID},set:{var next=route;next.captureUID=$0;store.setAudioRoute(next)})) {
                    ForEach(audio.devices.filter{$0.isVirtual && $0.inputChannels>=2 && $0.outputChannels>=2}) {Text($0.name).tag($0.uid)}
                }.disabled(locked)
                Picker(L("Headphone output"),selection:Binding(get:{route.playbackUID},set:{var next=route;next.playbackUID=$0;store.setAudioRoute(next)})) {
                    ForEach(audio.devices.filter{!$0.isVirtual && $0.outputChannels>=2}) {Text($0.name).tag($0.uid)}
                }.disabled(locked)
                Toggle(L("Start when FieldWeave opens"),isOn:Binding(get:{route.autoStart},set:{var next=route;next.autoStart=$0;store.setAudioRoute(next)}))
                    .font(.system(size:10)).tint(.midBand)
            } else {
                Text(L("Audio route unavailable")).font(.system(size:10)).foregroundStyle(.orange)
            }
            HStack {
                Button(L(locked ? "Stop & restore output":"Start processing")) {
                    if locked {store.stopLiveAudio()} else {store.startLiveAudio()}
                }.disabled(!locked && (!store.canProcess || store.audioRoute == nil))
                Button {audio.refreshDevices();if store.audioRoute == nil,
                    let capture=audio.devices.first(where:{$0.name=="BlackHole 2ch"}),
                    let playback=audio.devices.first(where:{$0.name=="NICEHCK NK1 Ultra"}) {
                    store.setAudioRoute(AudioRouteSettings(captureUID:capture.uid,playbackUID:playback.uid))
                }} label:{Image(systemName:"arrow.clockwise")}.disabled(locked).help(L("Refresh devices"))
            }
            if audio.isRunning {
                meter(L("Input"),audio.levels.capturePeak)
                meter(L("Output"),audio.levels.playbackPeak)
                HStack {Text(L("Clipped samples"));Spacer();Text("\(audio.levels.clippedSamples)").foregroundStyle(audio.levels.clippedSamples == 0 ? Color.secondary:Color.orange)}.font(.system(size:9))
                if audio.activeConfiguration != store.configuration || store.isCompiling {
                    Text(L("Playing the last applied FIR · changes pending")).font(.system(size:9)).foregroundStyle(.orange)
                }
            }
            if let error=audio.errorMessage {Text(L(error)).font(.system(size:9)).foregroundStyle(.orange).textSelection(.enabled)}
        }
        SectionCard("Personal-HRTF") {
            Picker(L("Candidate"),selection:$store.selectedHRTF) {
                ForEach(0..<7,id:\.self) {index in Text(String(format:"c%02d · HUTUBS pp%02d",index+1,donors[index])).tag(String(format:"c%02d",index+1))}
            }
            Button(L("Apply HRTF candidate")) {store.loadHRTFCandidate(store.selectedHRTF)}.disabled(store.isImporting || audio.isStarting)
        }
    }
    private func meter(_ title:String,_ values:[Double])->some View {
        let peak=values.filter(\.isFinite).max() ?? -120
        return HStack(spacing:6) {
            Text(title).frame(width:38,alignment:.leading)
            ProgressView(value:max(0,min(1,(peak+70)/70))).tint(.midBand)
            Text(peak > -100 ? String(format:"%.1f dB",peak):"−∞ dB").monospacedDigit().frame(width:61,alignment:.trailing)
        }.font(.system(size:9))
    }
}

import SwiftUI
import AppKit

extension Color {
    static let fieldBackground=Color(red:0.025,green:0.04,blue:0.06)
    static let fieldPanel=Color(red:0.045,green:0.064,blue:0.084)
    static let fieldLine=Color.white.opacity(0.10)
    static let lowBand=Color(red:1,green:0.47,blue:0.23)
    static let midBand=Color(red:0.53,green:0.86,blue:0.65)
    static let highBand=Color(red:0.35,green:0.70,blue:1)
    static let centerBand=Color(red:0.72,green:0.58,blue:0.98)
}
struct SectionCard<Content:View>:View {
    @AppStorage(AppLanguage.key) private var interfaceLanguage = "en"
    let title:String
    let content:Content
    init(_ title:String,@ViewBuilder content:()->Content){self.title=title;self.content=content()}
    var body:some View { VStack(alignment:.leading,spacing:13){Text(L(title).uppercased()).font(.system(size:10,weight:.medium,design:.monospaced)).tracking(1.6).foregroundStyle(.white.opacity(0.75));content}.padding(15).frame(maxWidth:.infinity,alignment:.leading).background(Color.fieldPanel.opacity(0.7),in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).stroke(Color.fieldLine)) }
}
struct ValueSlider:View {
    @AppStorage(AppLanguage.key) private var interfaceLanguage = "en"
    let title:String
    @Binding var value:Double
    let range:ClosedRange<Double>
    var suffix=""
    var color=Color.highBand
    var body:some View {VStack(spacing:7){HStack{Text(L(title)).foregroundStyle(.secondary);Spacer();Text(formatted).monospacedDigit()}.font(.system(size:11));Slider(value:$value,in:range).tint(color).controlSize(.small).accessibilityLabel(L(title)).accessibilityValue(formatted)}}
    private var formatted:String {
        if suffix == "°" {return abs(value)<0.05 ? "0°":String(format:"%+.1f°",value)}
        return String(format:suffix == "%" ? "%.0f %@":"%.1f %@",suffix == "%" ? value*100:value,suffix)
    }
}
struct FieldKnob:View {
    @AppStorage(AppLanguage.key) private var interfaceLanguage = "en"
    let title:String
    @Binding var value:Double
    let range:ClosedRange<Double>
    var color=Color.highBand
    var unit="%"
    @FWState private var startValue:Double?
    @FWState private var dragPhase:Double?
    @FWState private var previousAngle:Double?
    @FWState private var radialDrag:Bool=false
    private var fraction:Double{(value-range.lowerBound)/(range.upperBound-range.lowerBound)}
    var body:some View {
        VStack(spacing:9){
            ZStack {
                Circle().fill(LinearGradient(colors:[Color.white.opacity(0.08),Color.black.opacity(0.4)],startPoint:.topLeading,endPoint:.bottomTrailing)).shadow(color:.black.opacity(0.6),radius:10,y:5)
                Circle().stroke(Color.white.opacity(0.08),lineWidth:2).padding(3)
                Circle().trim(from:0,to:0.75).stroke(color.opacity(0.2),style:StrokeStyle(lineWidth:2.5,lineCap:.round)).rotationEffect(.degrees(135)).padding(2)
                Circle().trim(from:0,to:0.75*max(0,min(1,fraction))).stroke(color,style:StrokeStyle(lineWidth:2.5,lineCap:.round)).rotationEffect(.degrees(135)).padding(2)
                Rectangle().fill(color).frame(width:2,height:15).offset(y:-22).rotationEffect(.degrees(-135+fraction*270))
                Circle().fill(Color.white.opacity(0.035)).padding(13)
            }.frame(width:68,height:68)
                .contentShape(Circle())
                .gesture(DragGesture(minimumDistance:0).onChanged(handleDrag).onEnded{_ in startValue=nil;dragPhase=nil;previousAngle=nil;radialDrag=false})
                .onTapGesture(count:2){value=range.contains(1) && unit == "%" ? 1:0}
                .focusable().onMoveCommand{direction in let step=(range.upperBound-range.lowerBound)/100; if direction == .up || direction == .right {value=min(range.upperBound,value+step)}else{value=max(range.lowerBound,value-step)}}
                .accessibilityElement().accessibilityLabel(L(title)).accessibilityValue(formatted).accessibilityAdjustableAction {direction in let step=(range.upperBound-range.lowerBound)/100;value=max(range.lowerBound,min(range.upperBound,value+(direction == .increment ? step : -step)))}
            Text(L(title).uppercased()).font(.system(size:9,weight:.medium,design:.monospaced)).tracking(1).foregroundStyle(.secondary)
            Text(formatted).font(.system(size:13,weight:.medium,design:.monospaced)).foregroundStyle(color)
        }.frame(maxWidth:.infinity)
    }
    private func handleDrag(_ g:DragGesture.Value) {
        let fine=NSEvent.modifierFlags.contains(.shift) ? 0.1:1.0
        let x=g.location.x-34,y=g.location.y-34
        let angle=atan2(y,x)*180/Double.pi
        if startValue == nil {
            startValue=value
            radialDrag=hypot(g.startLocation.x-34,g.startLocation.y-34)>23
            if radialDrag {
                var phase=(angle-135).truncatingRemainder(dividingBy:360)
                if phase<0 {phase+=360}
                if phase>315 {phase-=360}
                dragPhase=fine<1 ? fraction*270:phase
                previousAngle=angle
            }
        } else if radialDrag {
            if hypot(x,y)<8 {previousAngle=nil;return}
            if let previous=previousAngle {
                var delta=angle-previous
                if delta>180 {delta-=360};if delta < -180 {delta+=360}
                dragPhase=(dragPhase ?? fraction*270)+delta*fine
            }
            previousAngle=angle
        }
        if radialDrag {
            value=range.lowerBound+max(0,min(270,dragPhase ?? fraction*270))/270*(range.upperBound-range.lowerBound)
        } else {
            value=max(range.lowerBound,min(range.upperBound,(startValue ?? value)-Double(g.translation.height)/240*(range.upperBound-range.lowerBound)*fine))
        }
    }
    private var formatted:String {
        switch unit {
        case "%": return String(format:"%.0f%%",value*100)
        case "pan": return abs(value)<0.005 ? L("Center"):String(format:"%@ %.0f%%",value<0 ? "L":"R",abs(value)*100)
        case "°": return abs(value)<0.05 ? "0°":String(format:"%+.1f°",value)
        default: return String(format:"%+.1f dB",value)
        }
    }
}

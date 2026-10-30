import SwiftUI
import AppKit
import FieldWeaveCore

struct ContentView:View {
    @AppStorage(AppLanguage.key) private var interfaceLanguage = "en"
    @ObservedObject var store:FieldStore
    @FWState private var tab:Int=0
    @FWState private var settings:Bool=false
    @FWState private var display:Bool=false
    @FWState private var showHelp:Bool=false
    @FWState private var visual:FieldVisualOptions=FieldVisualOptions()
    private var options:FieldVisualOptions {var o=visual;o.lowWidth=store.width(80);o.midWidth=store.width(1000);o.highWidth=store.width(10000);o.centerPan=(store.configuration.centerImaging?.enabled ?? false) ? store.configuration.centerImaging?.pan ?? 0:0;o.centerElevationDegrees=(store.configuration.centerImaging?.enabled ?? false) ? store.configuration.centerImaging?.elevationDegrees ?? 0:0;o.centerGainDb=(store.configuration.centerImaging?.enabled ?? false) ? store.configuration.centerImaging?.gainDb ?? 0:0;return o}
    func widthBinding(_ band:Int)->Binding<Double>{Binding(get:{store.width(band == 0 ? 80:band == 1 ? 1000:10000)},set:{store.setWidth($0,band:band)})}
    var pan:Binding<Double>{Binding(get:{store.configuration.centerImaging?.pan ?? 0},set:{store.setCenter(pan:$0)})}
    var centerHeight:Binding<Double>{Binding(get:{store.configuration.centerImaging?.elevationDegrees ?? 0},set:{store.setCenter(elevation:$0)})}
    var centerLevel:Binding<Double>{Binding(get:{store.configuration.centerImaging?.gainDb ?? 0},set:{store.setCenter(gain:$0)})}
    var centerEnabled:Binding<Bool>{Binding(get:{store.configuration.centerImaging?.enabled ?? false},set:{store.setCenter(enabled:$0)})}
    var body:some View {
        VStack(spacing:0){
            header
            Divider().overlay(Color.fieldLine)
            HStack(alignment:.top,spacing:0){
                ScrollView{left.padding(14)}.frame(width:240)
                Rectangle().fill(Color.fieldLine).frame(width:1)
                VStack(spacing:0){
                    ZStack(alignment:.topLeading){
                        if tab == 0 { SpatialFieldView(options:options) }else{FrequencyView(store:store).padding(24)}
                    }.frame(maxWidth:.infinity,maxHeight:.infinity)
                    Divider().overlay(Color.fieldLine)
                    HStack(spacing:4){FieldKnob(title:"Low width",value:widthBinding(0),range:0...2,color:.lowBand);FieldKnob(title:"Mid width",value:widthBinding(1),range:0...2,color:.midBand);FieldKnob(title:"High width",value:widthBinding(2),range:0...2,color:.highBand);FieldKnob(title:"Center height",value:centerHeight,range:-45...45,color:.centerBand,unit:"°").disabled(!centerEnabled.wrappedValue);FieldKnob(title:"Mid level",value:centerLevel,range:-12...6,color:.centerBand,unit:"dB").disabled(!centerEnabled.wrappedValue)}.padding(.vertical,22).padding(.horizontal,16).background(Color.fieldPanel.opacity(0.35))
                }
                Rectangle().fill(Color.fieldLine).frame(width:1)
                ScrollView{right.padding(14)}.frame(width:278)
            }
            Divider().overlay(Color.fieldLine)
            HStack(spacing:10){Circle().fill(store.isCompiling ? Color.yellow:store.isValid ? Color.midBand:Color.orange).frame(width:5,height:5);Text(L(store.status)).lineLimit(1);Spacer();if store.isCompiling || store.isWorking || store.isImporting{ProgressView().controlSize(.mini)};Text(String(format:AppLanguage.isChinese ? "%.1f kHz · 浮点 FIR" : "%.1f kHz · FLOAT FIR",Double(store.configuration.sampleRate)/1000)).font(.system(size:9,design:.monospaced)).foregroundStyle(.secondary)}.font(.system(size:10)).padding(.horizontal,18).frame(height:30)
        }.background(Color.fieldBackground).foregroundStyle(Color.white.opacity(0.88)).preferredColorScheme(.dark)
        .sheet(isPresented:$settings){settingsSheet}
        .task {store.prepareLiveAudio()}
        .sheet(isPresented:$showHelp){HelpView()}
        .sheet(item:$store.irReview){IRImportReviewView(store:store,review:$0)}
        .sheet(item:$store.configurationReview){ConfigurationReviewView(store:store,review:$0)}
        .confirmationDialog(L("Use the same channel for multiple paths?"),isPresented:Binding(get:{store.duplicateApplyScope != nil},set:{if !$0{store.duplicateApplyScope=nil}}),titleVisibility:.visible){
            if let scope=store.duplicateApplyScope {Button(L("Apply")){store.confirmDuplicateApply(scope)}}
            Button(L("Cancel"),role:.cancel){store.duplicateApplyScope=nil}
        }
        .alert("FieldWeave",isPresented:Binding(get:{store.errorMessage != nil},set:{if !$0{store.errorMessage=nil}})){Button(L("OK")){store.errorMessage=nil}}message:{Text(L(store.errorMessage ?? ""))}
    }
    var header:some View{HStack{
        VStack(alignment:.leading,spacing:4){Text(L("FIELDWEAVE")).font(.system(size:19,weight:.medium,design:.monospaced)).tracking(5)}.frame(width:220,alignment:.leading)
        Picker(L("View"),selection:$tab){Text(L("SOUND FIELD")).tag(0);Text(L("FREQUENCY")).tag(1)}.pickerStyle(.segmented).frame(width:300).labelsHidden()
        Spacer()
        Button{display.toggle()}label:{Label(L("DISPLAY"),systemImage:"slider.horizontal.3")}.popover(isPresented:$display){displaySettings.padding(20).frame(width:280)}
        Button{showHelp=true}label:{Image(systemName:"questionmark.circle")}.help(L("Application guide")).accessibilityLabel(L("Application guide"))
        Button{settings=true}label:{Image(systemName:"gearshape")}.help(L("DSP settings"))
    }.buttonStyle(.borderless).font(.system(size:10,weight:.medium,design:.monospaced)).padding(.horizontal,24).frame(height:77)}
    var left:some View {VStack(spacing:14){
        SectionCard(L("Preset")){
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],alignment:.leading,spacing:5){ForEach(["Neutral","Studio","Immersive","Vintage Stereo"],id:\.self){name in Button{store.selectPreset(name)}label:{HStack(spacing:5){Circle().fill(store.preset == name ? Color.white:Color.gray.opacity(0.3)).frame(width:5,height:5);Text(L(name)).font(.system(size:10)).lineLimit(1);Spacer(minLength:0)}.padding(.vertical,8).padding(.horizontal,5).background(store.preset == name ? Color.white.opacity(0.1):Color.clear,in:RoundedRectangle(cornerRadius:4))}.buttonStyle(.plain)}}
            Text(L(store.preset)).font(.system(size:9)).foregroundStyle(.secondary)
        }
        SectionCard(L("Frequency width")){
            ValueSlider(title:"High · 6–20 kHz",value:widthBinding(2),range:0...2,suffix:"%",color:.highBand)
            ValueSlider(title:"Mid · 250 Hz–6 kHz",value:widthBinding(1),range:0...2,suffix:"%",color:.midBand)
            ValueSlider(title:"Low · 20–250 Hz",value:widthBinding(0),range:0...2,suffix:"%",color:.lowBand)
        }
        SectionCard(L("Mid / center")){
            Toggle(L("Center shaping"),isOn:centerEnabled).font(.system(size:11)).tint(.centerBand)
            ValueSlider(title:"Center pan",value:pan,range:-1...1,color:.centerBand).disabled(!centerEnabled.wrappedValue)
            ValueSlider(title:"Center height",value:centerHeight,range:-45...45,suffix:"°",color:.centerBand).disabled(!centerEnabled.wrappedValue)
            ValueSlider(title:"Mid level",value:centerLevel,range:-12...6,suffix:"dB",color:.centerBand).disabled(!centerEnabled.wrappedValue)
            Button(L("Return to center")){store.setCenter(pan:0)}.font(.system(size:10)).buttonStyle(.link)
        }
        SectionCard(L("Headphone EQ")){
            Picker(L("Mode"),selection:$store.headphoneDraft.mode){Text(L("Bypass")).tag("bypass");Text(L("PEQ")).tag("peq");Text(L("Stereo FIR")).tag("fir")}.font(.system(size:10))
            if store.headphoneDraft.mode == "peq" {Button(L("Import PEQ JSON…")){store.importPEQ()};Text("\(store.headphoneDraft.peq?.count ?? 0) \(AppLanguage.isChinese ? "个参数均衡频段" : "parametric bands")").font(.system(size:10)).foregroundStyle(.secondary)}
            if store.headphoneDraft.mode == "fir" {Menu(L("Import FIR files…")){Button(L("Files…")){store.importIR(headphone:true)};Button(L("Folder…")){store.importIR(headphone:true,folder:true)}};irRow("left",label:"Left ear",headphone:true);irRow("right",label:"Right ear",headphone:true)}
            Button(L("Apply headphone EQ")){store.applyHeadphone()}.frame(maxWidth:.infinity)
        }
    }.controlSize(.small)}
    var right:some View {VStack(spacing:14){
        LiveAudioView(store:store,audio:store.liveAudio)
        SectionCard(L("HRTF / room")){
            Toggle(L("Apply imported matrix"),isOn:Binding(get:{store.configuration.externalization.mode != "bypass"},set:{if $0{store.applyExternalization()}else{store.bypassExternalization()}})).font(.system(size:11)).tint(.highBand)
            Text("\(L(store.configuration.externalization.mode == "bypass" ? "Bypassed":"Matrix active")) · \(store.externalizationDraft.paths?.count ?? 0)/4 \(AppLanguage.isChinese ? "条待应用路径" : "staged paths")").font(.system(size:9)).foregroundStyle(.secondary)
            DisclosureGroup(L("Matrix import & mapping")) {
            Menu(L("Import WAV files or folder…")){Button(L("Files…")){store.importIR()};Button(L("Folder…")){store.importIR(folder:true)}}
            irRow("LL",label:"Left → Left");irRow("LR",label:"Left → Right");irRow("RL",label:"Right → Left");irRow("RR",label:"Right → Right")
            Picker(L("IR kind"),selection:Binding(get:{store.externalizationDraft.kind ?? ""},set:{store.externalizationDraft.kind=$0.isEmpty ? nil:$0})){Text(L("Choose…")).tag("");Text(L("Measured HRTF")).tag("measured_hrtf");Text(L("Measured BRIR")).tag("measured_brir");Text(L("Test only")).tag("test_only")}.font(.system(size:10))
            TextField(L("Provenance / measurement source"),text:Binding(get:{store.externalizationDraft.provenance ?? ""},set:{store.externalizationDraft.provenance=$0})).textFieldStyle(.roundedBorder).font(.system(size:10))
            Picker(L("Normalization"),selection:Binding(get:{store.externalizationDraft.normalization ?? "none"},set:{store.externalizationDraft.normalization=$0})){Text(L("Preserve level")).tag("none");Text(L("Global peak")).tag("global_peak")}.font(.system(size:10))
            coordinateEditor
            Toggle(L("Confirm source coordinates"),isOn:$store.matrixCoordinatesConfirmed).font(.system(size:10))
            Button(L("Apply & validate matrix")) {store.applyExternalization()}.frame(maxWidth:.infinity)
            }.font(.system(size:10))
        }
        SectionCard(L("Crossfeed")){
            Toggle(L("Enable crossfeed"),isOn:Binding(get:{store.configuration.crossfeed.enabled},set:{v in if v {store.configuration.crossfeed=CrossfeedSettings(amount:0.15,delayMs:0.25,allowWithExternalization:store.configuration.crossfeed.allowWithExternalization ?? false)}else{store.configuration.crossfeed=CrossfeedSettings()}})).font(.system(size:11)).tint(.midBand)
            ValueSlider(title:"Low-frequency amount",value:Binding(get:{store.configuration.crossfeed.curve.map{CurveDSP.evaluate($0,frequencies:[20]).first ?? 0.15} ?? 0.15},set:{store.updateCrossfeed(amount:$0)}),range:0...0.3,suffix:"%",color:.midBand).disabled(!store.configuration.crossfeed.enabled)
            ValueSlider(title:"Delay",value:Binding(get:{store.configuration.crossfeed.delayMs ?? 0.25},set:{store.updateCrossfeed(delay:$0)}),range:0...2,suffix:"ms",color:.midBand).disabled(!store.configuration.crossfeed.enabled)
            Toggle(L("Explicitly allow with IR matrix"),isOn:Binding(get:{store.configuration.crossfeed.allowWithExternalization ?? false},set:{if store.configuration.crossfeed.enabled{store.configuration.crossfeed.allowWithExternalization=$0}})).font(.system(size:9)).disabled(!store.configuration.crossfeed.enabled)
        }
        SectionCard(L("Output / headroom")){
            ValueSlider(title:"Preamp",value:$store.configuration.safety.preampDb,range:-24...0,suffix:"dB",color:.midBand)
            Toggle(L("Automatic headroom"),isOn:$store.configuration.safety.autoHeadroom).font(.system(size:11)).tint(.midBand)
            if let report=store.compiled?.report {
                if !store.isValid || store.isCompiling {Text(L("Last valid FIR")).font(.system(size:9,weight:.medium)).foregroundStyle(.secondary)}
                VStack(spacing:6){reportRow("Headroom gain",String(format:"%.2f dB",report.autoHeadroomGainDb));reportRow("Input peak bound",String(format:"%.3f",report.boundedInputPeakBound));reportRow("Common delay",String(format:"%.2f ms",report.designCommonDelayMs));reportRow("Width error",String(format:"%.4f",report.widthMaxMagnitudeError))}.opacity(store.isCompiling || !store.isValid ? 0.4:1)
                ForEach(report.warnings,id:\.self){Text(warningStatus($0)).font(.system(size:9)).foregroundStyle(.orange)}
            }
            Button(L("Export FIR package…")){store.exportFIR()}.frame(maxWidth:.infinity).disabled(!store.canProcess)
            Button(L("Render audio WAV…")){store.renderAudio()}.frame(maxWidth:.infinity).disabled(!store.canProcess)
        }
    }.controlSize(.small)}
    private func warningStatus(_ warning:String)->String {
        switch warning {
        case "No measured HRTF/BRIR supplied; no claim of real externalization.": return L("No measured HRTF/BRIR supplied")
        case "Test-only IR is not evidence of measured HRTF/BRIR externalization.": return L("Test-only IR active")
        case "Auto headroom is disabled and unit-bounded input may clip.": return L("Clipping possible · automatic headroom off")
        default: return L(warning)
        }
    }
    func reportRow(_ label:String,_ value:String)->some View{HStack{Text(L(label)).foregroundStyle(.secondary);Spacer();Text(value).monospacedDigit()}.font(.system(size:9))}
    func irRow(_ key:String,label:String,headphone:Bool=false)->some View {
        let asset=headphone ? store.headphoneDraft.fir?[key]:store.externalizationDraft.paths?[key]
        return VStack(alignment:.leading,spacing:4){HStack{Text(L(label)).font(.system(size:10));Spacer();Button {store.importIR(path:key,headphone:headphone)}label:{Image(systemName:"folder")}.buttonStyle(.borderless)}
            if let asset {Text(URL(fileURLWithPath:asset.path).lastPathComponent).font(.system(size:9)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(asset.path)
                Picker(L("WAV channel"),selection:Binding(get:{headphone ? store.headphoneDraft.fir?[key]?.channel ?? 0:store.externalizationDraft.paths?[key]?.channel ?? 0},set:{v in if headphone{store.headphoneDraft.fir?[key]?.channel=v}else{store.externalizationDraft.paths?[key]?.channel=v}})){ForEach(0..<(store.assetChannels[asset.path] ?? 0),id:\.self){Text("\(AppLanguage.isChinese ? "声道" : "Channel") \($0+1)").tag($0)}}.font(.system(size:9))
            }else{Text(L("No file")).font(.system(size:9)).foregroundStyle(.tertiary)}
        }.padding(7).background(Color.black.opacity(0.15),in:RoundedRectangle(cornerRadius:5))
    }
    var coordinateEditor:some View {VStack(alignment:.leading,spacing:7){Text(L("Source coordinates · az° / el° / metres")).font(.system(size:9)).foregroundStyle(.secondary)
        ForEach(0..<2,id:\.self){source in HStack{Text(source == 0 ? "L":"R").font(.system(size:10));ForEach(0..<3,id:\.self){axis in TextField(L(""),value:Binding(get:{let c=store.externalizationDraft.coordinates ?? SourceCoordinates();return (source == 0 ? c.leftSource:c.rightSource)[axis]},set:{v in var c=store.externalizationDraft.coordinates ?? SourceCoordinates();if source == 0 {c.leftSource[axis]=v}else{c.rightSource[axis]=v};store.externalizationDraft.coordinates=c;store.matrixCoordinatesConfirmed=false}),format:.number).textFieldStyle(.roundedBorder).font(.system(size:9)).frame(minWidth:34)}}}
    }}
    var displaySettings:some View {VStack(alignment:.leading,spacing:15){Text(L("DISPLAY")).font(.system(size:11,weight:.medium,design:.monospaced)).tracking(2);Toggle(L("Motion"),isOn:$visual.motion);Toggle(L("Contours"),isOn:$visual.contours);Toggle(L("Grid"),isOn:$visual.grid);ValueSlider(title:"Depth",value:$visual.depth,range:0.3...2);ValueSlider(title:"Glow",value:$visual.glow,range:0...2);Toggle(L("High layer"),isOn:$visual.highVisible);ValueSlider(title:"High intensity",value:$visual.highIntensity,range:0...2,color:.highBand);Toggle(L("Mid layer"),isOn:$visual.midVisible);ValueSlider(title:"Mid intensity",value:$visual.midIntensity,range:0...2,color:.midBand);Toggle(L("Low layer"),isOn:$visual.lowVisible);ValueSlider(title:"Low intensity",value:$visual.lowIntensity,range:0...2,color:.lowBand)}.controlSize(.small)}
    var settingsSheet:some View{VStack(alignment:.leading,spacing:20){Text(L("DSP settings")).font(.title2);Picker(L("Language"),selection:$interfaceLanguage){Text("English").tag("en");Text("简体中文").tag("zh-Hans")};Picker(L("Sample rate"),selection:$store.configuration.sampleRate){Text(L("44.1 kHz")).tag(44100);Text(L("48 kHz")).tag(48000);Text(L("96 kHz")).tag(96000)};Picker(L("Width FIR length"),selection:$store.configuration.design.widthTaps){Text(L("1,025 taps")).tag(1025);Text(L("2,049 taps")).tag(2049);Text(L("4,097 taps")).tag(4097)};HStack{Button(L("Open configuration…")){settings=false;DispatchQueue.main.asyncAfter(deadline:.now()+0.2){store.openConfiguration()}};Button(L("Save configuration…")){store.saveConfiguration()};Spacer();Button(L("Done")){settings=false}.keyboardShortcut(.defaultAction)}}.padding(28).frame(width:520)}
}

struct FrequencyView:View {
    @AppStorage(AppLanguage.key) private var interfaceLanguage = "en"
    @ObservedObject var store:FieldStore
    @FWState private var active:Int?
    @FWState private var focusedPoint:Int?
    var body:some View{VStack(alignment:.leading,spacing:15){Text(L("STEREO WIDTH RESPONSE")).font(.system(size:12,weight:.medium,design:.monospaced)).tracking(2)
        GeometryReader{proxy in
            let size=proxy.size
            Canvas{context,s in
                for f in ([20,100,250,1000,6000,20000] as [Double]){let x=xPosition(f,s.width);var p=Path();p.move(to:CGPoint(x:x,y:0));p.addLine(to:CGPoint(x:x,y:s.height));context.stroke(p,with:.color(.white.opacity(0.07)),lineWidth:1);context.draw(Text(f>=1000 ? String(format:"%.0fk",f/1000):String(format:"%.0f",f)).font(.system(size:9)).foregroundColor(.gray),at:CGPoint(x:x,y:s.height-8))}
                for value in ([0,0.5,1,1.5,2] as [Double]){let y=yPosition(value,s.height);var p=Path();p.move(to:CGPoint(x:0,y:y));p.addLine(to:CGPoint(x:s.width,y:y));context.stroke(p,with:.color(.white.opacity(value == 1 ? 0.18:0.06)),lineWidth:1);context.draw(Text(String(format:"%.0f%%",value*100)).font(.system(size:9)).foregroundColor(.gray),at:CGPoint(x:22,y:y-7))}
                let frequencies=(0..<250).map{20*pow(1000,Double($0)/249)}
                let target=CurveDSP.evaluate(store.configuration.width,frequencies:frequencies)
                drawCurve(context:&context,frequencies:frequencies,values:target,size:s,color:.highBand,dashed:true)
                if !store.isCompiling,store.isValid,let c=store.compiled{drawCurve(context:&context,frequencies:c.responseFrequencies,values:c.widthActual,size:s,color:.midBand,dashed:false)}
                for p in store.configuration.width.points where p.count>=2 {let center=CGPoint(x:xPosition(p[0],s.width),y:yPosition(p[1],s.height));context.fill(Path(ellipseIn:CGRect(x:center.x-5,y:center.y-5,width:10,height:10)),with:.color(.highBand));context.stroke(Path(ellipseIn:CGRect(x:center.x-8,y:center.y-8,width:16,height:16)),with:.color(.highBand.opacity(0.3)),lineWidth:1)}
            }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onChanged{g in
                if active == nil{active=store.configuration.width.points.indices.min(by:{abs(xPosition(store.configuration.width.points[$0][0],size.width)-g.startLocation.x)<abs(xPosition(store.configuration.width.points[$1][0],size.width)-g.startLocation.x)})}
                guard let i=active else{return};focusedPoint=i
                var points=store.configuration.width.points
                let minimum=i>0 ? max(20,points[i-1][0]*1.0001):20
                let maximum=i<points.count-1 ? min(20000,Double(store.configuration.sampleRate)/2,points[i+1][0]/1.0001):min(20000,Double(store.configuration.sampleRate)/2)
                let normalizedX=Double(max(0,min(1,g.location.x/max(size.width,1))))
                let frequency=20.0*Foundation.pow(1000.0,normalizedX)
                points[i][0]=max(minimum,min(maximum,frequency))
                points[i][1]=max(0,min(2,(size.height-25-g.location.y)/max(size.height-50,1)*2))
                store.configuration.width.points=points;store.preset="Custom"
            }.onEnded{_ in active=nil})
        }
        if let i=focusedPoint,store.configuration.width.points.indices.contains(i){Text(String(format:AppLanguage.isChinese ? "锚点 %d · %.1f Hz · %.1f%%" : "Anchor %d · %.1f Hz · %.1f%%",i+1,store.configuration.width.points[i][0],store.configuration.width.points[i][1]*100)).font(.system(size:11,design:.monospaced)).foregroundStyle(Color.highBand)}
        HStack(spacing:20){Label(L("Target curve"),systemImage:"line.diagonal").foregroundStyle(Color.highBand);Label(L(store.isCompiling ? "Actual FIR pending…":store.isValid ? "Actual compiled FIR":"Actual unavailable"),systemImage:"waveform").foregroundStyle(Color.midBand)}.font(.system(size:10))
    }.padding(.vertical,20)}
    func xPosition(_ f:Double,_ width:Double)->Double{log(max(20,f)/20)/log(1000)*width}
    func yPosition(_ v:Double,_ height:Double)->Double{height-25-v/2*(height-50)}
    func drawCurve(context:inout GraphicsContext,frequencies:[Double],values:[Double],size:CGSize,color:Color,dashed:Bool){var p=Path();for (i,pair) in zip(frequencies,values).enumerated(){let point=CGPoint(x:xPosition(pair.0,size.width),y:yPosition(pair.1,size.height));if i==0{p.move(to:point)}else{p.addLine(to:point)}};context.stroke(p,with:.color(color),style:StrokeStyle(lineWidth:dashed ? 1:2,dash:dashed ? [4,4]:[]))}
}

import Foundation

typealias Matrix = [[[Double]]]
func identityMatrix()->Matrix{[[[1],[0]],[[0],[1]]]}
func diagonalMatrix(_ left:[Double],_ right:[Double])->Matrix {let n=max(left.count,right.count),zero=Array(repeating:0.0,count:n);return [[left+Array(repeating:0,count:n-left.count),zero],[zero,right+Array(repeating:0,count:n-right.count)]]}
func multiplyMatrix(_ a:Matrix,_ b:Matrix)->Matrix {
    let count=a[0][0].count+b[0][0].count-1;var out=Array(repeating:Array(repeating:Array(repeating:0.0,count:count),count:2),count:2)
    for i in 0..<2 {for j in 0..<2 {for k in 0..<2 {let conv=NativeFFT.convolve(a[i][k],b[k][j]);for t in 0..<count {out[i][j][t]+=conv[t]}}}};return out
}
func validateCompiled(_ compiled:CompiledField)throws {
    let n=compiled.report.matrixTaps
    guard (8000...192000).contains(compiled.report.sampleRate),(1...262143).contains(n),compiled.matrix.count==2,compiled.matrix.allSatisfy({$0.count==2 && $0.allSatisfy({$0.count==n && $0.allSatisfy(\.isFinite)})}) else{throw FieldError.invalid("Invalid compiled stereo FIR matrix")}
}
public enum FIRCompiler {
    static func validate(_ c:FieldConfiguration)throws {
        func number(_ v:Double,_ lo:Double,_ hi:Double,_ name:String)throws{guard v.isFinite,v>=lo,v<=hi else{throw FieldError.invalid("\(name) must be finite in \(lo)...\(hi)")}}
        guard c.version==1,(8000...192000).contains(c.sampleRate) else{throw FieldError.invalid("Unsupported configuration version or sample rate")}
        for taps in [c.design.widthTaps,c.design.eqTaps,c.design.maxMatrixTaps] {guard (1...262143).contains(taps) else{throw FieldError.invalid("FIR length must be 1...262143")}}
        guard c.design.widthTaps%2==1,c.design.resamplePolicy=="reject" else{throw FieldError.invalid("Width taps must be odd; native import currently requires resample_policy=reject")}
        try number(c.design.tailEnergyTolerance,0,0.01,"Tail energy tolerance")
        func curve(_ s:CurveSpec,_ maxValue:Double)throws {guard s.interpolation=="pchip_log_hz",s.points.count>=2,s.points.count<=4096 else{throw FieldError.invalid("Curve needs 2...4096 log-Hz PCHIP points")};var previous=0.0;for p in s.points {guard p.count==2 else{throw FieldError.invalid("Curve point must be [Hz,value]")};try number(p[0],1,Double(c.sampleRate)/2,"Curve frequency");try number(p[1],0,maxValue,"Curve value");guard p[0]>previous else{throw FieldError.invalid("Curve frequencies must strictly increase")};previous=p[0]}}
        try curve(c.width,2)
        let h=c.headphone
        switch h.mode {case "bypass":guard h.peq==nil,h.fir==nil else{throw FieldError.invalid("Bypassed headphone correction contains active parameters")}
        case "peq":guard let bands=h.peq,h.fir==nil,bands.count<=64 else{throw FieldError.invalid("PEQ needs at most 64 bands and no FIR")};for b in bands {try number(b.frequencyHz,1,Double(c.sampleRate)/2-1,"PEQ frequency");try number(b.q,0.1,20,"PEQ Q");try number(b.gainDb,-24,24,"PEQ gain")}
        case "fir":guard h.peq==nil,let paths=h.fir,Set(paths.keys)==Set(["left","right"]) else{throw FieldError.invalid("Headphone FIR requires left and right WAV assets")}
        default:throw FieldError.invalid("Unsupported headphone mode")}
        if let center=c.centerImaging {if center.enabled {guard let pan=center.pan,let gain=center.gainDb else{throw FieldError.invalid("Enabled center imaging requires pan and gain")};try number(pan,-1,1,"Center pan");try number(gain,-12,6,"Center gain");if let elevation=center.elevationDegrees {try number(elevation,-45,45,"Center elevation")};if let profile=center.heightProfile,!CenterElevation.supportedProfiles.contains(profile) {throw FieldError.invalid("Unsupported measured center-height profile")}} else if center.pan != nil || center.gainDb != nil || center.elevationDegrees != nil || center.heightProfile != nil {throw FieldError.invalid("Disabled center imaging has active parameters")}}
        let e=c.externalization
        switch e.mode {case "bypass":guard e.paths==nil,e.kind==nil,e.normalization==nil,e.coordinates==nil,e.provenance==nil else{throw FieldError.invalid("Bypassed externalization has active parameters")}
        case "matrix_ir":guard let paths=e.paths,Set(paths.keys)==Set(["LL","LR","RL","RR"]),["measured_hrtf","measured_brir","test_only"].contains(e.kind ?? ""),["none","global_peak"].contains(e.normalization ?? ""),let provenance=e.provenance,!provenance.isEmpty,let coordinates=e.coordinates,coordinates.convention==SourceCoordinates().convention else{throw FieldError.invalid("Matrix IR requires four paths, explicit kind, normalization, provenance and source coordinates")};for p in [coordinates.leftSource,coordinates.rightSource] {guard p.count==3 else{throw FieldError.invalid("Source coordinates require azimuth/elevation/distance")};try number(p[0],-180,180,"Azimuth");try number(p[1],-90,90,"Elevation");try number(p[2],0.001,100,"Distance")}
        default:throw FieldError.invalid("Unsupported externalization; native import accepts four WAV IR paths, not SOFA")}
        let x=c.crossfeed
        if x.enabled {guard let spec=x.curve,let delay=x.delayMs else{throw FieldError.invalid("Crossfeed requires curve and delay")};try curve(spec,0.3);try number(delay,0,2,"Crossfeed delay");if e.mode != "bypass" && x.allowWithExternalization != true {throw FieldError.invalid("Matrix IR plus crossfeed requires explicit opt-in")}} else if x.curve != nil || x.delayMs != nil || x.allowWithExternalization != nil {throw FieldError.invalid("Disabled crossfeed has active parameters")}
        try number(c.safety.preampDb,-60,0,"Preamp");try number(c.safety.ceilingDbfs,-24,0,"Ceiling")
    }
    public static func compile(_ configuration:FieldConfiguration,baseURL:URL)throws->CompiledField {
        let c=configuration;try validate(c);let fs=c.sampleRate,d=c.design;var warnings:[String]=[]
        func imported(_ asset:IRAsset)throws->[Double] {
            guard !asset.path.isEmpty,asset.channel>=0 else{throw FieldError.invalid("Asset path/channel invalid")}
            let url=URL(fileURLWithPath:asset.path,relativeTo:baseURL);guard url.pathExtension.lowercased()=="wav" else{throw FieldError.invalid("Native IR import currently supports WAV only")}
            let wav=try WAVFile.read(url);guard wav.sampleRate==fs else{throw FieldError.invalid("IR sample-rate mismatch: \(wav.sampleRate) Hz versus \(fs) Hz; explicitly convert the WAV before import")};guard asset.channel<wav.channels.count else{throw FieldError.invalid("IR channel out of range")};guard wav.channels[asset.channel].count<=262143 else{throw FieldError.invalid("IR exceeds 262143-tap import limit")};return wav.channels[asset.channel]
        }
        var q=identityMatrix()
        if c.headphone.mode=="fir" {q=try diagonalMatrix(imported(c.headphone.fir!["left"]!),imported(c.headphone.fir!["right"]!))}
        if c.headphone.mode=="peq" {
            let count=max(d.eqTaps*4,d.eqTaps+8192);var impulse=Array(repeating:0.0,count:count);impulse[0]=1
            for band in c.headphone.peq! {let a=pow(10,band.gainDb/40),omega=2*Double.pi*band.frequencyHz/Double(fs),alpha=sin(omega)/(2*band.q),a0=1+alpha/a,b0=(1+alpha*a)/a0,b1 = -2*cos(omega)/a0,b2=(1-alpha*a)/a0,a1 = -2*cos(omega)/a0,a2=(1-alpha/a)/a0;var x1=0.0,x2=0.0,y1=0.0,y2=0.0
                for n in 0..<count {let x=impulse[n],y=b0*x+b1*x1+b2*x2-a1*y1-a2*y2;x2=x1;x1=x;y2=y1;y1=y;impulse[n]=y}
            }
            let total=impulse.reduce(0){$0+$1*$1},tail=impulse.dropFirst(d.eqTaps).reduce(0){$0+$1*$1}/max(total,1e-300)
            guard tail<=d.tailEnergyTolerance else{throw FieldError.invalid("PEQ truncation loses \(tail) energy; increase EQ taps")};q=diagonalMatrix(Array(impulse.prefix(d.eqTaps)),Array(impulse.prefix(d.eqTaps)))
        }
        let (width,delay)=try CurveDSP.design(c.width,fs:fs,taps:d.widthTaps);var direct=Array(repeating:0.0,count:width.count);direct[delay]=1
        let diagonal=zip(direct,width).map{($0+$1)/2},off=zip(direct,width).map{($0-$1)/2};let w:Matrix=[[diagonal,off],[off,diagonal]]
        var matrix=multiplyMatrix(w,q);var left=1.0,right=1.0
        let elevation=(c.centerImaging?.enabled == true ? c.centerImaging?.elevationDegrees:nil) ?? 0
        var elevationStrategy="bypass",elevationProfile:String?
        if let center=c.centerImaging,center.enabled {let pan=center.pan!,gain=pow(10,center.gainDb!/20)
            if pan==0 {left=gain;right=gain} else if pan == -1 {left=gain*sqrt(2);right=0} else if pan==1 {left=0;right=gain*sqrt(2)} else {let angle=Double.pi/4*(1+pan);left=gain*sqrt(2)*cos(angle);right=gain*sqrt(2)*sin(angle)}
            if elevation==0 && (left != 1 || right != 1) {matrix=multiplyMatrix([[[(left+1)/2],[(left-1)/2]],[[(right-1)/2],[(right+1)/2]]],matrix)}
        }
        var externalMatrix=identityMatrix(),rawExternalMatrix:Matrix?,externalScale=1.0
        if c.externalization.mode=="matrix_ir" {
            let paths=c.externalization.paths!;var irs:[String:[Double]]=[:];for k in ["LL","LR","RL","RR"]{irs[k]=try imported(paths[k]!)};let n=irs.values.map(\.count).max()!;var e=Array(repeating:Array(repeating:Array(repeating:0.0,count:n),count:2),count:2)
            for (key,row,col) in [("LL",0,0),("LR",1,0),("RL",0,1),("RR",1,1)] {e[row][col].replaceSubrange(0..<irs[key]!.count,with:irs[key]!)}
            rawExternalMatrix=e
            if c.externalization.normalization=="global_peak" {let peak=e.flatMap{$0}.flatMap{$0}.map{abs($0)}.max()!;if peak>0 {externalScale=1/peak;for i in 0..<2 {for j in 0..<2 {e[i][j]=e[i][j].map{$0/peak}}}}};externalMatrix=e
            if elevation==0 {matrix=multiplyMatrix(e,matrix)}
            if c.externalization.kind=="test_only" {warnings.append("Test-only IR is not evidence of measured HRTF/BRIR externalization.")}
        } else {warnings.append("No measured HRTF/BRIR supplied; no claim of real externalization.")}
        if elevation != 0 {
            let result=try CenterElevation.apply(base:matrix,externalization:externalMatrix,rawExternalization:rawExternalMatrix,externalizationScale:externalScale,left:left,right:right,degrees:elevation,profile:c.centerImaging?.heightProfile,sampleRate:fs)
            matrix=result.matrix;elevationStrategy=result.strategy;elevationProfile=result.profile
            if let warning=result.warning {warnings.append(warning)}
        }
        var crossDelay=0
        if c.crossfeed.enabled {let (g,cd)=try CurveDSP.design(c.crossfeed.curve!,fs:fs,taps:d.widthTaps);crossDelay=cd;let extra=Int((c.crossfeed.delayMs!*Double(fs)/1000).rounded(.toNearestOrEven)),n=g.count+extra;var x=Array(repeating:Array(repeating:Array(repeating:0.0,count:n),count:2),count:2);x[0][0][cd]=1;x[1][1][cd]=1;x[0][1].replaceSubrange(extra..<extra+g.count,with:g)
            x[1][0].replaceSubrange(extra..<extra+g.count,with:g);matrix=multiplyMatrix(x,matrix)
        }
        if matrix[0][0].count>d.maxMatrixTaps {let energy=matrix.flatMap{$0}.flatMap{$0}.reduce(0){$0+$1*$1};let loss=matrix.flatMap{$0}.reduce(0){$0+$1.dropFirst(d.maxMatrixTaps).reduce(0){$0+$1*$1}}/max(energy,1e-300);guard loss<=d.tailEnergyTolerance else{throw FieldError.invalid("Matrix truncation loses \(loss) energy; increase maximum matrix taps")};for i in 0..<2{for j in 0..<2{matrix[i][j]=Array(matrix[i][j].prefix(d.maxMatrixTaps))}}}
        let preamp=pow(10,c.safety.preampDb/20);for i in 0..<2{for j in 0..<2{matrix[i][j]=matrix[i][j].map{$0*preamp}}}
        let bound=matrix.map{$0.flatMap{$0}.reduce(0){$0+abs($1)}}.max()!,ceiling=pow(10,c.safety.ceilingDbfs/20),gain=c.safety.autoHeadroom ? min(1,ceiling/max(bound,1e-300)):1
        for i in 0..<2{for j in 0..<2{matrix[i][j]=matrix[i][j].map{$0*gain};guard matrix[i][j].allSatisfy(\.isFinite) else{throw FieldError.invalid("DSP compilation produced nonfinite samples")}}}
        if bound*gain>1+1e-12 {warnings.append("Auto headroom is disabled and unit-bounded input may clip.")}
        let fftn=max(16384,NativeFFT.size(max(matrix[0][0].count,width.count)*2)),freq=(0...fftn/2).map{Double($0)*Double(fs)/Double(fftn)},actual=NativeFFT.magnitude(width,n:fftn),target=CurveDSP.evaluate(c.width,frequencies:freq),error=zip(actual,target).map{abs($0-$1)}.max()!
        let report=CompilationReport(sampleRate:fs,matrixTaps:matrix[0][0].count,designCommonDelayMs:Double(delay+crossDelay)*1000/Double(fs),autoHeadroomGainDb:20*log10(gain),boundedInputPeakBound:bound*gain,widthMaxMagnitudeError:error,warnings:warnings,midLeftGain:left,midRightGain:right,centerElevationDegrees:elevation,centerElevationStrategy:elevationStrategy,centerElevationProfile:elevationProfile)
        return CompiledField(matrix:matrix,report:report,responseFrequencies:freq,widthTarget:target,widthActual:actual)
    }
}
public enum FIRProcessor {
    public static func render(input:URL,output:URL,compiled:CompiledField)throws->RenderReport {
        try validateCompiled(compiled)
        guard input.standardizedFileURL != output.standardizedFileURL else{throw FieldError.invalid("Output must be a different file from input")};let audio=try WAVFile.read(input)
        guard audio.channels.count==2,audio.sampleRate==compiled.report.sampleRate else{throw FieldError.invalid("Offline render requires stereo WAV at the compiled sample rate")}
        let n=audio.channels[0].count+compiled.report.matrixTaps-1;guard n<=50_000_000 else{throw FieldError.invalid("Rendered file exceeds frame limit")};var out=Array(repeating:Array(repeating:0.0,count:n),count:2)
        for i in 0..<2 {for j in 0..<2 {let result=NativeFFT.blockConvolve(audio.channels[j],compiled.matrix[i][j]);for k in 0..<n {out[i][k]+=result[k]}}}
        let peak=out.reduce(0.0){peak,channel in channel.reduce(peak){max($0,abs($1))}};guard peak.isFinite,peak<=1 else{throw FieldError.invalid("Render rejected: output peak \(peak) exceeds full scale; lower preamp or enable automatic headroom")};try WAVFile.write(output,sampleRate:audio.sampleRate,channels:out);return RenderReport(sampleRate:audio.sampleRate,frames:n,peak:peak)
    }
}

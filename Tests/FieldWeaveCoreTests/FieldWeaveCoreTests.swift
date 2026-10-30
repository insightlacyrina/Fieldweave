import Foundation
import Testing
@testable import FieldWeaveCore

@Suite struct FieldWeaveCoreTests {
    var base:URL {URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent("FieldWeaveTests-"+UUID().uuidString,isDirectory:true)}
    func neutral()->FieldConfiguration {var c=FieldConfiguration();c.width=CurveSpec(points:[[20,1],[20000,1]]);c.safety.preampDb=0;c.safety.autoHeadroom=false;return c}
    func compile(_ c:FieldConfiguration)throws->CompiledField {try FIRCompiler.compile(c,baseURL:URL(fileURLWithPath:"/tmp",isDirectory:true))}
    @Test func testExactNeutralAndMonoSidePreservation()throws {
        let c=try compile(neutral());XCTAssertEqual(c.matrix,[[[1],[0]],[[0],[1]]]);XCTAssertEqual(c.report.designCommonDelayMs,0)
        var mono=neutral();mono.width=CurveSpec(points:[[20,0],[20000,0]]);let m=try compile(mono);XCTAssertEqual(m.matrix,[[[0.5],[0.5]],[[0.5],[0.5]]])
        var wide=neutral();wide.width=CurveSpec(points:[[20,2],[20000,2]]);let w=try compile(wide);XCTAssertEqual(w.matrix,[[[1.5],[-0.5]],[[-0.5],[1.5]]])
    }
    @Test func testCenterAllMidEqualPowerAndSide()throws {
        var c=neutral();c.centerImaging=CenterSettings(pan:0.6,gainDb:-2);let r=try compile(c),l=r.report.midLeftGain,g=r.report.midRightGain
        XCTAssertEqual(l*l+g*g,2*pow(10,-2.0/10),accuracy:1e-12)
        XCTAssertEqual(r.matrix[0][0][0]+r.matrix[0][1][0],l,accuracy:1e-12);XCTAssertEqual(r.matrix[1][0][0]+r.matrix[1][1][0],g,accuracy:1e-12)
        XCTAssertEqual(r.matrix[0][0][0]-r.matrix[0][1][0],1,accuracy:1e-12);XCTAssertEqual(r.matrix[1][0][0]-r.matrix[1][1][0],-1,accuracy:1e-12)
        c.centerImaging=CenterSettings(pan:1);let edge=try compile(c);XCTAssertEqual(edge.report.midLeftGain,0);XCTAssertEqual(edge.report.midRightGain,sqrt(2))
    }
    @Test func testPCHIPAnchorsAndShape() {
        let spec=CurveSpec(points:[[20,0],[100,0.4],[1000,0.1],[20000,1]])
        let values=CurveDSP.evaluate(spec,frequencies:[0,20,100,1000,20000,100000]);for (a,b) in zip(values,[0,0,0.4,0.1,1,1]) {XCTAssertEqual(a,b,accuracy:1e-12)}
        let f=(0..<500).map{20*pow(1000,Double($0)/499)},y=CurveDSP.evaluate(spec,frequencies:f);XCTAssertTrue(y.allSatisfy{$0>=0 && $0<=1})
    }
    @Test func testWidthLinearPhaseAndMidDelayAlignment()throws {
        var c=neutral();c.design.widthTaps=129;c.width=CurveSpec(points:[[20,0.5],[1000,1.5],[20000,0.8]]);let r=try compile(c)
        XCTAssertEqual(r.report.matrixTaps,129);XCTAssertEqual(r.report.designCommonDelayMs,64.0/48,accuracy:1e-12)
        for n in 0..<129 {XCTAssertEqual(r.matrix[0][0][n]+r.matrix[0][1][n],n==64 ? 1:0,accuracy:1e-12);XCTAssertEqual(r.matrix[0][0][n],r.matrix[0][0][128-n],accuracy:1e-12)}
    }
    @Test func testFFTMatchesDirectConvolution() {
        let a=(0..<31).map{sin(Double($0)*0.3)},b=(0..<27).map{cos(Double($0)*0.4)};var expected=Array(repeating:0.0,count:57)
        for i in a.indices {for j in b.indices {expected[i+j]+=a[i]*b[j]}}
        for (actual,expected) in zip(NativeFFT.convolve(a,b),expected) {XCTAssertEqual(actual,expected,accuracy:1e-11)}
    }
    @Test func testOverlapAddPreservesFullTail() {
        let input=(0..<131073).map{sin(Double($0)*0.07)},kernel=[0.2,-0.3,0.1,0.4,-0.2]
        let result=NativeFFT.blockConvolve(input,kernel)
        XCTAssertEqual(result.count,input.count+kernel.count-1)
        for i in result.indices {var expected=0.0;for k in kernel.indices {if i>=k && i-k<input.count{expected+=input[i-k]*kernel[k]}};XCTAssertEqual(result[i],expected,accuracy:1e-10)}
    }
    @Test func testCrossfeedDelayAndCommonDelay()throws {
        var c=neutral();c.crossfeed=CrossfeedSettings(amount:0.1,delayMs:1);c.crossfeed.curve=CurveSpec(points:[[20,0.1],[20000,0.1]]);let r=try compile(c)
        XCTAssertEqual(r.report.matrixTaps,49);XCTAssertEqual(r.matrix[0][0][0],1);XCTAssertEqual(r.matrix[0][1][48],0.1);XCTAssertEqual(r.matrix[1][0][48],0.1);XCTAssertEqual(r.matrix[1][1][0],1)
        c.design.widthTaps=65;c.crossfeed.curve=CurveSpec(points:[[20,0.1],[20000,0]]);let linear=try compile(c);XCTAssertEqual(linear.report.designCommonDelayMs,32.0/48,accuracy:1e-12);XCTAssertEqual(linear.matrix[0][0][32],1,accuracy:1e-12)
    }
    @Test func testWAVRoundtripAndRejectNonfiniteAndTruncated()throws {
        let folder=base;try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:folder)};let url=folder.appendingPathComponent("stereo.wav")
        let channels=[[0.0,-0.5,0.25,1.0],[0.25,0,-1,0.5]];try WAVFile.write(url,sampleRate:48000,channels:channels);let read=try WAVFile.read(url);XCTAssertEqual(read.channels,channels);XCTAssertEqual(read.sampleRate,48000)
        XCTAssertThrowsError(try WAVFile.write(url,sampleRate:48000,channels:[[.nan]]));var bytes=try Data(contentsOf:url);bytes.removeLast();try bytes.write(to:url);XCTAssertThrowsError(try WAVFile.read(url))
    }
    func matrixConfiguration(folder:URL)throws->FieldConfiguration {
        var c=neutral();c.externalization.mode="matrix_ir";c.externalization.kind="test_only";c.externalization.normalization="none";c.externalization.coordinates=SourceCoordinates();c.externalization.provenance="unit test impulses";var paths:[String:IRAsset]=[:]
        for (key,values) in [("LL",[0.1,0,0]),("LR",[0,0.2,0]),("RL",[0,0,0.3]),("RR",[0.4,0,0])] {try WAVFile.write(folder.appendingPathComponent(key+".wav"),sampleRate:48000,channels:[values]);paths[key]=IRAsset(path:key+".wav")};c.externalization.paths=paths;return c
    }
    @Test func testPCMBitDepthsAndNonfiniteImport()throws {
        let folder=base;try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:folder)}
        for (bits,payload) in [(8,[UInt8(0),128,255]),(16,[0,128,0,0,255,127]),(24,[0,0,128,0,0,0,255,255,127]),(32,[0,0,0,128,0,0,0,0,255,255,255,127])] {
            var bytes=Data();func ascii(_ text:String){bytes.append(contentsOf:text.utf8)};func word(_ value:Int,_ count:Int){for k in 0..<count{bytes.append(UInt8((value>>(8*k))&255))}}
            ascii("RIFF");word(36+payload.count+(payload.count%2),4);ascii("WAVEfmt ");word(16,4);word(1,2);word(1,2);word(48000,4);word(48000*bits/8,4);word(bits/8,2);word(bits,2);ascii("data");word(payload.count,4);bytes.append(contentsOf:payload);if payload.count%2==1{bytes.append(0)}
            let url=folder.appendingPathComponent("pcm-\(bits).wav");try bytes.write(to:url);let decoded=try WAVFile.read(url);XCTAssertEqual(decoded.channels[0][0],-1);XCTAssertEqual(decoded.channels[0][1],0);XCTAssertEqual(decoded.channels[0][2],1-1/pow(2,Double(bits-1)),accuracy:1e-12)
        }
        let url=folder.appendingPathComponent("nan.wav");try WAVFile.write(url,sampleRate:48000,channels:[[0]]);var bytes=try Data(contentsOf:url);bytes.replaceSubrange(44..<48,with:[0,0,192,127]);try bytes.write(to:url);XCTAssertThrowsError(try WAVFile.read(url))
    }
    @Test func testFailedExportLeavesNoPartialTarget()throws {
        let folder=base;try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:folder)}
        let c=try matrixConfiguration(folder:folder),compiled=try FIRCompiler.compile(c,baseURL:folder);try FileManager.default.removeItem(at:folder.appendingPathComponent("LL.wav"))
        let target=folder.appendingPathComponent("export");XCTAssertThrowsError(try FieldExporter.export(compiled,configuration:c,to:target,baseURL:folder));XCTAssertFalse(FileManager.default.fileExists(atPath:target.path));XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath:folder.path).contains(where:{$0.hasPrefix(".fieldweave-export-")}))
    }
    @Test func testMatrixMappingPortableExportAndTailRender()throws {
        let folder=base;try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:folder)};let c=try matrixConfiguration(folder:folder),r=try FIRCompiler.compile(c,baseURL:folder)
        XCTAssertEqual(r.matrix[0][0][0],0.1,accuracy:1e-7);XCTAssertEqual(r.matrix[1][0][1],0.2,accuracy:1e-7);XCTAssertEqual(r.matrix[0][1][2],0.3,accuracy:1e-7);XCTAssertEqual(r.matrix[1][1][0],0.4,accuracy:1e-7)
        let package=folder.appendingPathComponent("package",isDirectory:true);try FieldExporter.export(r,configuration:c,to:package,baseURL:folder);XCTAssertThrowsError(try FieldExporter.export(r,configuration:c,to:package,baseURL:folder));let portable=try FieldConfiguration.read(from:package.appendingPathComponent("configuration.json")),rebuilt=try FIRCompiler.compile(portable,baseURL:package);XCTAssertEqual(rebuilt.matrix,r.matrix)
        let input=folder.appendingPathComponent("input.wav"),output=folder.appendingPathComponent("output.wav");try WAVFile.write(input,sampleRate:48000,channels:[[1,0],[0,0]]);let render=try FIRProcessor.render(input:input,output:output,compiled:r);XCTAssertEqual(render.frames,4);let audio=try WAVFile.read(output);XCTAssertEqual(audio.channels[0][0],0.1,accuracy:1e-7);XCTAssertEqual(audio.channels[1][1],0.2,accuracy:1e-7)
        let yaml=try String(contentsOf:package.appendingPathComponent("camilladsp-coreaudio.yml"),encoding:.utf8);XCTAssertFalse(yaml.contains(folder.path));XCTAssertTrue(yaml.contains("REPLACE_WITH_CAPTURE_DEVICE"))
    }
    @Test func testSafetyValidationTailAuditAndRateMismatch()throws {
        var c=neutral();c.width=CurveSpec(points:[[20,2],[20000,2]]);c.safety.autoHeadroom=true;let r=try compile(c);XCTAssertLessThanOrEqual(r.report.boundedInputPeakBound,pow(10,-1.0/20)+1e-12)
        c.design.resamplePolicy="polyphase";XCTAssertThrowsError(try compile(c));c=neutral();c.width.points=[[100,1],[20,1]];XCTAssertThrowsError(try compile(c));c=neutral();c.headphone.mode="peq";c.headphone.peq=[PEQBand(frequencyHz:20,q:20,gainDb:24)];c.design.eqTaps=1;XCTAssertThrowsError(try compile(c))
        let folder=base;try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:folder)};var matrix=try matrixConfiguration(folder:folder);matrix.design.maxMatrixTaps=1;XCTAssertThrowsError(try FIRCompiler.compile(matrix,baseURL:folder));matrix.design.maxMatrixTaps=65536;try WAVFile.write(folder.appendingPathComponent("LL.wav"),sampleRate:44100,channels:[[1]]);XCTAssertThrowsError(try FIRCompiler.compile(matrix,baseURL:folder))
    }
    @Test func testRenderRejectsClipAndSampleRateMismatch()throws {
        let folder=base;try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:folder)};let input=folder.appendingPathComponent("input.wav"),output=folder.appendingPathComponent("out.wav");var c=neutral();c.width=CurveSpec(points:[[20,2],[20000,2]]);let r=try compile(c)
        try WAVFile.write(input,sampleRate:48000,channels:[[1],[-1]]);XCTAssertThrowsError(try FIRProcessor.render(input:input,output:output,compiled:r));XCTAssertFalse(FileManager.default.fileExists(atPath:output.path))
        try WAVFile.write(input,sampleRate:44100,channels:[[0.1],[0.1]]);XCTAssertThrowsError(try FIRProcessor.render(input:input,output:output,compiled:r))
    }
}

private func XCTAssertEqual<T:Equatable>(_ a:T,_ b:T,sourceLocation:SourceLocation=#_sourceLocation) {#expect(a==b,sourceLocation:sourceLocation)}
private func XCTAssertEqual(_ a:Double,_ b:Double,accuracy:Double,sourceLocation:SourceLocation=#_sourceLocation) {#expect(abs(a-b)<=accuracy,sourceLocation:sourceLocation)}
private func XCTAssertTrue(_ value:Bool,sourceLocation:SourceLocation=#_sourceLocation) {#expect(value,sourceLocation:sourceLocation)}
private func XCTAssertFalse(_ value:Bool,sourceLocation:SourceLocation=#_sourceLocation) {#expect(!value,sourceLocation:sourceLocation)}
private func XCTAssertLessThanOrEqual(_ a:Double,_ b:Double,sourceLocation:SourceLocation=#_sourceLocation) {#expect(a<=b,sourceLocation:sourceLocation)}
private func XCTAssertThrowsError<T>(_ expression:@autoclosure ()throws->T,sourceLocation:SourceLocation=#_sourceLocation) {do {_ = try expression();Issue.record("Expected error",sourceLocation:sourceLocation)}catch{}}

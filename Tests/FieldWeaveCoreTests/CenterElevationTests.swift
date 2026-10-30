import Foundation
import Testing
@testable import FieldWeaveCore

@Suite struct FieldWeaveCenterElevationTests {
    func neutral() -> FieldConfiguration {
        var c=FieldConfiguration()
        c.width=CurveSpec(points:[[20,1],[20000,1]])
        c.safety.preampDb=0;c.safety.autoHeadroom=false
        return c
    }
    func compile(_ c:FieldConfiguration) throws -> CompiledField {
        try FIRCompiler.compile(c,baseURL:URL(fileURLWithPath:"/"))
    }
    func directory() throws -> URL {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("FieldWeaveElevation-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
        return url
    }
    func configuration(matrix:Matrix,folder:URL) throws -> FieldConfiguration {
        var c=neutral()
        var paths:[String:IRAsset]=[:]
        for (key,row,col) in [("LL",0,0),("LR",1,0),("RL",0,1),("RR",1,1)] {
            let url=folder.appendingPathComponent(key+".wav")
            try WAVFile.write(url,sampleRate:48000,channels:[matrix[row][col]])
            paths[key]=IRAsset(path:url.path)
        }
        c.externalization.mode="matrix_ir";c.externalization.paths=paths
        c.externalization.kind="measured_hrtf";c.externalization.normalization="none"
        c.externalization.coordinates=SourceCoordinates();c.externalization.provenance="A label cannot identify the actual measured donor"
        return c
    }
    func sample(_ matrix:Matrix,_ row:Int,_ col:Int,_ tap:Int) -> Double {
        tap<matrix[row][col].count ? matrix[row][col][tap]:0
    }

    @Test func zeroHeightAndOldJSONKeepTheExactOriginalPipeline() throws {
        let folder=try directory();defer{try? FileManager.default.removeItem(at:folder)}
        var old=try configuration(matrix:CenterElevation.referenceMatrix(profile:"c01",sampleRate:48000),folder:folder)
        old.width=CurveSpec(points:[[20,0.7],[1000,1.2],[20000,1.7]])
        old.centerImaging=CenterSettings(pan:0.3,gainDb:-2)
        let json=try old.jsonData()
        #expect(!String(decoding:json,as:UTF8.self).contains("elevation_degrees"))
        let decoded=try FieldConfiguration.decode(json),baseline=try compile(decoded)
        var explicit=decoded;explicit.centerImaging?.elevationDegrees=0;explicit.centerImaging?.heightProfile="c07"
        let zero=try compile(explicit)
        #expect(zero.matrix==baseline.matrix)
        #expect(zero.report.designCommonDelayMs==baseline.report.designCommonDelayMs)
        #expect(zero.report.centerElevationStrategy=="bypass")
        #expect(zero.report.centerElevationProfile==nil)
        explicit.centerImaging=CenterSettings(enabled:false)
        var absent=explicit;absent.centerImaging=nil
        let disabled=try compile(explicit),missing=try compile(absent)
        #expect(disabled.matrix==missing.matrix)
    }

    @Test func allBanksRetainOriginalZeroAndInterpolateMeasuredElevationNodes() throws {
        let project=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for id in CenterElevation.supportedProfiles {
            let zero=try CenterElevation.referenceMatrix(profile:id,sampleRate:48000)
            let folder=project.appendingPathComponent("Examples/PersonalHRTF/"+id)
            for (name,row,col) in [("LS_LE",0,0),("LS_RE",1,0),("RS_LE",0,1),("RS_RE",1,1)] {
                let original=try WAVFile.read(folder.appendingPathComponent(name+".wav"))
                #expect(zero[row][col]==original.channels[0])
            }
            let lower=try CenterElevation.matrix(profile:id,degrees:-50,sampleRate:48000)
            let upper=try CenterElevation.matrix(profile:id,degrees:-40,sampleRate:48000)
            let middle=try CenterElevation.matrix(profile:id,degrees:-45,sampleRate:48000)
            for ear in 0..<2 {for source in 0..<2 {for tap in middle[ear][source].indices {
                #expect(abs(middle[ear][source][tap]-(lower[ear][source][tap]+upper[ear][source][tap])/2)<1e-12)
            }}}
        }
    }

    @Test func matchingDonorReplacesOnlyMidAndUsesTheHRTFOnce() throws {
        let folder=try directory();defer{try? FileManager.default.removeItem(at:folder)}
        let original=try CenterElevation.referenceMatrix(profile:"c01",sampleRate:48000)
        let raised=try CenterElevation.matrix(profile:"c01",degrees:30,sampleRate:48000)
        var c=try configuration(matrix:original,folder:folder)
        for pan in [-1.0,0,0.6,1] {
            c.centerImaging=CenterSettings(pan:pan,gainDb:-3,elevationDegrees:30,heightProfile:"c01")
            let field=try compile(c)
            #expect(field.report.centerElevationStrategy=="measured_mid_replacement")
            #expect(field.report.matrixTaps==original[0][0].count)
            for ear in 0..<2 {for tap in field.matrix[ear][0].indices {
                let mid=field.matrix[ear][0][tap]+field.matrix[ear][1][tap]
                let side=field.matrix[ear][0][tap]-field.matrix[ear][1][tap]
                let expectedMid=field.report.midLeftGain*raised[ear][0][tap]+field.report.midRightGain*raised[ear][1][tap]
                #expect(abs(mid-expectedMid)<1e-11)
                #expect(abs(side-(original[ear][0][tap]-original[ear][1][tap]))<1e-11)
            }}
        }
        c.centerImaging=CenterSettings(elevationDegrees:30)
        #expect(try compile(c).report.centerElevationProfile=="c01")
        c.externalization.normalization="global_peak"
        let normalized=try compile(c),scale=1/(original.flatMap{$0}.flatMap{$0}.map{abs($0)}.max()!)
        for ear in 0..<2 {for tap in normalized.matrix[ear][0].indices {
            #expect(abs(normalized.matrix[ear][0][tap]+normalized.matrix[ear][1][tap]-(raised[ear][0][tap]+raised[ear][1][tap])*scale)<1e-11)
        }}
    }

    @Test func bypassAndUnknownRenderersKeepSideAndUseRelativeCues() throws {
        var c=neutral()
        for degrees in [-45.0,45] {
            c.centerImaging=CenterSettings(elevationDegrees:degrees,heightProfile:"c01")
            let field=try compile(c)
            #expect(field.report.centerElevationStrategy=="relative_minimum_phase_cues")
            #expect(field.report.centerElevationProfile=="c01")
            #expect(field.report.designCommonDelayMs==0)
            #expect(field.matrix[0][0].contains{abs($0)>1e-6})
            for ear in 0..<2 {for tap in field.matrix[ear][0].indices {
                let side=field.matrix[ear][0][tap]-field.matrix[ear][1][tap]
                #expect(abs(side-(tap==0 ? (ear==0 ? 1.0:-1.0):0))<1e-10)
            }}
        }
        c.centerImaging=CenterSettings(elevationDegrees:0.0001,heightProfile:"c01")
        let tiny=try compile(c)
        for ear in 0..<2 {for source in 0..<2 {for tap in tiny.matrix[ear][source].indices {
            let baseline=(tap==0 && ear==source) ? 1.0:0
            #expect(abs(tiny.matrix[ear][source][tap]-baseline)<0.001)
        }}}
        let folder=try directory();defer{try? FileManager.default.removeItem(at:folder)}
        let unknown:Matrix=[[[0.4,0.1],[0.2,0]],[[0.1,0],[0.3,-0.1]]]
        let decodedUnknown=unknown.map{$0.map{$0.map{Double(Float($0))}}}
        c=try configuration(matrix:unknown,folder:folder)
        c.centerImaging=CenterSettings(elevationDegrees:20,heightProfile:"c01")
        let field=try compile(c)
        #expect(field.report.centerElevationStrategy=="relative_minimum_phase_cues")
        for ear in 0..<2 {for tap in field.matrix[ear][0].indices {
            #expect(abs(field.matrix[ear][0][tap]-field.matrix[ear][1][tap]-(sample(decodedUnknown,ear,0,tap)-sample(decodedUnknown,ear,1,tap)))<1e-10)
        }}
    }

    @Test func actualMatrixDonorWinsOverAStaleProfileSelection() throws {
        let folder=try directory();defer{try? FileManager.default.removeItem(at:folder)}
        var c=try configuration(matrix:CenterElevation.referenceMatrix(profile:"c01",sampleRate:48000),folder:folder)
        c.centerImaging=CenterSettings(elevationDegrees:20,heightProfile:"c02")
        let field=try compile(c)
        #expect(field.report.centerElevationStrategy=="measured_mid_replacement")
        #expect(field.report.centerElevationProfile=="c01")
        var modified=try CenterElevation.referenceMatrix(profile:"c01",sampleRate:48000)
        modified[0][0][10]+=0.01
        c=try configuration(matrix:modified,folder:folder)
        c.centerImaging=CenterSettings(elevationDegrees:20,heightProfile:"c02")
        let unknown=try compile(c)
        #expect(unknown.report.centerElevationStrategy=="relative_minimum_phase_cues")
        #expect(unknown.report.centerElevationProfile=="c02")
        #expect(unknown.report.warnings.contains{$0.contains("absolute elevation")})
    }

    @Test func relativeDesignIsCausalFiniteAndHasBoundedGain() throws {
        let boost=try CenterElevation.minimumPhaseRatio(target:[1],reference:[1e-5])
        let cut=try CenterElevation.minimumPhaseRatio(target:[1e-5],reference:[1])
        let equal=try CenterElevation.minimumPhaseRatio(target:[1,0.2,-0.1],reference:[1,0.2,-0.1])
        #expect(abs(boost[0]-pow(10,12.0/20))<1e-9)
        #expect(abs(cut[0]-pow(10,-18.0/20))<1e-9)
        #expect(abs(equal[0]-1)<1e-10)
        #expect(equal.dropFirst().allSatisfy{abs($0)<1e-10})
        #expect(boost.allSatisfy{$0.isFinite})
    }

    @Test func trustedBankRateConversionAndHeightSafetyWorkAtSupportedAppRates() throws {
        for rate in [44100,48000,96000] {
            var c=neutral();c.sampleRate=rate;c.safety.autoHeadroom=true;c.safety.preampDb = -3
            c.centerImaging=CenterSettings(elevationDegrees:45,heightProfile:"c07")
            let field=try compile(c)
            #expect(field.report.sampleRate==rate)
            #expect(field.report.boundedInputPeakBound<=pow(10,-1.0/20)+1e-9)
            #expect(field.matrix.flatMap{$0}.flatMap{$0}.allSatisfy{$0.isFinite})
            let reference=try CenterElevation.referenceMatrix(profile:"c07",sampleRate:rate)
            let native=try CenterElevation.referenceMatrix(profile:"c07",sampleRate:48000)
            for ear in 0..<2 {for source in 0..<2 {
                #expect(abs(reference[ear][source].reduce(0,+)-native[ear][source].reduce(0,+))<0.005)
            }}
        }
    }

    @Test func configurationRoundTripAndPortableExportRebuildTheSameHeight() throws {
        let folder=try directory();defer{try? FileManager.default.removeItem(at:folder)}
        var c=neutral();c.centerImaging=CenterSettings(pan:0.3,gainDb:-2,elevationDegrees:25,heightProfile:"c04")
        c.safety.autoHeadroom=true
        let decoded=try FieldConfiguration.decode(c.jsonData())
        #expect(decoded==c)
        let field=try compile(c),package=folder.appendingPathComponent("package")
        try FieldExporter.export(field,configuration:c,to:package,baseURL:folder)
        let attribution=try String(contentsOf:package.appendingPathComponent("CENTER-HEIGHT-ATTRIBUTION.txt"),encoding:.utf8)
        #expect(attribution.contains("CC BY 4.0"))
        let provenance=try JSONSerialization.jsonObject(with:Data(contentsOf:package.appendingPathComponent("center-height-provenance.json"))) as? [String:Any]
        #expect(provenance?["active_profile"] as? String=="c04")
        let reopened=try FieldConfiguration.read(from:package.appendingPathComponent("configuration.json"))
        let rebuilt=try FIRCompiler.compile(reopened,baseURL:package)
        #expect(rebuilt.matrix==field.matrix)
        #expect(rebuilt.report.centerElevationDegrees==25)
    }

    @Test func invalidHeightAndInactiveParametersAreRejected() throws {
        for degrees in [-46.0,46,Double.nan,Double.infinity] {
            var c=neutral();c.centerImaging=CenterSettings(elevationDegrees:degrees)
            #expect(throws:(any Error).self){try compile(c)}
        }
        var c=neutral();c.centerImaging=CenterSettings(elevationDegrees:20,heightProfile:"c99")
        #expect(throws:(any Error).self){try compile(c)}
        c.centerImaging=CenterSettings(enabled:false);c.centerImaging?.elevationDegrees=20
        #expect(throws:(any Error).self){try compile(c)}
        c.centerImaging=CenterSettings(enabled:false);c.centerImaging?.heightProfile="c01"
        #expect(throws:(any Error).self){try compile(c)}
    }
}

import Foundation
import Testing
import FieldWeaveCore
import FieldWeaveAudio
@testable import FieldWeave

@Suite @MainActor struct FieldWeaveCenterElevationFlowTests {
    func directory() throws -> URL {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("FieldWeaveElevationFlow-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
        return url
    }
    func settle(_ store:FieldStore) async throws {
        for _ in 0..<2000 {
            if !store.isImporting && !store.isCompiling {return}
            try await Task.sleep(nanoseconds:10_000_000)
        }
        Issue.record("Elevation compile/import did not settle")
    }
    func saveEvidence(_ store:FieldStore,name:String) throws {
        guard let folder=ProcessInfo.processInfo.environment["FIELDWEAVE_ELEVATION_EVIDENCE"] else {return}
        let root=URL(fileURLWithPath:folder).appendingPathComponent("Packages").appendingPathComponent(name)
        let field=try #require(store.compiled)
        try FieldExporter.export(field,configuration:store.configuration,to:root,baseURL:URL(fileURLWithPath:"/"))
        func device(_ name:String)->AudioDevice {AudioDevice(objectID:0,uid:name,name:name,inputChannels:2,outputChannels:2,sampleRate:Double(store.configuration.sampleRate),transportType:0)}
        let yaml=try LiveConfiguration.yaml(exportDirectory:root,capture:device("BlackHole 2ch"),playback:device("NICEHCK NK1 Ultra"))
        try yaml.write(to:root.appendingPathComponent("live.yml"),atomically:true,encoding:.utf8)
    }

    @Test func heightEditsPersistAndFollowTheSelectedDonor() async throws {
        let root=try directory();defer{try? FileManager.default.removeItem(at:root)}
        let store=FieldStore(supportDirectory:root);try await settle(store)
        store.setCenter(pan:0.4,gain:-2,elevation:25)
        try await settle(store)
        #expect(store.isValid)
        #expect(store.configuration.centerImaging?.elevationDegrees==25)
        #expect(store.configuration.centerImaging?.heightProfile=="c01")
        store.loadHRTFCandidate("c03");try await settle(store)
        #expect(store.isValid)
        #expect(store.configuration.centerImaging?.elevationDegrees==25)
        #expect(store.configuration.centerImaging?.heightProfile=="c03")
        #expect(store.configuration.centerImaging?.pan==0.4)
        #expect(store.configuration.centerImaging?.gainDb == -2)
        let original=try #require(store.compiled)
        let reopened=FieldStore(supportDirectory:root);try await settle(reopened)
        #expect(reopened.configuration==store.configuration)
        #expect(reopened.compiled?.matrix==original.matrix)
        let package=root.appendingPathComponent("portable",isDirectory:true)
        try FieldExporter.export(original,configuration:store.configuration,to:package,baseURL:URL(fileURLWithPath:"/"))
        let configuration=try FieldConfiguration.read(from:package.appendingPathComponent("configuration.json"))
        let rebuilt=try FIRCompiler.compile(configuration,baseURL:package)
        #expect(rebuilt.matrix==original.matrix)
        store.setCenter(enabled:false);try await settle(store)
        #expect(store.isValid)
        #expect(store.configuration.centerImaging?.elevationDegrees==nil)
        #expect(store.configuration.centerImaging?.heightProfile==nil)
        store.setCenter(enabled:true);try await settle(store)
        #expect(store.configuration.centerImaging?.elevationDegrees==0)
    }

    @Test func heightControlRoundoffReturnsToTheExactOriginalFIR() async throws {
        let root=try directory();defer{try? FileManager.default.removeItem(at:root)}
        let store=FieldStore(supportDirectory:root);try await settle(store)
        let baseline=try #require(store.compiled)
        store.setCenter(elevation:45);try await settle(store)
        #expect(store.compiled?.matrix != baseline.matrix)
        // Observed after stepping the native slider from +45 back to its center.
        store.setCenter(elevation:7.105427357601002e-15);try await settle(store)
        #expect(store.configuration.centerImaging?.elevationDegrees==0)
        #expect(store.compiled?.report.centerElevationStrategy=="bypass")
        #expect(store.compiled?.matrix==baseline.matrix)
        #expect(store.compiled?.report.matrixTaps==baseline.report.matrixTaps)
    }

    @Test func allPresetsAndMeasuredCandidatesSupportHeightWithLiveBalance() async throws {
        let root=try directory();defer{try? FileManager.default.removeItem(at:root)}
        let store=FieldStore(supportDirectory:root);try await settle(store)
        for name in ["Neutral","Studio","Immersive","Vintage Stereo"] {
            store.selectPreset(name);try await settle(store)
            let neutral=try #require(store.compiled)
            for height in [-30.0,30] {
                store.setCenter(elevation:height);try await settle(store)
                #expect(store.isValid)
                #expect(store.errorMessage==nil)
                let field=try #require(store.compiled)
                #expect(field.matrix != neutral.matrix)
                let cal=try LiveConfiguration.calibration(compiled:field,configuration:store.configuration)
                #expect(cal.targetGainDb == -9)
                #expect(cal.filterGainDb.isFinite)
                try saveEvidence(store,name:name+(height>0 ? "-up30":"-down30"))
            }
            store.setCenter(elevation:0);try await settle(store)
            #expect(store.compiled?.matrix==neutral.matrix)
        }
        for id in ["c01","c04","c07"] {
            store.loadHRTFCandidate(id);try await settle(store)
            #expect(store.isValid)
            for height in [-45.0,-20,20,45] {
                store.setCenter(elevation:height);try await settle(store)
                #expect(store.isValid)
                #expect(store.errorMessage==nil)
                let field=try #require(store.compiled)
                #expect(field.report.boundedInputPeakBound<=pow(10,-1.0/20)+1e-8)
                let cal=try LiveConfiguration.calibration(compiled:field,configuration:store.configuration)
                #expect(cal.filterGainDb.isFinite)
                try saveEvidence(store,name:id+(height>0 ? "-up":"-down")+String(Int(abs(height))))
            }
            store.setCenter(elevation:0);try await settle(store)
        }
    }
}

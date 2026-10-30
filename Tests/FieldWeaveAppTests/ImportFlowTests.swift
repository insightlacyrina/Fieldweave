import Foundation
import Testing
import FieldWeaveCore
import FieldWeaveAudio
@testable import FieldWeave

@Suite @MainActor struct FieldWeaveImportFlowTests {
    @Test func presetsAndManualEditsShareTheLiveBalancePath() async throws {
        let dir=try directory();defer{try? FileManager.default.removeItem(at:dir)}
        let store=FieldStore(supportDirectory:dir);try await settle(store)
        for name in ["Neutral","Studio","Immersive","Vintage Stereo"] {
            store.selectPreset(name);try await settle(store)
            let compiled=try #require(store.compiled)
            let cal=try LiveConfiguration.calibration(compiled:compiled,configuration:store.configuration)
            #expect(cal.targetGainDb == -9)
            #expect(cal.filterGainDb.isFinite)
            #expect(compiled.report.boundedInputPeakBound<=pow(10,-1.0/20)+1e-9)
            try saveBalanceEvidence(store,name:name)
        }
        store.setWidth(2,band:0);store.setWidth(0.2,band:2)
        store.setCenter(pan:0.8,gain:6);store.updateCrossfeed(amount:0.25,delay:1)
        store.configuration.safety.preampDb = -12
        try await settle(store)
        #expect(store.isValid)
        let cal=try LiveConfiguration.calibration(compiled:#require(store.compiled),configuration:store.configuration)
        #expect(cal.targetGainDb == -18)
        #expect(cal.filterGainDb.isFinite)
        try saveBalanceEvidence(store,name:"Manual-combined")
        store.configuration.safety.preampDb = -3
        store.bypassExternalization();store.configuration.crossfeed=CrossfeedSettings()
        store.setCenter(pan:-1,gain:-12);store.setWidth(0,band:0);store.setWidth(2,band:1)
        try await settle(store);try saveBalanceEvidence(store,name:"Manual-pan-width")
        store.configuration.headphone.mode="peq"
        store.configuration.headphone.peq=[PEQBand(frequencyHz:150,q:0.7,gainDb:8),PEQBand(frequencyHz:4000,q:1,gainDb:-6)]
        try await settle(store);try saveBalanceEvidence(store,name:"Manual-EQ")
    }

    func saveBalanceEvidence(_ store:FieldStore,name:String) throws {
        guard let folder=ProcessInfo.processInfo.environment["FIELDWEAVE_BALANCE_EVIDENCE"] else {return}
        let root=URL(fileURLWithPath:folder).appendingPathComponent("Packages").appendingPathComponent(name)
        let compiled=try #require(store.compiled)
        try FieldExporter.export(compiled,configuration:store.configuration,to:root,baseURL:URL(fileURLWithPath:"/"))
        func device(_ name:String)->AudioDevice {AudioDevice(objectID:0,uid:name,name:name,inputChannels:2,outputChannels:2,sampleRate:48000,transportType:0)}
        let yaml=try LiveConfiguration.yaml(exportDirectory:root,capture:device("BlackHole 2ch"),playback:device("NICEHCK NK1 Ultra"))
        try yaml.write(to:root.appendingPathComponent("live.yml"),atomically:true,encoding:.utf8)
    }
    @Test func bundledDonorCandidatesApplyWithoutInventedHeadphoneCorrection() async throws {
        let dir=try directory();defer{try? FileManager.default.removeItem(at:dir)}
        let store=FieldStore(supportDirectory:dir);try await settle(store)
        store.setWidth(1.15,band:1);try await settle(store)
        for index in 1...7 {
            let id=String(format:"c%02d",index)
            store.loadHRTFCandidate(id);try await settle(store)
            #expect(store.errorMessage == nil)
            #expect(store.isValid)
            #expect(store.configuration.sampleRate == 48000)
            #expect(store.configuration.externalization.paths?.count == 4)
            #expect(store.configuration.externalization.provenance?.contains("NOT a measurement of this listener") == true)
            #expect(store.configuration.headphone.mode == "bypass")
            #expect(!store.configuration.crossfeed.enabled)
            #expect(abs(store.width(1000)-1.15) < 0.000001)
            let report=try #require(store.compiled?.report)
            #expect(report.boundedInputPeakBound <= pow(10,-1.0/20)+0.000001)
            #expect(!store.liveAudio.isRunning)
            try saveBalanceEvidence(store,name:id)
        }
    }
    func directory() throws -> URL {
        let url=URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent("FieldWeaveImportFlow-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
        return url
    }
    func settle(_ store:FieldStore) async throws {
        for _ in 0..<1000 {
            if !store.isImporting && !store.isCompiling {return}
            try await Task.sleep(nanoseconds:10_000_000)
        }
        Issue.record("Import/compile did not settle")
    }
    @Test func lastImportWinsAndEditsCancelPendingReplacement() async throws {
        let dir=try directory();defer{try? FileManager.default.removeItem(at:dir)}
        let store=FieldStore(supportDirectory:dir);try await settle(store)
        var first=store.configuration;first.safety.preampDb = -6
        var second=store.configuration;second.safety.preampDb = -9
        store.validateAndReplace(first);store.validateAndReplace(second)
        try await settle(store)
        #expect(store.configuration == second)
        #expect(store.isValid)
        store.validateAndReplace(first)
        store.configuration.safety.preampDb = -12
        try await settle(store)
        #expect(store.configuration.safety.preampDb == -12)
        #expect(!store.isImporting)
    }
    @Test func failedImportRetainsConfigurationAndRollsBackAssets() async throws {
        let dir=try directory();defer{try? FileManager.default.removeItem(at:dir)}
        let store=FieldStore(supportDirectory:dir);try await settle(store)
        let original=store.configuration
        let file=dir.appendingPathComponent("input.wav")
        try WAVFile.write(file,sampleRate:48000,channels:[[1],[0.5]])
        var invalid=original;invalid.headphone.mode="fir"
        invalid.headphone.fir=["left":IRAsset(path:file.path),"right":IRAsset(path:file.path,channel:9)]
        store.validateAndReplace(invalid);try await settle(store)
        #expect(store.configuration == original)
        #expect(store.errorMessage != nil)
        #expect(store.isValid)
        let assets=dir.appendingPathComponent("Assets")
        let directories=(try? FileManager.default.contentsOfDirectory(atPath:assets.path)) ?? []
        #expect(directories.isEmpty)
    }
    @Test func peqAndIRRemainDraftUntilApplyAndAssetsSurviveSourceRemoval() async throws {
        let dir=try directory();defer{try? FileManager.default.removeItem(at:dir)}
        let store=FieldStore(supportDirectory:dir);try await settle(store)
        let original=store.configuration
        let peq=dir.appendingPathComponent("peq.json")
        try Data("[{\"frequency_hz\":1000,\"q\":1,\"gain_db\":0}]".utf8).write(to:peq)
        store.stagePEQ(peq);try await settle(store)
        #expect(store.configuration == original)
        #expect(store.headphoneDraft.mode == "peq")
        let wav=dir.appendingPathComponent("stereo.wav")
        try WAVFile.write(wav,sampleRate:48000,channels:[[1],[0.5]])
        store.stageIR([wav],headphone:true);try await settle(store)
        let review=try #require(store.irReview)
        #expect(review.proposed["right"]?.channel == 1)
        store.stageMappings(review.proposed,review:review)
        #expect(store.configuration == original)
        store.applyHeadphone();try await settle(store)
        let path=try #require(store.configuration.headphone.fir?["left"]?.path)
        #expect(path != wav.path)
        try FileManager.default.removeItem(at:wav)
        #expect(FileManager.default.fileExists(atPath:path))
        #expect(store.assetChannels[path] == 2)
        #expect(store.isValid)
        let reopened=FieldStore(supportDirectory:dir);try await settle(reopened)
        #expect(reopened.configuration == store.configuration)
        #expect(reopened.assetChannels[path] == 2)
    }
    @Test func configurationPreviewDoesNotReplaceUntilApply() async throws {
        let dir=try directory();defer{try? FileManager.default.removeItem(at:dir)}
        let store=FieldStore(supportDirectory:dir);try await settle(store)
        let original=store.configuration
        var c=original;c.safety.preampDb = -10
        let file=dir.appendingPathComponent("config.json");try c.jsonData().write(to:file)
        store.stageConfiguration(file);try await settle(store)
        #expect(store.configuration == original)
        let review=try #require(store.configurationReview)
        store.validateAndReplace(review.configuration);try await settle(store)
        #expect(store.configuration == c)
        #expect(store.configurationReview?.id == nil)
    }
    @Test func applyingOneSectionPreservesOtherDraftAndItsMetadata() async throws {
        let dir=try directory();defer{try? FileManager.default.removeItem(at:dir)}
        let store=FieldStore(supportDirectory:dir);try await settle(store)
        let file=dir.appendingPathComponent("pending.wav")
        try WAVFile.write(file,sampleRate:48000,channels:[[1],[0.5]])
        store.stageIR([file],headphone:true);try await settle(store)
        let review=try #require(store.irReview)
        store.stageMappings(review.proposed,review:review)
        let draft=store.headphoneDraft
        store.validateAndReplace(store.configuration,scope:.matrix);try await settle(store)
        #expect(store.headphoneDraft == draft)
        #expect(store.assetChannels[file.path] == 2)
    }
    @Test func inspectionRejectsWrongRateBeforeStagingAndCancelledDraftCannotApply() async throws {
        let dir=try directory();defer{try? FileManager.default.removeItem(at:dir)}
        let store=FieldStore(supportDirectory:dir);try await settle(store)
        let file=dir.appendingPathComponent("wrong.wav")
        try WAVFile.write(file,sampleRate:44100,channels:[[1]])
        store.stageIR([file],headphone:true);try await settle(store)
        let review=try #require(store.irReview)
        #expect(review.files.isEmpty)
        #expect(review.failures.count == 1)
        store.irReview=nil
        let original=store.configuration
        var changed=original;changed.safety.preampDb = -9
        store.validateAndReplace(changed)
        store.headphoneDraft.mode="peq"
        try await settle(store)
        #expect(store.configuration == original)
    }

    @Test func manualDuplicateChannelsRequireExplicitConfirmation() async throws {
        let dir=try directory();defer{try? FileManager.default.removeItem(at:dir)}
        let store=FieldStore(supportDirectory:dir);try await settle(store)
        let original=store.configuration
        let file=dir.appendingPathComponent("mono.wav")
        try WAVFile.write(file,sampleRate:48000,channels:[[1]])
        store.headphoneDraft.mode="fir"
        store.headphoneDraft.fir=["left":IRAsset(path:file.path),"right":IRAsset(path:file.path)]
        store.applyHeadphone()
        #expect(!store.isImporting)
        #expect(store.configuration == original)
        #expect(store.duplicateApplyScope == .headphone)
        store.confirmDuplicateApply(.headphone);try await settle(store)
        #expect(store.configuration.headphone.mode == "fir")
        #expect(store.isValid)
    }
    @Test func measurementConfirmationRevocationCancelsApply() async throws {
        let dir=try directory();defer{try? FileManager.default.removeItem(at:dir)}
        let store=FieldStore(supportDirectory:dir);try await settle(store)
        let original=store.configuration
        store.matrixCoordinatesConfirmed=true
        var changed=original;changed.safety.preampDb = -9
        store.validateAndReplace(changed,scope:.matrix)
        store.matrixCoordinatesConfirmed=false
        try await settle(store)
        #expect(store.configuration == original)
    }

}

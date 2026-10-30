import SwiftUI
import AppKit
import UniformTypeIdentifiers
import FieldWeaveCore
import FieldWeaveAudio

@MainActor final class FieldStore: ObservableObject {
    @Published var configuration = FieldConfiguration() { didSet { if !committingImport { scheduleCompile() } } }
    @Published var compiled: CompiledField?
    @Published var isCompiling = false
    @Published var isWorking = false
    @Published var isValid = false
    @Published var status = "Preparing FIR…"
    @Published var errorMessage: String?
    @Published var preset = "Custom"
    @Published var headphoneDraft = HeadphoneSettings() { didSet { if !committingImport { cancelImport() } } }
    @Published var externalizationDraft = ExternalizationSettings() { didSet { if !committingImport { cancelImport() } } }
    @Published var matrixCoordinatesConfirmed = false { didSet { if !committingImport { cancelImport() } } }
    @Published var assetChannels: [String:Int] = [:]
    @Published private(set) var isImporting = false
    @Published var irReview: IRImportReview?
    @Published var configurationReview: ConfigurationReview?
    @Published var duplicateApplyScope: ImportScope?
    private var confirmedDuplicateSignatures: [ImportScope:String] = [:]
    private var importToken = UUID()
    private var committingImport = false
    private var revision = 0
    private var work: Task<Void,Never>?
    private let supportURL: URL
    private var terminationObserver: NSObjectProtocol?
    let liveAudio: LiveAudioController
    @Published var audioRoute: AudioRouteSettings?
    @Published var selectedHRTF = "c01"
    var wantsLiveAudio = false
    var livePrepared = false
    var canProcess: Bool { compiled != nil && isValid && !isCompiling && !isWorking && !isImporting && errorMessage == nil }
    init(supportDirectory: URL? = nil) {
        supportURL = supportDirectory ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("FieldWeave",isDirectory:true)
        liveAudio = LiveAudioController(supportDirectory:supportURL)
        try? FileManager.default.createDirectory(at:supportURL,withIntermediateDirectories:true)
        let url = supportURL.appendingPathComponent("Autosave.json")
        if let saved = try? FieldConfiguration.read(from:url) { configuration = Self.resolveAssets(saved,relativeTo:supportURL) }
        if let profile=Self.bundledHRTFProfile(configuration) {selectedHRTF=profile}
        externalizationDraft = configuration.externalization
        headphoneDraft = configuration.headphone
        matrixCoordinatesConfirmed = configuration.externalization.coordinates != nil
        terminationObserver = NotificationCenter.default.addObserver(forName:NSApplication.willTerminateNotification,object:nil,queue:.main) { [weak self] _ in
            MainActor.assumeIsolated {self?.stopLiveAudio()}
        }
        scheduleCompile()
        refreshAssetMetadata()
    }
    deinit {
        if let terminationObserver {NotificationCenter.default.removeObserver(terminationObserver)}
    }
    func scheduleCompile() {
        cancelImport()
        revision += 1
        let generation = revision, config = configuration
        isValid = false; isCompiling = true; errorMessage = nil; status = "Designing FIR…"
        work?.cancel()
        work = Task { [weak self] in
            try? await Task.sleep(nanoseconds:180_000_000)
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority:.userInitiated) { Result { try FIRCompiler.compile(config,baseURL:URL(fileURLWithPath:"/")) } }.value
            guard let self, generation == self.revision, !Task.isCancelled else { return }
            self.isCompiling = false
            switch result {
            case .success(let field):
                self.compiled = field; self.isValid = true
                self.status = "FIR ready · \(field.report.matrixTaps) taps"
                if let data = try? config.jsonData() { try? data.write(to:self.supportURL.appendingPathComponent("Autosave.json"),options:.atomic) }
                self.synchronizeLiveAudio()
            case .failure(let error): self.errorMessage = error.localizedDescription; self.status = "Configuration needs attention"
            }
        }
    }
    func width(_ frequency: Double) -> Double {
        CurveDSP.evaluate(configuration.width,frequencies:[frequency]).first ?? 1
    }
    func setWidth(_ value:Double, band:Int) {
        var points = [[20.0,width(80)],[250,width(80)],[1000,width(1000)],[6000,width(10000)],[20000,width(10000)]]
        for i in (band == 0 ? [0,1] : band == 1 ? [2] : [3,4]) { points[i][1] = value }
        configuration.width.points = points; preset = "Custom"
    }
    func setCenter(pan:Double? = nil,gain:Double? = nil,elevation:Double? = nil,enabled:Bool? = nil) {
        var center = configuration.centerImaging ?? CenterSettings()
        if let enabled {
            center.enabled = enabled; center.pan = enabled ? center.pan ?? 0:nil; center.gainDb = enabled ? center.gainDb ?? 0:nil
            center.elevationDegrees = enabled ? center.elevationDegrees ?? 0:nil
            if !enabled {center.heightProfile=nil}
        }
        if center.enabled {
            if let pan { center.pan = pan }; if let gain { center.gainDb = gain }
            if let elevation {
                // Native slider/knob increments can leave a sub-nanodegree residue
                // at their zero stop. Keep the exact neutral DSP branch reachable.
                center.elevationDegrees=abs(elevation)<1e-9 ? 0:elevation
                center.heightProfile=selectedHRTF
            }
        }
        configuration.centerImaging = center; preset = "Custom"
    }
    nonisolated static func bundledHRTFProfile(_ config:FieldConfiguration)->String? {
        if let provenance=config.externalization.provenance,
           let id=CenterElevation.supportedProfiles.first(where:{provenance.contains("Personal-HRTF \($0),")}) {return id}
        if let id=config.centerImaging?.heightProfile,CenterElevation.supportedProfiles.contains(id) {return id}
        return nil
    }
    func selectPreset(_ name:String) {
        var c = FieldConfiguration()
        c.sampleRate = configuration.sampleRate; c.design = configuration.design
        switch name {
        case "Neutral": c.width.points = [[20,1],[250,1],[1000,1],[6000,1],[20000,1]]
        case "Studio": c.width.points = [[20,1.05],[250,1.05],[1000,1.1],[6000,1.15],[20000,1.15]]
        case "Immersive": c.width.points = [[20,1.25],[250,1.25],[1000,1.4],[6000,1.65],[20000,1.65]]
        case "Vintage Stereo": c.width.points = [[20,0.9],[250,0.9],[1000,1],[6000,1.1],[20000,1.1]]; c.crossfeed = CrossfeedSettings(amount:0.18,delayMs:0.25)
        default: break
        }
        configuration = c; externalizationDraft = c.externalization; headphoneDraft = c.headphone; matrixCoordinatesConfirmed=false; preset = name
    }
    func reset() { configuration = FieldConfiguration(); externalizationDraft = configuration.externalization; headphoneDraft = configuration.headphone; preset = "Custom"; matrixCoordinatesConfirmed=false }
    nonisolated static func resolveAssets(_ input:FieldConfiguration,relativeTo base:URL) -> FieldConfiguration {
        var c = input
        func resolve(_ assets:[String:IRAsset]?) -> [String:IRAsset]? { assets?.mapValues { asset in var a=asset; if !a.path.hasPrefix("/") { a.path=base.appendingPathComponent(a.path).standardizedFileURL.path }; a.path=URL(fileURLWithPath:a.path).standardizedFileURL.resolvingSymlinksInPath().path; return a } }
        c.headphone.fir=resolve(c.headphone.fir); c.externalization.paths=resolve(c.externalization.paths); return c
    }
    func cancelImport() {
        importToken = UUID()
        if isImporting {status="Import superseded by newer edits"}
        isImporting = false
    }
    private func beginImport() -> UUID {
        cancelImport()
        errorMessage = nil
        isImporting = true
        return importToken
    }
    func openConfiguration() {
        let panel=NSOpenPanel(); panel.allowedContentTypes=[.json]; panel.allowsMultipleSelection=false
        guard panel.runModal() == .OK, let url=panel.url else { return }
        stageConfiguration(url)
    }
    func stageConfiguration(_ url: URL) {
        let token=beginImport()
        irReview=nil; configurationReview=nil
        status="Validating imported configuration…"
        Task {
            let result=await Task.detached { Result { () -> ConfigurationReview in
                let c=Self.resolveAssets(try FieldConfiguration.read(from:url),relativeTo:url.deletingLastPathComponent())
                let files=try Self.inspectAssets(c)
                return ConfigurationReview(url:url,configuration:c,files:files)
            }}.value
            guard token == importToken else { return }
            isImporting=false
            switch result {
            case .success(let review): configurationReview=review; status="Ready to review"
            case .failure(let error): errorMessage=error.localizedDescription; status="Import rejected; previous configuration retained"
            }
        }
    }
    enum ImportScope: Hashable {case configuration,headphone,matrix}
    func validateAndReplace(_ config:FieldConfiguration,scope:ImportScope = .configuration) {
        let token=beginImport(), requestedRevision=revision
        let assetRoot=supportURL.appendingPathComponent("Assets",isDirectory:true)
        status="Validating imported configuration…"
        Task {
            let result=await Task.detached { Result { () -> PreparedImport in
                let managed=try ManagedAssets.copy(config,to:assetRoot)
                do {
                    let files=try Self.inspectAssets(managed.configuration)
                    let compiled=try FIRCompiler.compile(managed.configuration,baseURL:URL(fileURLWithPath:"/"))
                    return PreparedImport(configuration:managed.configuration,compiled:compiled,files:files,directory:managed.directory)
                } catch { if let directory=managed.directory {try? FileManager.default.removeItem(at:directory)}; throw error }
            }}.value
            guard token == importToken, requestedRevision == revision else {
                if case .success(let prepared)=result,let directory=prepared.directory {try? FileManager.default.removeItem(at:directory)}
                return
            }
            isImporting=false
            switch result {
            case .success(let prepared):
                do {try prepared.configuration.jsonData().write(to:supportURL.appendingPathComponent("Autosave.json"),options:.atomic)}
                catch {
                    if let directory=prepared.directory {try? FileManager.default.removeItem(at:directory)}
                    errorMessage=error.localizedDescription;status="Import rejected; previous configuration retained";return
                }
                work?.cancel(); revision += 1
                committingImport=true; configuration=prepared.configuration
                if scope != .matrix {headphoneDraft=configuration.headphone}
                if scope != .headphone {
                    externalizationDraft=configuration.externalization
                    matrixCoordinatesConfirmed=configuration.externalization.coordinates != nil
                }
                committingImport=false
                assetChannels.merge(Dictionary(uniqueKeysWithValues:prepared.files.map{($0.url.path,$0.channelCount)})){_,new in new}
                compiled=prepared.compiled; isCompiling=false; isValid=true; preset="Custom"
                if let profile=Self.bundledHRTFProfile(configuration) {selectedHRTF=profile}
                errorMessage=nil; status="FIR ready · \(prepared.compiled.report.matrixTaps) taps"
                configurationReview=nil
                synchronizeLiveAudio()
            case .failure(let error): errorMessage=error.localizedDescription; status="Import rejected; previous configuration retained"
            }
        }
    }
    nonisolated static func inspectAssets(_ config:FieldConfiguration) throws -> [IRFileInfo] {
        let assets=Array((config.headphone.fir ?? [:]).values)+Array((config.externalization.paths ?? [:]).values)
        let urls=Set(assets.map{URL(fileURLWithPath:$0.path).standardizedFileURL.resolvingSymlinksInPath()})
        let files=try urls.sorted{$0.path<$1.path}.map{try IRImport.inspect($0,sampleRate:config.sampleRate)}
        for asset in assets {
            guard let file=files.first(where:{$0.url.path == URL(fileURLWithPath:asset.path).standardizedFileURL.resolvingSymlinksInPath().path}), (0..<file.channelCount).contains(asset.channel) else {throw FieldError.invalid("IR channel out of range")}
        }
        return files
    }
    private func refreshAssetMetadata() {
        let c=configuration
        Task {
            let files=await Task.detached {try? Self.inspectAssets(c)}.value
            guard configuration == c,let files else {return}
            assetChannels.merge(Dictionary(uniqueKeysWithValues:files.map{($0.url.path,$0.channelCount)})){_,new in new}
        }
    }
    func saveConfiguration() {
        let p=NSSavePanel(); p.allowedContentTypes=[.json]; p.nameFieldStringValue="FieldWeave.json"
        guard p.runModal() == .OK,let url=p.url else {return}
        do { try configuration.jsonData().write(to:url,options:.atomic); status="Configuration saved" } catch {errorMessage=error.localizedDescription}
    }
    func exportFIR() {
        guard canProcess,let field=compiled else{return}
        let p=NSOpenPanel();p.canChooseDirectories=true;p.canChooseFiles=false;p.canCreateDirectories=true;p.prompt=L("Export here")
        guard p.runModal() == .OK,let url=p.url else{return}
        let config=configuration;isWorking=true
        let destination=url.appendingPathComponent("FieldWeave-"+ISO8601DateFormatter().string(from:Date()).replacingOccurrences(of:":",with:"-")+"-"+String(UUID().uuidString.prefix(6)),isDirectory:true)
        Task { let result=await Task.detached { Result { try FieldExporter.export(field,configuration:config,to:destination,baseURL:URL(fileURLWithPath:"/")) } }.value;isWorking=false;switch result{case .success:status="FIR package exported";NSWorkspace.shared.activateFileViewerSelecting([destination]);case .failure(let e):errorMessage=e.localizedDescription} }
    }
    func renderAudio() {
        guard canProcess,let field=compiled else{return}
        let p=NSOpenPanel();p.allowedContentTypes=[.wav];p.prompt=L("Choose input WAV")
        guard p.runModal() == .OK,let input=p.url else{return}
        let s=NSSavePanel();s.allowedContentTypes=[.wav];s.nameFieldStringValue=input.deletingPathExtension().lastPathComponent+"-FieldWeave.wav"
        guard s.runModal() == .OK,let output=s.url else{return}
        guard input.standardizedFileURL != output.standardizedFileURL else {errorMessage="Please choose a different output file.";return}
        isWorking=true;status="Rendering WAV…"
        Task { let result=await Task.detached { Result { try FIRProcessor.render(input:input,output:output,compiled:field) } }.value;isWorking=false;switch result {case .success(let report):status=String(format:"Rendered %d frames · peak %.2f dBFS",report.frames,20*log10(max(report.peak,1e-12)));case .failure(let e):errorMessage=e.localizedDescription} }
    }
    func importIR(path:String?=nil,headphone:Bool=false,folder:Bool=false) {
        let panel=NSOpenPanel(); panel.allowedContentTypes=[.wav]
        panel.allowsMultipleSelection = !folder && path == nil
        panel.canChooseDirectories=folder
        panel.canChooseFiles = !folder
        panel.begin { [weak self] response in
            guard response == .OK else {return}
            self?.stageIR(panel.urls,headphone:headphone,path:path)
        }
    }
    func stageIR(_ urls:[URL],headphone:Bool,path:String?=nil) {
        let token=beginImport(),sampleRate=configuration.sampleRate
        configurationReview=nil; irReview=nil
        status="Checking files…"
        Task {
            let result=await Task.detached { Result { () -> IRImportReview in
                let expanded=try IRImport.expand(urls)
                var files:[IRFileInfo]=[],failures:[ImportFailure]=[]
                for url in expanded {
                    do {files.append(try IRImport.inspect(url,sampleRate:sampleRate))}
                    catch {failures.append(ImportFailure(name:url.lastPathComponent,message:error.localizedDescription))}
                }
                return IRImportReview(headphone:headphone,fixedPath:path,sampleRate:sampleRate,files:files,failures:failures)
            }}.value
            guard token == importToken else {return}
            isImporting=false
            switch result {
            case .success(let review): irReview=review; status="Ready to review"
            case .failure(let error): errorMessage=error.localizedDescription; status="Import rejected; previous configuration retained"
            }
        }
    }
    func stageMappings(_ mapping:[String:IRAsset],review:IRImportReview) {
        guard review.sampleRate == configuration.sampleRate else {errorMessage=L("Sample rate changed; import the files again.");return}
        for file in review.files {assetChannels[file.url.path]=file.channelCount}
        cancelImport()
        if review.headphone {
            var draft=headphoneDraft
            draft.mode="fir";draft.peq=nil
            if review.fixedPath == nil {draft.fir=mapping}
            else {var assets=draft.fir ?? [:];assets.merge(mapping){_,new in new};draft.fir=assets}
            headphoneDraft=draft
        } else {
            var draft=externalizationDraft
            if review.fixedPath == nil {draft.paths=mapping}
            else {var assets=draft.paths ?? [:];assets.merge(mapping){_,new in new};draft.paths=assets}
            externalizationDraft=draft
            matrixCoordinatesConfirmed=false
            externalizationDraft.kind=nil;externalizationDraft.provenance=nil;externalizationDraft.coordinates=nil
        }
        let scope:ImportScope=review.headphone ? .headphone:.matrix
        confirmedDuplicateSignatures[scope]=Self.duplicateSignature(review.headphone ? headphoneDraft.fir:externalizationDraft.paths)
        irReview=nil;status="Draft ready · Apply to activate"
    }
    func updateCrossfeed(amount:Double? = nil,delay:Double? = nil) {
        guard configuration.crossfeed.enabled else{return}
        let old=configuration.crossfeed
        let currentAmount=old.curve.map{CurveDSP.evaluate($0,frequencies:[20]).first ?? 0.15} ?? 0.15
        configuration.crossfeed=CrossfeedSettings(amount:amount ?? currentAmount,delayMs:delay ?? old.delayMs ?? 0.25,allowWithExternalization:old.allowWithExternalization ?? false)
    }
    nonisolated static func duplicateSignature(_ assets:[String:IRAsset]?) -> String? {
        guard let assets else {return nil}
        let channels=assets.values.map{"\(URL(fileURLWithPath:$0.path).standardizedFileURL.resolvingSymlinksInPath().path)#\($0.channel)"}
        guard Set(channels).count < channels.count else {return nil}
        return assets.keys.sorted().map{"\($0):\(assets[$0]!.path)#\(assets[$0]!.channel)"}.joined(separator:"|")
    }
    private func needsDuplicateConfirmation(_ assets:[String:IRAsset]?,scope:ImportScope)->Bool {
        guard let signature=Self.duplicateSignature(assets), confirmedDuplicateSignatures[scope] != signature else {return false}
        duplicateApplyScope=scope;return true
    }
    func confirmDuplicateApply(_ scope:ImportScope) {
        confirmedDuplicateSignatures[scope]=Self.duplicateSignature(scope == .headphone ? headphoneDraft.fir:externalizationDraft.paths)
        duplicateApplyScope=nil
        if scope == .headphone {applyHeadphone()} else {applyExternalization()}
    }
    func applyExternalization() {
        guard matrixCoordinatesConfirmed, externalizationDraft.kind != nil, !(externalizationDraft.provenance ?? "").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {errorMessage=L("Choose the IR kind, enter its source, and confirm the measurement coordinates.");return}
        guard !needsDuplicateConfirmation(externalizationDraft.paths,scope:.matrix) else {return}
        var c=configuration
        var e=externalizationDraft
        e.mode="matrix_ir"; e.normalization=e.normalization ?? "none"; e.coordinates=e.coordinates ?? SourceCoordinates()
        c.externalization=e;validateAndReplace(c,scope:.matrix)
    }
    func bypassExternalization() { configuration.externalization=ExternalizationSettings() }
    func applyHeadphone() {
        if headphoneDraft.mode == "fir",needsDuplicateConfirmation(headphoneDraft.fir,scope:.headphone) {return}
        var c=configuration
        var h=headphoneDraft
        if h.mode=="bypass" {h=HeadphoneSettings()}
        if h.mode=="peq" {h.fir=nil}
        if h.mode=="fir" {h.peq=nil}
        c.headphone=h;validateAndReplace(c,scope:.headphone)
    }
    func importPEQ() {
        let panel=NSOpenPanel();panel.allowedContentTypes=[.json];guard panel.runModal() == .OK,let url=panel.url else{return}
        stagePEQ(url)
    }
    func stagePEQ(_ url:URL) {
        let token=beginImport(),sampleRate=configuration.sampleRate
        status="Checking files…"
        Task {
            let result=await Task.detached {Result {try PEQImport.read(url,sampleRate:sampleRate)}}.value
            guard token == importToken else {return}
            isImporting=false
            switch result {
            case .success(let bands):
                var draft=HeadphoneSettings();draft.mode="peq";draft.peq=bands;draft.provenance=url.lastPathComponent
                headphoneDraft=draft;status="Draft ready · Apply to activate"
            case .failure(let error): errorMessage=error.localizedDescription;status="Import rejected; previous configuration retained"
            }
        }
    }
}

private struct PreparedImport: Sendable {
    var configuration: FieldConfiguration
    var compiled: CompiledField
    var files: [IRFileInfo]
    var directory: URL?
}

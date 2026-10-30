import SwiftUI
import FieldWeaveCore

struct ImportFailure: Identifiable, Sendable {
    let id = UUID()
    var name: String
    var message: String
}
struct IRImportReview: Identifiable, Sendable {
    let id = UUID()
    var headphone: Bool
    var fixedPath: String?
    var sampleRate: Int
    var files: [IRFileInfo]
    var failures: [ImportFailure]
    var keys: [String] { fixedPath.map{[$0]} ?? (headphone ? ["left","right"] : ["LL","LR","RL","RR"]) }
    var proposed: [String:IRAsset] {
        if let path=fixedPath,files.count == 1,let file=files.first {
            let right=path == "right" || path == "LR" || path == "RR"
            return [path:IRAsset(path:file.url.path,channel:right && file.channelCount == 2 ? 1:0)]
        }
        return IRImport.suggestions(files,headphone:headphone)
    }
}
struct ConfigurationReview: Identifiable, Sendable {
    let id = UUID()
    var url: URL
    var configuration: FieldConfiguration
    var files: [IRFileInfo]
}

func importPathLabel(_ key:String) -> String {
    switch key {
    case "left":return L("Left ear")
    case "right":return L("Right ear")
    case "LL":return L("Left → Left")
    case "LR":return L("Left → Right")
    case "RL":return L("Right → Left")
    case "RR":return L("Right → Right")
    default:return key
    }
}
struct IRImportReviewView: View {
    @AppStorage(AppLanguage.key) private var interfaceLanguage = "en"
    @ObservedObject var store: FieldStore
    let review: IRImportReview
    @FWState private var mapping: [String:IRAsset]
    @FWState private var allowDuplicates = false
    init(store:FieldStore,review:IRImportReview) {
        self.store=store;self.review=review;_mapping=FWState(initialValue:review.proposed)
    }
    private var complete:Bool {
        review.keys.allSatisfy { key in
            guard let asset=mapping[key],let file=review.files.first(where:{$0.url.path == asset.path}) else {return false}
            return (0..<file.channelCount).contains(asset.channel)
        }
    }
    private var duplicates:Bool {
        var effective=review.fixedPath == nil ? [:]:(review.headphone ? store.headphoneDraft.fir ?? [:]:store.externalizationDraft.paths ?? [:])
        effective.merge(mapping){_,new in new}
        return FieldStore.duplicateSignature(effective) != nil
    }
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            HStack { Text(L("Review import")).font(.title2);Spacer();Text(review.headphone ? L("Headphone EQ") : L("HRTF / room")).foregroundStyle(.secondary) }
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    Grid(alignment:.leading,horizontalSpacing:12,verticalSpacing:14) {
                        GridRow {Text(L("Destination"));Text(L("File"));Text(L("WAV channel"))}.font(.caption).foregroundStyle(.secondary)
                        ForEach(review.keys,id:\.self) {key in
                            GridRow {
                                Text(importPathLabel(key)).frame(width:100,alignment:.leading)
                                Picker(L("File"),selection:Binding(get:{mapping[key]?.path ?? ""},set:{path in
                                    if path.isEmpty {mapping.removeValue(forKey:key)}
                                    else {let file=review.files.first{$0.url.path == path};let right=key == "right" || key == "LR" || key == "RR";mapping[key]=IRAsset(path:path,channel:right && file?.channelCount == 2 ? 1:0)}
                                    allowDuplicates=false
                                })) {
                                    Text(L("Choose…")).tag("")
                                    ForEach(review.files,id:\.url) { file in Text(file.url.lastPathComponent).tag(file.url.path) }
                                }.labelsHidden().frame(minWidth:230)
                                if let asset=mapping[key],let file=review.files.first(where:{$0.url.path == asset.path}) {
                                    Picker(L("WAV channel"),selection:Binding(get:{mapping[key]?.channel ?? 0},set:{mapping[key]?.channel=$0;allowDuplicates=false})) {
                                        ForEach(0..<file.channelCount,id:\.self){Text("\($0+1)").tag($0)}
                                    }.labelsHidden().frame(width:85)
                                } else { Text("—").frame(width:85) }
                            }
                        }
                    }
                    if duplicates {Toggle(L("Use the same channel for multiple paths"),isOn:$allowDuplicates).tint(.orange)}
                    Divider()
                    if review.files.isEmpty && review.failures.isEmpty {Text(L("No WAV files found.")).font(.callout).foregroundStyle(.secondary)}
                    ForEach(review.files,id:\.url) {file in
                        HStack(alignment:.top) {
                            Image(systemName:"checkmark.circle.fill").foregroundStyle(Color.midBand)
                            Text(file.url.lastPathComponent).lineLimit(2).help(file.url.path)
                            Spacer()
                            Text("\(file.sampleRate) Hz · \(file.channelCount) \(L("channels")) · \(file.frameCount) \(L("taps"))").foregroundStyle(.secondary).monospacedDigit()
                        }.font(.caption)
                    }
                    ForEach(review.failures){failure in
                        VStack(alignment:.leading,spacing:4){Label(failure.name,systemImage:"exclamationmark.triangle");Text(L(failure.message)).textSelection(.enabled)}.font(.caption).foregroundStyle(.orange)
                    }
                }.padding(2)
            }
            HStack {
                Button(L("Cancel")){store.irReview=nil}.keyboardShortcut(.cancelAction)
                Spacer()
                Button(L("Use mappings")){store.stageMappings(mapping.filter{review.keys.contains($0.key)},review:review)}
                    .keyboardShortcut(.defaultAction).disabled(!complete || (duplicates && !allowDuplicates))
            }
        }.padding(26).frame(width:720,height:490).background(Color.fieldBackground).preferredColorScheme(.dark)
    }
}

struct ConfigurationReviewView: View {
    @AppStorage(AppLanguage.key) private var interfaceLanguage = "en"
    @ObservedObject var store:FieldStore
    let review:ConfigurationReview
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            Text(L("Review configuration")).font(.title2)
            Text(review.url.lastPathComponent).font(.headline)
            Grid(alignment:.leading,horizontalSpacing:25,verticalSpacing:10) {
                GridRow {Text(L("Sample rate"));Text("\(review.configuration.sampleRate) Hz")}
                GridRow {Text(L("Headphone EQ"));Text(review.configuration.headphone.mode.uppercased())}
                GridRow {Text(L("HRTF / room"));Text(L(review.configuration.externalization.mode == "bypass" ? "Bypassed" : "Matrix active"))}
                GridRow {Text(L("Center height"));Text(String(format:"%+.1f°",review.configuration.centerImaging?.enabled == true ? review.configuration.centerImaging?.elevationDegrees ?? 0:0))}
                GridRow {Text(L("Crossfeed"));Text(L(review.configuration.crossfeed.enabled ? "Enabled" : "Bypassed"))}
            }.font(.callout)
            ScrollView {
                VStack(alignment:.leading,spacing:9) {
                    ForEach(review.files,id:\.url) {file in
                        Label("\(file.url.lastPathComponent) · \(file.sampleRate) Hz · \(file.channelCount) \(L("channels"))",systemImage:"checkmark.circle").font(.caption).help(file.url.path)
                    }
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
            HStack {
                Button(L("Cancel")){store.cancelImport();store.configurationReview=nil}.keyboardShortcut(.cancelAction)
                Spacer()
                if store.isImporting {ProgressView().controlSize(.small)}
                Button(L("Apply configuration")){store.validateAndReplace(review.configuration)}.keyboardShortcut(.defaultAction).disabled(store.isImporting)
            }
        }.padding(26).frame(width:580,height:420).background(Color.fieldBackground).preferredColorScheme(.dark)
        .interactiveDismissDisabled(store.isImporting)
    }
}

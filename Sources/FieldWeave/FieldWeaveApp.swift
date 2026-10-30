import SwiftUI
import AppKit

@main
struct FieldWeaveApp:App {
    @AppStorage(AppLanguage.key) private var interfaceLanguage = "en"
    @StateObject private var store=FieldStore()
    var body:some Scene {
        WindowGroup {
            ContentView(store:store)
                .preferredColorScheme(.dark)
                .frame(minWidth:1100,minHeight:760)
        }
        .defaultSize(width:1440,height:960)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing:.newItem) {
                Button(L("Open configuration…")) {store.openConfiguration()}.keyboardShortcut("o")
                Button(L("Save configuration…")) {store.saveConfiguration()}.keyboardShortcut("s")
                Divider()
                Button(L("Export FIR package…")) {store.exportFIR()}.keyboardShortcut("e",modifiers:[.command,.shift])
                Button(L("Render audio WAV…")) {store.renderAudio()}.keyboardShortcut("r",modifiers:[.command,.shift])
            }
        }
    }
}

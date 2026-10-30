import Foundation
import FieldWeaveCore
import FieldWeaveAudio

extension FieldStore {
    func prepareLiveAudio() {
        guard !livePrepared else { return }
        livePrepared = true
        do { try liveAudio.recoverInterruptedRoute() }
        catch { errorMessage = error.localizedDescription; return }
        liveAudio.refreshDevices()
        if let id=Self.bundledHRTFProfile(configuration) {selectedHRTF=id}
        audioRoute = liveAudio.savedSettings()
        if audioRoute == nil,
           let capture = liveAudio.devices.first(where: { $0.name == "BlackHole 2ch" }),
           let playback = liveAudio.devices.first(where: { $0.name == "NICEHCK NK1 Ultra" }) {
            audioRoute = AudioRouteSettings(captureUID:capture.uid,playbackUID:playback.uid)
        }
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of:"--personal-hrtf"), arguments.indices.contains(index+1) {
            loadHRTFCandidate(arguments[index+1], resetSound:true)
        }
        if arguments.contains("--enable-live-audio"), var settings = audioRoute {
            settings.autoStart = true
            audioRoute = settings
            do { try liveAudio.saveSettings(settings) } catch { errorMessage = error.localizedDescription }
        }
        wantsLiveAudio = audioRoute?.autoStart == true
        synchronizeLiveAudio()
    }

    func loadHRTFCandidate(_ id:String, resetSound:Bool=false) {
        // Xcode-style bundles and native SwiftPM bundles place copied resources differently.
        let configURL = Bundle.module.url(forResource:id,withExtension:"json",subdirectory:"Resources/PersonalHRTF")
            ?? Bundle.module.url(forResource:id,withExtension:"json",subdirectory:"PersonalHRTF")
        guard (1...7).map({String(format:"c%02d",$0)}).contains(id), let configURL else {
            errorMessage = "The requested HRTF candidate is unavailable"; return
        }
        do {
            let imported = Self.resolveAssets(try FieldConfiguration.read(from:configURL),relativeTo:configURL.deletingLastPathComponent())
            var next = resetSound ? imported:configuration
            next.sampleRate = imported.sampleRate
            next.externalization = imported.externalization
            if next.centerImaging?.enabled == true {next.centerImaging?.heightProfile=id}
            // The imported matrix already contains the acoustic cross-ear paths.
            next.crossfeed = CrossfeedSettings()
            selectedHRTF = id
            validateAndReplace(next)
        } catch { errorMessage = error.localizedDescription }
    }

    func setAudioRoute(_ settings:AudioRouteSettings) {
        audioRoute = settings
        do { try liveAudio.saveSettings(settings) } catch { errorMessage = error.localizedDescription }
    }

    func startLiveAudio() {
        wantsLiveAudio = true
        synchronizeLiveAudio()
    }

    func stopLiveAudio() {
        wantsLiveAudio = false
        liveAudio.stop()
    }

    func synchronizeLiveAudio() {
        guard livePrepared, wantsLiveAudio, !liveAudio.isStarting, isValid, !isCompiling, !isImporting,
              let compiled, let settings = audioRoute else { return }
        let config = configuration
        Task { [weak self] in
            guard let self, self.wantsLiveAudio, self.livePrepared, self.isValid,
                  !self.isCompiling, !self.isImporting, self.configuration == config else { return }
            do {
                if self.liveAudio.isRunning {
                    try await self.liveAudio.update(compiled:compiled,configuration:config,baseURL:URL(fileURLWithPath:"/"))
                } else {
                    try await self.liveAudio.start(compiled:compiled,configuration:config,baseURL:URL(fileURLWithPath:"/"),settings:settings)
                    if !self.wantsLiveAudio { self.liveAudio.stop(); return }
                    if self.liveAudio.activeConfiguration != self.configuration { self.synchronizeLiveAudio() }
                }
            } catch {
                if error is CancellationError { return }
                if self.wantsLiveAudio { self.errorMessage = error.localizedDescription }
            }
        }
    }
}

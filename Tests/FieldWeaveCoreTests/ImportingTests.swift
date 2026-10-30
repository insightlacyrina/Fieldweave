import Foundation
import Testing
@testable import FieldWeaveCore

@Suite struct ImportingTests {
    private func temporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("fieldweave-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        return try body(directory)
    }

    private func info(_ name: String, channels: Int = 1) -> IRFileInfo {
        IRFileInfo(url: URL(fileURLWithPath: "/tmp/\(name).wav"), channelCount: channels, sampleRate: 48000, frameCount: 32)
    }

    @Test func singleStereoHeadphoneUsesDifferentEarChannels() {
        let file = info("correction", channels: 2)
        let mapping = IRImport.suggestions([file], headphone: true)
        #expect(mapping["left"] == IRAsset(path: file.url.path, channel: 0))
        #expect(mapping["right"] == IRAsset(path: file.url.path, channel: 1))
        #expect(IRImport.suggestions([file, file], headphone: true) == mapping)
    }

    @Test func headphoneRoutingRequiresUnambiguousFilenameTokens() {
        let left = info("headphone-left"), right = info("headphone_R", channels: 2)
        let unknown = info("cleft"), ambiguous = info("left_right"), duplicate = info("other-left")
        let mapping = IRImport.suggestions([unknown, right, ambiguous, left], headphone: true)
        #expect(mapping == ["left": IRAsset(path: left.url.path), "right": IRAsset(path: right.url.path, channel: 1)])
        let duplicateMapping = IRImport.suggestions([right, left, duplicate], headphone: true)
        #expect(duplicateMapping["left"] == nil)
        #expect(duplicateMapping["right"]?.path == right.url.path)
        #expect(IRImport.suggestions([info("unknown-a"), info("unknown-b")], headphone: true).isEmpty)
        #expect(IRImport.suggestions([info("left", channels: 4), info("right", channels: 4)], headphone: true).isEmpty)
    }

    @Test func matrixRoutingUsesSourceThenEarAndNeverSubstringGuesses() {
        let files = ["LL", "LR", "RL", "RR"].map { info("room_\($0)") }
        let mapping = IRImport.suggestions(Array(files.reversed()), headphone: false)
        for (key, file) in zip(["LL", "LR", "RL", "RR"], files) {
            #expect(mapping[key] == IRAsset(path: file.url.path))
        }
        #expect(IRImport.suggestions([info("small"), info("LL_LR"), info("LL", channels: 2)], headphone: false).isEmpty)
        let duplicates = IRImport.suggestions(files + [info("other_LL")], headphone: false)
        #expect(duplicates["LL"] == nil)
        #expect(duplicates.count == 3)
    }

    @Test func sourceStereoMappingPreservesMatrixDirection() {
        let left = info("left_source", channels: 2), right = info("source_right", channels: 2)
        let mapping = IRImport.suggestions([right, left], headphone: false)
        #expect(mapping["LL"] == IRAsset(path: left.url.path, channel: 0))
        #expect(mapping["LR"] == IRAsset(path: left.url.path, channel: 1))
        #expect(mapping["RL"] == IRAsset(path: right.url.path, channel: 0))
        #expect(mapping["RR"] == IRAsset(path: right.url.path, channel: 1))
        #expect(IRImport.suggestions([info("left_source_right", channels: 2)], headphone: false).isEmpty)
        #expect(IRImport.suggestions([info("left", channels: 2), info("right", channels: 2)], headphone: false).isEmpty)
        #expect(IRImport.suggestions([left, info("alternate_left_source", channels: 2)], headphone: false).isEmpty)
    }

    @Test func explicitSourceEarAliasesMapMonoWithoutGuessingConflicts() {
        let files = ["LS_LE", "LS_RE", "RS_LE", "RS_RE"].map { info($0) }
        let mapping = IRImport.suggestions(files, headphone: false)
        for (key, file) in zip(["LL", "LR", "RL", "RR"], files) {
            #expect(mapping[key] == IRAsset(path: file.url.path, channel: 0))
        }
        let ambiguous = ["LS_RS_LE", "LS_LE_RE", "LS_LE_RR", "LS_LE_LL_LR", "LS", "LE", "left_source_RS_LE"]
        for name in ambiguous {
            #expect(IRImport.suggestions([info(name)], headphone: false).isEmpty)
        }
        #expect(IRImport.suggestions([info("LS_LE", channels: 2)], headphone: false).isEmpty)
        #expect(IRImport.suggestions([info("LS_LE"), info("other_LS_LE")], headphone: false).isEmpty)
        #expect(IRImport.suggestions([info("LS_LE_LL")], headphone: false)["LL"] != nil)
    }

    @Test func inspectionReturnsActualMetadataAndRejectsRateOrLength() throws {
        try temporaryDirectory { directory in
            let stereo = directory.appendingPathComponent("stereo.wav")
            try WAVFile.write(stereo, sampleRate: 48000, channels: [[1, 0, 0], [0.5, 0, 0]])
            let metadata = try IRImport.inspect(stereo, sampleRate: 48000)
            #expect(metadata.channelCount == 2)
            #expect(metadata.sampleRate == 48000)
            #expect(metadata.frameCount == 3)
            #expect(throws: Error.self) { try IRImport.inspect(stereo, sampleRate: 44100) }
            let mono = directory.appendingPathComponent("mono.wav")
            try WAVFile.write(mono, sampleRate: 48000, channels: [[1]])
            #expect(try IRImport.inspect(mono, sampleRate: 48000).channelCount == 1)
            let long = directory.appendingPathComponent("long.wav")
            try WAVFile.write(long, sampleRate: 48000, channels: [Array(repeating: 0, count: IRImport.maximumFrames + 1)])
            #expect(throws: Error.self) { try IRImport.inspect(long, sampleRate: 48000) }
            let malformed = directory.appendingPathComponent("malformed.wav")
            try Data("not a wave file".utf8).write(to: malformed)
            #expect(throws: Error.self) { try IRImport.inspect(malformed, sampleRate: 48000) }
        }
    }

    @Test func folderSelectionIsBoundedNonrecursiveAndDeduplicated() throws {
        try temporaryDirectory { directory in
            let visible = directory.appendingPathComponent("correction.WAV")
            let hidden = directory.appendingPathComponent(".hidden.wav")
            let other = directory.appendingPathComponent("notes.json")
            for file in [visible, hidden, other] { try Data().write(to: file) }
            let nested = directory.appendingPathComponent("nested", isDirectory: true)
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            try Data().write(to: nested.appendingPathComponent("nested.wav"))
            let results = try IRImport.expand([directory, visible])
            #expect(results == [visible.standardizedFileURL.resolvingSymlinksInPath()])
            for index in 0..<IRImport.maximumFiles {
                try Data().write(to: directory.appendingPathComponent("\(index).wav"))
            }
            #expect(throws: Error.self) { try IRImport.expand([directory]) }
        }
    }

    @Test func strictPEQRejectsUnsupportedMissingNullAndInvalidValues() throws {
        let valid = Data("[{\"frequency_hz\":1000,\"q\":1,\"gain_db\":-3}]".utf8)
        #expect(try PEQImport.decode(valid, sampleRate: 48000) == [PEQBand(frequencyHz: 1000, q: 1, gainDb: -3)])
        let invalid = [
            "{\"bands\":[]}",
            "[null]",
            "[{\"frequency_hz\":1000,\"q\":1,\"gain_db\":-3,\"type\":\"peak\"}]",
            "[{\"frequency_hz\":1000,\"q\":1}]",
            "[{\"frequency_hz\":1000,\"q\":null,\"gain_db\":-3}]",
            "[{\"frequency_hz\":24000,\"q\":1,\"gain_db\":-3}]",
            "[{\"frequency_hz\":1000,\"q\":0,\"gain_db\":-3}]",
            "[{\"frequency_hz\":1000,\"q\":1,\"gain_db\":25}]",
            "[{\"frequency_hz\":true,\"q\":1,\"gain_db\":-3}]"
        ]
        for json in invalid {
            #expect(throws: Error.self) { try PEQImport.decode(Data(json.utf8), sampleRate: 48000) }
        }
        let band = ["frequency_hz": 1000.0, "q": 1.0, "gain_db": -3.0]
        let tooMany = try JSONSerialization.data(withJSONObject: Array(repeating: band, count: 65))
        #expect(throws: Error.self) { try PEQImport.decode(tooMany, sampleRate: 48000) }
        #expect(throws: Error.self) { try PEQImport.decode(valid, sampleRate: 7000) }
        #expect(throws: Error.self) { try PEQImport.decode(Data("[{\"frequency_hz\":23000,\"q\":1,\"gain_db\":0}]".utf8), sampleRate: 44100) }
    }

    @Test func managedCopiesDeduplicateAndSurviveOriginalDeletion() throws {
        try temporaryDirectory { directory in
            let original = directory.appendingPathComponent("correction.wav")
            try WAVFile.write(original, sampleRate: 48000, channels: [[1, 0], [0.5, 0]])
            let alias = directory.appendingPathComponent("alias.wav")
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: original)
            var configuration = FieldConfiguration()
            configuration.headphone.mode = "fir"
            configuration.headphone.fir = ["left": IRAsset(path: original.path), "right": IRAsset(path: alias.path, channel: 1)]
            let root = directory.appendingPathComponent("assets", isDirectory: true)
            let result = try ManagedAssets.copy(configuration, to: root)
            let transaction = try #require(result.directory)
            #expect(try FileManager.default.contentsOfDirectory(atPath: transaction.path).count == 1)
            let left = try #require(result.configuration.headphone.fir?["left"])
            let right = try #require(result.configuration.headphone.fir?["right"])
            #expect(left.path == right.path)
            #expect(left.channel == 0 && right.channel == 1)
            try FileManager.default.removeItem(at: original)
            #expect(try IRImport.inspect(URL(fileURLWithPath: left.path), sampleRate: 48000).channelCount == 2)
            let reused = try ManagedAssets.copy(result.configuration, to: root)
            #expect(reused.configuration == result.configuration)
            #expect(reused.directory == nil)
            #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).count == 1)
        }
    }

    @Test func managedAssetFailureRollsBackOnlyItsOwnTransaction() throws {
        try temporaryDirectory { directory in
            let original = directory.appendingPathComponent("a.wav")
            try WAVFile.write(original, sampleRate: 48000, channels: [[1]])
            let root = directory.appendingPathComponent("assets", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let existing = root.appendingPathComponent("existing.wav")
            try WAVFile.write(existing, sampleRate: 48000, channels: [[0.5]])
            var configuration = FieldConfiguration()
            configuration.headphone.fir = ["left": IRAsset(path: original.path), "right": IRAsset(path: directory.appendingPathComponent("z-missing.wav").path)]
            #expect(throws: Error.self) { try ManagedAssets.copy(configuration, to: root) }
            #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["existing.wav"])
            #expect(try WAVFile.read(existing).channels == [[0.5]])
            configuration.headphone.fir = ["left": IRAsset(path: "relative.wav")]
            #expect(throws: Error.self) { try ManagedAssets.copy(configuration, to: root) }
        }
    }

    @Test func managedAssetSymlinkCannotPretendExternalAssetIsManaged() throws {
        try temporaryDirectory { directory in
            let original = directory.appendingPathComponent("external.wav")
            try WAVFile.write(original, sampleRate: 48000, channels: [[1]])
            let root = directory.appendingPathComponent("assets", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let alias = root.appendingPathComponent("shortcut.wav")
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: original)
            var configuration = FieldConfiguration()
            configuration.externalization.paths = ["LL": IRAsset(path: alias.path)]
            let result = try ManagedAssets.copy(configuration, to: root)
            #expect(result.directory != nil)
            #expect(result.configuration.externalization.paths?["LL"]?.path != original.path)
            try FileManager.default.removeItem(at: original)
            let path = try #require(result.configuration.externalization.paths?["LL"]?.path)
            #expect(try WAVFile.read(URL(fileURLWithPath: path)).channels == [[1]])
        }
    }
}

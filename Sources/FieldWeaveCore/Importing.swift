import Foundation

public struct IRFileInfo: Equatable, Sendable {
    public let url: URL
    public let channelCount: Int
    public let sampleRate: Int
    public let frameCount: Int

    public init(url: URL, channelCount: Int, sampleRate: Int, frameCount: Int) {
        self.url = url
        self.channelCount = channelCount
        self.sampleRate = sampleRate
        self.frameCount = frameCount
    }
}

public enum IRImport {
    public static let maximumFiles = 128
    public static let maximumFrames = 262143

    /// Enumerates only the selected directories' immediate, nonhidden WAV children.
    public static func expand(_ urls: [URL]) throws -> [URL] {
        let fm = FileManager.default
        var found: [String: URL] = [:]
        func append(_ url: URL) throws {
            guard url.pathExtension.lowercased() == "wav" else { return }
            let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
            let values = try resolved.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { return }
            found[resolved.path] = resolved
            guard found.count <= maximumFiles else {
                throw FieldError.invalid("Select at most \(maximumFiles) WAV files")
            }
        }
        for url in urls {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                let children = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
                for child in children { try append(child) }
            } else {
                try append(url)
            }
        }
        return found.values.sorted { $0.path < $1.path }
    }

    /// Synchronous so callers can perform the complete inspection away from the UI actor.
    public static func inspect(_ url: URL, sampleRate: Int) throws -> IRFileInfo {
        guard url.pathExtension.lowercased() == "wav" else {
            throw FieldError.invalid("Native IR import currently supports WAV only")
        }
        guard (8000...192000).contains(sampleRate) else {
            throw FieldError.invalid("Unsupported configuration sample rate")
        }
        try preflight(url, sampleRate: sampleRate)
        let wav = try WAVFile.read(url)
        guard wav.sampleRate == sampleRate else { throw rateMismatch(wav.sampleRate, sampleRate) }
        guard let frames = wav.channels.first?.count, frames <= maximumFrames else {
            throw FieldError.invalid("IR exceeds \(maximumFrames)-tap import limit")
        }
        return IRFileInfo(url: url.standardizedFileURL.resolvingSymlinksInPath(), channelCount: wav.channels.count,
                          sampleRate: wav.sampleRate, frameCount: frames)
    }

    /// Filenames propose routing only. Ambiguous or duplicate candidates remain unassigned.
    public static func suggestions(_ files: [IRFileInfo], headphone: Bool) -> [String: IRAsset] {
        let files = Dictionary(grouping: files, by: { $0.url.standardizedFileURL.resolvingSymlinksInPath().path })
            .compactMap { $0.value.first }.sorted { $0.url.path < $1.url.path }
        if headphone, files.count == 1, let file = files.first, file.channelCount == 2 {
            return ["left": IRAsset(path: file.url.path, channel: 0), "right": IRAsset(path: file.url.path, channel: 1)]
        }
        var candidates: [String: [IRAsset]] = [:]
        func propose(_ key: String, _ file: IRFileInfo, _ channel: Int) {
            guard channel < file.channelCount else { return }
            candidates[key, default: []].append(IRAsset(path: file.url.path, channel: channel))
        }
        for file in files {
            let tokens = filenameTokens(file.url)
            guard file.channelCount > 0 else { continue }
            if headphone {
                guard file.channelCount <= 2 else { continue }
                guard tokens.isDisjoint(with: ["source", "ll", "lr", "rl", "rr"]) else { continue }
                let left = !tokens.isDisjoint(with: ["left", "l"])
                let right = !tokens.isDisjoint(with: ["right", "r"])
                guard left != right else { continue }
                if left { propose("left", file, 0) }
                if right { propose("right", file, file.channelCount == 2 ? 1 : 0) }
            } else {
                let routes = tokens.intersection(["ll", "lr", "rl", "rr"])
                let sources = tokens.intersection(["ls", "rs"])
                let ears = tokens.intersection(["le", "re"])
                if !sources.isEmpty || !ears.isEmpty {
                    guard sources.count == 1, ears.count == 1, file.channelCount == 1,
                          tokens.isDisjoint(with: ["left", "right", "l", "r", "source"]) else { continue }
                    let route = (sources.contains("ls") ? "L" : "R") + (ears.contains("le") ? "L" : "R")
                    guard routes.isEmpty || routes == [route.lowercased()] else { continue }
                    propose(route, file, 0)
                } else if routes.count == 1, file.channelCount == 1,
                   tokens.isDisjoint(with: ["left", "right", "l", "r", "source"]) {
                    propose(routes.first!.uppercased(), file, 0)
                } else if routes.isEmpty, file.channelCount == 2, tokens.contains("source") {
                    let left = tokens.contains("left"), right = tokens.contains("right")
                    guard left != right, tokens.isDisjoint(with: ["l", "r"]) else { continue }
                    if left { propose("LL", file, 0); propose("LR", file, 1) }
                    if right { propose("RL", file, 0); propose("RR", file, 1) }
                }
            }
        }
        return candidates.compactMapValues { $0.count == 1 ? $0[0] : nil }
    }

    private static func filenameTokens(_ url: URL) -> Set<String> {
        Set(url.deletingPathExtension().lastPathComponent.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
    }

    private static func rateMismatch(_ actual: Int, _ expected: Int) -> FieldError {
        .invalid("IR sample-rate mismatch: \(actual) Hz versus \(expected) Hz; explicitly convert the WAV before import")
    }

    // Reject an oversized impulse or wrong rate before WAVFile allocates sample arrays.
    // WAVFile remains the authority for decoding and validating the actual WAV contents.
    private static func preflight(_ url: URL, sampleRate: Int) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber, size.int64Value <= 268_435_456 else {
            throw FieldError.invalid("WAV exceeds 256 MiB import limit")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        func bytes(_ offset: UInt64, _ count: Int) throws -> [UInt8] {
            try handle.seek(toOffset: offset)
            guard let data = try handle.read(upToCount: count), data.count == count else {
                throw FieldError.invalid("Invalid WAV: truncated chunk")
            }
            return Array(data)
        }
        func integer(_ b: [UInt8], _ p: Int, _ count: Int) -> Int {
            (0..<count).reduce(0) { $0 | (Int(b[p + $1]) << ($1 * 8)) }
        }
        let header = try bytes(0, 12)
        guard String(bytes: header[0..<4], encoding: .ascii) == "RIFF",
              String(bytes: header[8..<12], encoding: .ascii) == "WAVE" else {
            throw FieldError.invalid("Invalid WAV: RIFF header")
        }
        let end = UInt64(integer(header, 4, 4)) + 8
        guard end <= size.uint64Value else { throw FieldError.invalid("Invalid WAV: RIFF header") }
        var offset: UInt64 = 12, blockAlign: Int?, dataLength: Int?
        while offset + 8 <= end {
            let chunk = try bytes(offset, 8), length = integer(chunk, 4, 4), start = offset + 8
            guard UInt64(length) <= end - start else { throw FieldError.invalid("Invalid WAV: truncated chunk") }
            let tag = String(bytes: chunk[0..<4], encoding: .ascii)
            if tag == "fmt ", length >= 16 {
                let format = try bytes(start, 16), rate = integer(format, 4, 4)
                guard rate == sampleRate else { throw rateMismatch(rate, sampleRate) }
                blockAlign = integer(format, 12, 2)
            } else if tag == "data" {
                dataLength = length
            }
            offset = start + UInt64(length) + UInt64(length % 2)
        }
        if let align = blockAlign, align > 0, let count = dataLength, count / align > maximumFrames {
            throw FieldError.invalid("IR exceeds \(maximumFrames)-tap import limit")
        }
    }
}

public enum PEQImport {
    public static func read(_ url: URL, sampleRate: Int) throws -> [PEQBand] {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber, size.int64Value <= 1_048_576 else {
            throw FieldError.invalid("PEQ JSON exceeds 1 MiB import limit")
        }
        return try decode(Data(contentsOf: url), sampleRate: sampleRate)
    }

    public static func decode(_ data: Data, sampleRate: Int) throws -> [PEQBand] {
        guard (8000...192000).contains(sampleRate) else { throw FieldError.invalid("Unsupported configuration sample rate") }
        guard let bands = try JSONSerialization.jsonObject(with: data) as? [Any], bands.count <= 64 else {
            throw FieldError.invalid("PEQ JSON must be an array of at most 64 bands")
        }
        let keys: Set<String> = ["frequency_hz", "q", "gain_db"]
        for (index, band) in bands.enumerated() {
            guard let object = band as? [String: Any], Set(object.keys) == keys,
                  !object.values.contains(where: { $0 is NSNull }) else {
                throw FieldError.invalid("PEQ band \(index + 1) requires exactly frequency_hz, q, gain_db without null values")
            }
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let result = try decoder.decode([PEQBand].self, from: data)
        for (index, band) in result.enumerated() {
            guard band.frequencyHz.isFinite, (1...(Double(sampleRate) / 2 - 1)).contains(band.frequencyHz),
                  band.q.isFinite, (0.1...20).contains(band.q),
                  band.gainDb.isFinite, (-24...24).contains(band.gainDb) else {
                throw FieldError.invalid("PEQ band \(index + 1) has frequency, Q, or gain outside the supported range")
            }
        }
        return result
    }
}

public struct ManagedAssetCopy: Sendable {
    public let configuration: FieldConfiguration
    /// Newly created transaction directory, or nil when every asset was already managed.
    public let directory: URL?
}

public enum ManagedAssets {
    /// Copies unique external IR files atomically as a group, reusing existing managed files.
    /// Asset paths must be absolute; configuration-relative paths are resolved by the caller.
    public static func copy(_ configuration: FieldConfiguration, to assetRoot: URL) throws -> ManagedAssetCopy {
        let fm = FileManager.default
        let root = assetRoot.standardizedFileURL.resolvingSymlinksInPath()
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        var paths = Set<String>()
        for assets in [configuration.headphone.fir, configuration.externalization.paths] {
            for asset in assets?.values ?? Dictionary<String, IRAsset>().values {
                guard asset.path.hasPrefix("/") else { throw FieldError.invalid("Resolve IR asset paths before saving imported files") }
                paths.insert(asset.path)
            }
        }
        var replacements: [String: String] = [:], copied: [String: String] = [:]
        var directory: URL?
        do {
            for path in paths.sorted() {
                let source = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
                let values = try source.resourceValues(forKeys: [.isRegularFileKey])
                guard values.isRegularFile == true, source.pathExtension.lowercased() == "wav" else {
                    throw FieldError.invalid("IR asset must be a regular WAV file: \(source.lastPathComponent)")
                }
                if source.path.hasPrefix(rootPrefix) { replacements[path] = source.path; continue }
                if let existing = copied[source.path] { replacements[path] = existing; continue }
                if directory == nil {
                    let candidate = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
                    try fm.createDirectory(at: candidate, withIntermediateDirectories: true)
                    directory = candidate
                }
                let name = String(format: "%03d-%@", copied.count + 1, source.lastPathComponent)
                let destination = directory!.appendingPathComponent(name)
                try fm.copyItem(at: source, to: destination)
                copied[source.path] = destination.path
                replacements[path] = destination.path
            }
            var result = configuration
            result.headphone.fir = configuration.headphone.fir?.mapValues { IRAsset(path: replacements[$0.path]!, channel: $0.channel) }
            result.externalization.paths = configuration.externalization.paths?.mapValues { IRAsset(path: replacements[$0.path]!, channel: $0.channel) }
            return ManagedAssetCopy(configuration: result, directory: directory)
        } catch {
            if let directory { try? fm.removeItem(at: directory) }
            throw error
        }
    }
}

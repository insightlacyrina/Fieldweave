import Foundation

public struct FieldConfiguration: Codable, Equatable, Sendable {
    public var version = 1
    public var sampleRate = 48000
    public var design = DesignSettings()
    public var headphone = HeadphoneSettings()
    public var width = CurveSpec(points: [[20,1.2],[250,1.2],[1000,1.1],[6000,1.3],[20000,1.3]])
    public var centerImaging: CenterSettings? = CenterSettings()
    public var externalization = ExternalizationSettings()
    public var crossfeed = CrossfeedSettings()
    public var safety = SafetySettings()
    public init() {}
    public static let encoder: JSONEncoder = { let e=JSONEncoder(); e.keyEncodingStrategy = .convertToSnakeCase; e.outputFormatting=[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]; return e }()
    public static let decoder: JSONDecoder = { let d=JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase; return d }()
    public func jsonData() throws -> Data { try Self.encoder.encode(self) }
    public static func read(from url: URL) throws -> Self { try decode(Data(contentsOf:url)) }
    public static func decode(_ data:Data) throws -> Self {
        let json=try JSONSerialization.jsonObject(with:data)
        func object(_ value:Any,allowed:Set<String>,at path:String) throws -> [String:Any] {
            guard let map=value as? [String:Any] else {throw FieldError.invalid("Expected object at \(path)")}
            let extra=Set(map.keys).subtracting(allowed)
            guard extra.isEmpty else {throw FieldError.invalid("Unsupported keys at \(path): \(extra.sorted().joined(separator: ", "))")}
            guard !map.values.contains(where:{$0 is NSNull}) else {throw FieldError.invalid("Null parameters at \(path); omit inactive values instead")}
            return map
        }
        let root=try object(json,allowed:["version","sample_rate","design","headphone","width","center_imaging","externalization","crossfeed","safety"],at:"configuration")
        let schemas:[String:Set<String>]=[
            "design":["width_taps","eq_taps","max_matrix_taps","resample_policy","tail_energy_tolerance"],
            "headphone":["mode","peq","fir","provenance"], "width":["interpolation","points"],
            "center_imaging":["enabled","pan","gain_db","elevation_degrees","height_profile"],
            "externalization":["mode","paths","kind","normalization","coordinates","provenance"],
            "crossfeed":["enabled","curve","delay_ms","allow_with_externalization"],
            "safety":["preamp_db","auto_headroom","ceiling_dbfs"]]
        for (key,schema) in schemas {
            if let value=root[key] {
                let map=try object(value,allowed:schema,at:key)
                if let bands=map["peq"] as? [Any] {for band in bands {_ = try object(band,allowed:["frequency_hz","q","gain_db"],at:"headphone.peq")}}
                if let curve=map["curve"] {_ = try object(curve,allowed:["interpolation","points"],at:"crossfeed.curve")}
                if let coordinates=map["coordinates"] {_ = try object(coordinates,allowed:["convention","left_source","right_source"],at:"externalization.coordinates")}
                for name in ["fir","paths"] {
                    if let assets=map[name] as? [String:Any] {for (name,asset) in assets {_ = try object(asset,allowed:["path","channel"],at:"asset.\(name)")}}
                }
            }
        }
        return try decoder.decode(Self.self,from:data)
    }
}
public struct DesignSettings: Codable, Equatable, Sendable {
    public var widthTaps = 2049
    public var eqTaps = 4096
    public var maxMatrixTaps = 65536
    public var resamplePolicy = "reject"
    public var tailEnergyTolerance = 0.000001
    public init() {}
}
public struct CurveSpec: Codable, Equatable, Sendable {
    public var interpolation = "pchip_log_hz"
    public var points: [[Double]]
    public init(points:[[Double]]) { self.points=points }
}
public struct CenterSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var pan: Double?
    public var gainDb: Double?
    /// Missing in older configurations: nil is the unchanged, zero-height path.
    public var elevationDegrees: Double?
    public var heightProfile: String?
    public init(enabled:Bool=true,pan:Double=0,gainDb:Double=0,elevationDegrees:Double?=nil,heightProfile:String?=nil) {
        self.enabled=enabled; self.pan=enabled ? pan:nil; self.gainDb=enabled ? gainDb:nil
        self.elevationDegrees=enabled ? elevationDegrees:nil; self.heightProfile=enabled ? heightProfile:nil
    }
}
public struct HeadphoneSettings: Codable, Equatable, Sendable {
    public var mode = "bypass"
    public var peq: [PEQBand]?
    public var fir: [String:IRAsset]?
    public var provenance: String?
    public init() {}
}
public struct PEQBand: Codable, Equatable, Sendable {
    public var frequencyHz: Double
    public var q: Double
    public var gainDb: Double
    public init(frequencyHz:Double,q:Double,gainDb:Double) { self.frequencyHz=frequencyHz; self.q=q; self.gainDb=gainDb }
}
public struct IRAsset: Codable, Equatable, Sendable {
    public var path: String
    public var channel: Int
    public init(path:String,channel:Int=0) { self.path=path; self.channel=channel }
}
public struct ExternalizationSettings: Codable, Equatable, Sendable {
    public var mode = "bypass"
    public var paths: [String:IRAsset]?
    public var kind: String?
    public var normalization: String?
    public var coordinates: SourceCoordinates?
    public var provenance: String?
    public init() {}
}
public struct SourceCoordinates: Codable, Equatable, Sendable {
    public var convention = "SOFA spherical: azimuth positive left, elevation positive up, distance metres"
    public var leftSource: [Double] = [30,0,1]
    public var rightSource: [Double] = [-30,0,1]
    public init() {}
}
public struct CrossfeedSettings: Codable, Equatable, Sendable {
    public var enabled = false
    public var curve: CurveSpec?
    public var delayMs: Double?
    public var allowWithExternalization: Bool?
    public init() {}
    public init(amount:Double,delayMs:Double,allowWithExternalization:Bool=false) {
        enabled=true; curve=CurveSpec(points:[[20,amount],[700,amount*0.75],[4000,amount*0.15],[20000,0]])
        self.delayMs=delayMs; self.allowWithExternalization=allowWithExternalization
    }
}
public struct SafetySettings: Codable, Equatable, Sendable {
    public var preampDb = -3.0
    public var autoHeadroom = true
    public var ceilingDbfs = -1.0
    public init() {}
}

public struct CompilationReport: Codable, Sendable {
    public var sampleRate: Int
    public var matrixTaps: Int
    public var designCommonDelayMs: Double
    public var autoHeadroomGainDb: Double
    public var boundedInputPeakBound: Double
    public var widthMaxMagnitudeError: Double
    public var warnings: [String]
    public var midLeftGain: Double
    public var midRightGain: Double
    public var centerElevationDegrees: Double
    public var centerElevationStrategy: String
    public var centerElevationProfile: String?
    public init(sampleRate:Int,matrixTaps:Int,designCommonDelayMs:Double,autoHeadroomGainDb:Double,boundedInputPeakBound:Double,widthMaxMagnitudeError:Double,warnings:[String]=[],midLeftGain:Double=1,midRightGain:Double=1,centerElevationDegrees:Double=0,centerElevationStrategy:String="bypass",centerElevationProfile:String?=nil) {
        self.sampleRate=sampleRate; self.matrixTaps=matrixTaps; self.designCommonDelayMs=designCommonDelayMs; self.autoHeadroomGainDb=autoHeadroomGainDb; self.boundedInputPeakBound=boundedInputPeakBound; self.widthMaxMagnitudeError=widthMaxMagnitudeError; self.warnings=warnings; self.midLeftGain=midLeftGain; self.midRightGain=midRightGain
        self.centerElevationDegrees=centerElevationDegrees;self.centerElevationStrategy=centerElevationStrategy;self.centerElevationProfile=centerElevationProfile
    }
}
public struct CompiledField: Sendable {
    public var matrix: [[[Double]]] // [output ear][input source][tap]
    public var report: CompilationReport
    public var responseFrequencies: [Double]
    public var widthTarget: [Double]
    public var widthActual: [Double]
    public init(matrix:[[[Double]]],report:CompilationReport,responseFrequencies:[Double],widthTarget:[Double],widthActual:[Double]) {
        self.matrix=matrix; self.report=report; self.responseFrequencies=responseFrequencies; self.widthTarget=widthTarget; self.widthActual=widthActual
    }
}
public struct RenderReport: Codable, Sendable {
    public var sampleRate: Int
    public var frames: Int
    public var peak: Double
    public init(sampleRate:Int,frames:Int,peak:Double) { self.sampleRate=sampleRate; self.frames=frames; self.peak=peak }
}
public enum FieldError: LocalizedError {
    case invalid(String)
    public var errorDescription:String? { switch self { case .invalid(let message):return message } }
}

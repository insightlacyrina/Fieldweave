import Foundation

/// Measured donor elevation data. These are height cues, not a listener-specific
/// localization guarantee. The resource manifest fixes donor and measurement provenance.
public enum CenterElevation {
    public static let supportedProfiles = (1...7).map { String(format: "c%02d", $0) }
    public static let supportedDegrees = -45.0...45.0

    struct Result {
        var matrix: Matrix
        var strategy: String
        var profile: String
        var warning: String?
    }

    private struct Manifest: Decodable {
        var version: Int
        var sampleRate: Int
        var profiles: [Profile]
    }
    private struct Profile: Decodable {
        var id: String
        var donor: String
        var elevations: [Elevation]
    }
    private struct Elevation: Decodable {
        var degrees: Double
        var paths: [String:String]
    }
    private struct Bank {
        var donor: String
        var matrices: [(degrees:Double, matrix:Matrix)]
    }
    private static let cacheLock = NSLock()
    private static var cache: [String:Bank] = [:]

    /// The original externalization matrix is supplied before its optional global
    /// normalization, so a different donor or an edited/custom IR never matches by name.
    static func apply(base:Matrix,externalization:Matrix,rawExternalization:Matrix?,
                      externalizationScale:Double,left:Double,right:Double,degrees:Double,
                      profile requested:String?,sampleRate:Int) throws -> Result {
        guard degrees.isFinite,supportedDegrees.contains(degrees),degrees != 0 else {
            throw FieldError.invalid("Active center elevation must be nonzero in -45...45 degrees")
        }
        var matched:String?
        if let original=rawExternalization {
            let candidates=(requested.map {[$0]} ?? [])+supportedProfiles.filter{$0 != requested}
            for id in candidates where try matches(original,referenceMatrix(profile:id,sampleRate:sampleRate)) {
                matched=id;break
            }
        }
        let profile=matched ?? requested ?? "c01"
        let target=try matrix(profile:profile,degrees:degrees,sampleRate:sampleRate)
        let mid:Matrix=[[[left/2],[left/2]],[[right/2],[right/2]]]
        let side:Matrix=[[[0.5],[-0.5]],[[-0.5],[0.5]]]
        let sidePath=multiplyMatrix(externalization,side)
        let middlePath:Matrix
        let strategy:String
        var warning:String?
        if matched != nil {
            // Replace the center's acoustic renderer. It must not pass through the
            // horizontal HRTF again; Side still uses that original matrix once.
            let scaled=target.map {$0.map {$0.map {$0*externalizationScale}}}
            middlePath=multiplyMatrix(scaled,mid)
            strategy="measured_mid_replacement"
        } else {
            // A dry or unknown renderer has no matching measured horizontal basis.
            // Apply only its donor's relative elevation spectra, with a regularized,
            // bounded minimum-phase ratio. A complete extra HRTF is never cascaded.
            let reference=try referenceMatrix(profile:profile,sampleRate:sampleRate)
            let filters=try (0..<2).map { ear in
                try minimumPhaseRatio(target:midResponse(target[ear],left:left,right:right),
                                      reference:midResponse(reference[ear],left:left,right:right))
            }
            middlePath=multiplyMatrix(diagonalMatrix(filters[0],filters[1]),multiplyMatrix(externalization,mid))
            strategy="relative_minimum_phase_cues"
            warning="Center height uses measured \(profile) relative elevation spectra on the current renderer; absolute elevation and listener match are not verified."
        }
        return Result(matrix:multiplyMatrix(add(middlePath,sidePath),base),strategy:strategy,profile:profile,warning:warning)
    }

    static func referenceMatrix(profile:String,sampleRate:Int) throws -> Matrix {
        try matrix(profile:profile,degrees:0,sampleRate:sampleRate)
    }

    static func matrix(profile:String,degrees:Double,sampleRate:Int) throws -> Matrix {
        guard supportedProfiles.contains(profile),sampleRate>=8000,sampleRate<=192000,degrees.isFinite else {
            throw FieldError.invalid("Unsupported center height profile or sample rate")
        }
        let bank=try load(profile)
        guard let first=bank.matrices.first,let last=bank.matrices.last,
              degrees>=first.degrees,degrees<=last.degrees else {
            throw FieldError.invalid("The measured elevation bank does not cover the requested height")
        }
        let original:Matrix
        if let exact=bank.matrices.first(where:{$0.degrees==degrees}) { original=exact.matrix }
        else {
            guard let upper=bank.matrices.firstIndex(where:{$0.degrees>degrees}),upper>0 else {
                throw FieldError.invalid("No measured elevation interval brackets the requested height")
            }
            let a=bank.matrices[upper-1],b=bank.matrices[upper]
            let amount=(degrees-a.degrees)/(b.degrees-a.degrees)
            let n=max(a.matrix[0][0].count,b.matrix[0][0].count)
            original=(0..<2).map { ear in (0..<2).map { source in
                (0..<n).map { tap in
                    let av=tap<a.matrix[ear][source].count ? a.matrix[ear][source][tap]:0
                    let bv=tap<b.matrix[ear][source].count ? b.matrix[ear][source][tap]:0
                    return av+(bv-av)*amount
                }
            } }
        }
        // Only the bundled, known 48 kHz measurement bank is converted. External IR
        // sample-rate rejection remains unchanged. The 1/ratio factor preserves FIR
        // transfer gain rather than treating an impulse response as an audio clip.
        if sampleRate==48000 {return original}
        return original.map {$0.map {resample($0,from:48000,to:sampleRate)}}
    }

    private static func load(_ id:String) throws -> Bank {
        cacheLock.lock()
        let saved=cache[id]
        cacheLock.unlock()
        if let saved {return saved}
        guard let url=Bundle.module.url(forResource:"manifest",withExtension:"json",subdirectory:"Resources/CenterElevation")
            ?? Bundle.module.url(forResource:"manifest",withExtension:"json",subdirectory:"CenterElevation") else {
            throw FieldError.invalid("The bundled measured center-height bank is unavailable")
        }
        let decoder=JSONDecoder();decoder.keyDecodingStrategy = .convertFromSnakeCase
        let manifest=try decoder.decode(Manifest.self,from:Data(contentsOf:url))
        guard manifest.version==1,manifest.sampleRate==48000,
              Set(manifest.profiles.map(\.id)).count==manifest.profiles.count,
              let profile=manifest.profiles.first(where:{$0.id==id}),!profile.donor.isEmpty,
              profile.elevations.count>=3,profile.elevations.contains(where:{$0.degrees==0}) else {
            throw FieldError.invalid("Invalid measured center-height bank manifest")
        }
        let root=url.deletingLastPathComponent().standardizedFileURL
        var previous = -Double.infinity
        var matrices:[(degrees:Double,matrix:Matrix)]=[]
        for node in profile.elevations {
            guard node.degrees.isFinite,node.degrees>previous,(-90...90).contains(node.degrees),
                  Set(node.paths.keys)==Set(["LL","LR","RL","RR"]) else {
                throw FieldError.invalid("Invalid measured elevation coordinates or four-path routing")
            }
            previous=node.degrees
            var result:Matrix=Array(repeating:Array(repeating:[],count:2),count:2)
            for (key,row,col) in [("LL",0,0),("LR",1,0),("RL",0,1),("RR",1,1)] {
                let path=node.paths[key]!
                let asset=root.appendingPathComponent(path).standardizedFileURL
                guard !path.hasPrefix("/"),asset.path.hasPrefix(root.path+"/"),asset.pathExtension.lowercased()=="wav" else {
                    throw FieldError.invalid("Height bank assets must stay inside their bundled directory")
                }
                let wav=try WAVFile.read(asset)
                guard wav.sampleRate==48000,wav.channels.count==1,
                      let channel=wav.channels.first,!channel.isEmpty,channel.count<=65536 else {
                    throw FieldError.invalid("Invalid bundled measured height impulse response")
                }
                result[row][col]=channel
            }
            let length=result.flatMap{$0}.map(\.count).max()!
            result=result.map {$0.map {$0+Array(repeating:0,count:length-$0.count)}}
            matrices.append((node.degrees,result))
        }
        let bank=Bank(donor:profile.donor,matrices:matrices)
        cacheLock.lock();cache[id]=bank;cacheLock.unlock()
        return bank
    }

    private static func matches(_ a:Matrix,_ b:Matrix) -> Bool {
        for ear in 0..<2 {for source in 0..<2 {
            let av=a[ear][source],bv=b[ear][source]
            let scale=max(bv.map{abs($0)}.max() ?? 0,1)
            for tap in 0..<max(av.count,bv.count) {
                let x=tap<av.count ? av[tap]:0,y=tap<bv.count ? bv[tap]:0
                if abs(x-y)>scale*1e-8 {return false}
            }
        }}
        return true
    }

    private static func midResponse(_ row:[[Double]],left:Double,right:Double) -> [Double] {
        let n=max(row[0].count,row[1].count)
        return (0..<n).map {tap in
            left*(tap<row[0].count ? row[0][tap]:0)+right*(tap<row[1].count ? row[1][tap]:0)
        }
    }

    /// Real-cepstrum minimum-phase reconstruction of a regularized measured
    /// amplitude ratio. At zero the caller strictly bypasses this entire branch.
    static func minimumPhaseRatio(target:[Double],reference:[Double]) throws -> [Double] {
        let n=max(16384,NativeFFT.size(max(target.count,reference.count)*8))
        let a=NativeFFT.magnitude(target,n:n),b=NativeFFT.magnitude(reference,n:n)
        let floor=max((b.max() ?? 0)*0.01,1e-10),regularization=floor*floor
        let low=pow(10,-18.0/20),high=pow(10,12.0/20)
        var real=Array(repeating:0.0,count:n),imaginary=real
        for i in 0...n/2 {
            let ratio=min(high,max(low,sqrt((a[i]*a[i]+regularization)/(b[i]*b[i]+regularization))))
            real[i]=log(ratio)
            if i>0 && i<n/2 {real[n-i]=real[i]}
        }
        let wantedDC=exp(real[0])
        NativeFFT.transform(&real,&imaginary,inverse:true)
        for i in 1..<n/2 {real[i]*=2}
        for i in n/2+1..<n {real[i]=0}
        imaginary=Array(repeating:0,count:n)
        NativeFFT.transform(&real,&imaginary)
        for i in 0..<n {
            let amplitude=exp(real[i]),phase=imaginary[i]
            real[i]=amplitude*cos(phase);imaginary[i]=amplitude*sin(phase)
        }
        NativeFFT.transform(&real,&imaginary,inverse:true)
        let total=real.reduce(0){$0+$1*$1}
        let limit=min(4096,n/2)
        let tail=real.dropFirst(limit).reduce(0){$0+$1*$1}/max(total,1e-300)
        guard tail<0.001 else {throw FieldError.invalid("Measured relative height filter exceeds its causal FIR tail tolerance")}
        var taps=Array(real.prefix(limit))
        let dc=taps.reduce(0,+)
        if abs(dc)>1e-8 {let correction=wantedDC/dc;taps=taps.map{$0*correction}}
        guard taps.allSatisfy(\.isFinite) else {throw FieldError.invalid("Center-height design produced nonfinite coefficients")}
        return taps
    }

    private static func add(_ a:Matrix,_ b:Matrix) -> Matrix {
        var result:Matrix=Array(repeating:Array(repeating:[],count:2),count:2)
        for ear in 0..<2 {for source in 0..<2 {
            let av=a[ear][source],bv=b[ear][source],count=max(av.count,bv.count)
            var taps=Array(repeating:0.0,count:count)
            for tap in 0..<count {
                let left=tap<av.count ? av[tap]:0
                let right=tap<bv.count ? bv[tap]:0
                taps[tap]=left+right
            }
            result[ear][source]=taps
        }}
        return result
    }

    private static func resample(_ input:[Double],from:Int,to:Int) -> [Double] {
        let ratio=Double(to)/Double(from),cutoff=min(1,ratio)*0.94
        let radius=32.0/cutoff
        let count=Int(ceil(Double(input.count-1)*ratio))+1
        return (0..<count).map { index in
            let time=Double(index)/ratio
            let first=max(0,Int(ceil(time-radius))),last=min(input.count-1,Int(floor(time+radius)))
            guard first<=last else{return 0}
            var value=0.0
            for tap in first...last {
                let distance=time-Double(tap),x=distance*cutoff
                let sinc=abs(x)<1e-12 ? 1:sin(.pi*x)/(.pi*x)
                let window=0.5+0.5*cos(.pi*distance/radius)
                value+=input[tap]*cutoff*sinc*window/ratio
            }
            return value
        }
    }
}

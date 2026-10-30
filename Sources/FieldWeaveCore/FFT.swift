import Foundation

enum NativeFFT {
    static func size(_ count:Int) -> Int { var n=1; while n<count { n <<= 1 }; return n }
    static func transform(_ real:inout [Double],_ imag:inout [Double],inverse:Bool=false) {
        let n=real.count; guard n>1 else{return}; var j=0
        for i in 1..<n { var bit=n>>1; while j & bit != 0 {j ^= bit;bit >>= 1}; j ^= bit; if i<j {real.swapAt(i,j);imag.swapAt(i,j)} }
        var length=2
        while length<=n { let angle=(inverse ? 2.0 : -2.0)*Double.pi/Double(length), wr0=cos(angle),wi0=sin(angle)
            for start in stride(from:0,to:n,by:length) {var wr=1.0,wi=0.0
                for k in 0..<(length/2) {let a=start+k,b=a+length/2;let vr=real[b]*wr-imag[b]*wi,vi=real[b]*wi+imag[b]*wr;let ur=real[a],ui=imag[a];real[a]=ur+vr;imag[a]=ui+vi;real[b]=ur-vr;imag[b]=ui-vi;let next=wr*wr0-wi*wi0;wi=wr*wi0+wi*wr0;wr=next}
            };length <<= 1
        }
        if inverse {for i in 0..<n {real[i] /= Double(n);imag[i] /= Double(n)}}
    }
    static func convolve(_ a:[Double],_ b:[Double])->[Double] {
        if a.allSatisfy({$0==0}) || b.allSatisfy({$0==0}) {return Array(repeating:0,count:a.count+b.count-1)}
        if a.count==1{return b.map{$0*a[0]}};if b.count==1{return a.map{$0*b[0]}}
        let count=a.count+b.count-1,n=size(count); var ar=a+Array(repeating:0,count:n-a.count),ai=Array(repeating:0.0,count:n),br=b+Array(repeating:0,count:n-b.count),bi=ai
        transform(&ar,&ai);transform(&br,&bi)
        for i in 0..<n {let r=ar[i]*br[i]-ai[i]*bi[i];ai[i]=ar[i]*bi[i]+ai[i]*br[i];ar[i]=r};transform(&ar,&ai,inverse:true);return Array(ar.prefix(count))
    }
    static func blockConvolve(_ input:[Double],_ kernel:[Double])->[Double] {
        if input.count < 131072 {return convolve(input,kernel)}
        if kernel.allSatisfy({$0==0}) {return Array(repeating:0,count:input.count+kernel.count-1)}
        if kernel.count==1{return input.map{$0*kernel[0]}}
        let n=size(max(8192,kernel.count*2)),block=n-kernel.count+1
        var kr=kernel+Array(repeating:0,count:n-kernel.count),ki=Array(repeating:0.0,count:n)
        transform(&kr,&ki);var output=Array(repeating:0.0,count:input.count+kernel.count-1)
        for start in stride(from:0,to:input.count,by:block) {
            let count=min(block,input.count-start);var r=Array(repeating:0.0,count:n),i=r
            r.replaceSubrange(0..<count,with:input[start..<start+count]);transform(&r,&i)
            for k in 0..<n {let value=r[k]*kr[k]-i[k]*ki[k];i[k]=r[k]*ki[k]+i[k]*kr[k];r[k]=value}
            transform(&r,&i,inverse:true)
            for k in 0..<count+kernel.count-1 {output[start+k]+=r[k]}
        };return output
    }
    static func magnitude(_ a:[Double],n:Int)->[Double] {var r=a+Array(repeating:0,count:n-a.count),i=Array(repeating:0.0,count:n);transform(&r,&i);return (0...n/2).map{hypot(r[$0],i[$0])}}
}

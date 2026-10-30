import Foundation

public enum CurveDSP {
    public static func evaluate(_ spec:CurveSpec,frequencies:[Double])->[Double] {
        guard spec.points.count>=2,spec.points.allSatisfy({$0.count==2 && $0[0]>0 && $0.allSatisfy(\.isFinite)}) else{return frequencies.map{_ in 0}}
        let x=spec.points.map{log($0[0])},y=spec.points.map{$0[1]},n=x.count
        let h=(0..<n-1).map{x[$0+1]-x[$0]};guard h.allSatisfy({$0>0}) else{return frequencies.map{_ in 0}}
        let d=(0..<n-1).map{(y[$0+1]-y[$0])/h[$0]};var m=Array(repeating:0.0,count:n)
        if n==2 {m=[d[0],d[0]]} else {
            for k in 1..<n-1 {if d[k-1]*d[k]>0 {let w1=2*h[k]+h[k-1],w2=h[k]+2*h[k-1];m[k]=(w1+w2)/(w1/d[k-1]+w2/d[k])}}
            func edge(_ h0:Double,_ h1:Double,_ d0:Double,_ d1:Double)->Double {let v=((2*h0+h1)*d0-h0*d1)/(h0+h1);if v*d0<=0{return 0};if d0*d1<0 && abs(v)>3*abs(d0){return 3*d0};return v}
            m[0]=edge(h[0],h[1],d[0],d[1]);m[n-1]=edge(h[n-2],h[n-3],d[n-2],d[n-3])
        }
        return frequencies.map {f in let z=min(max(log(max(f,1)),x[0]),x[n-1]);var k=0;while k<n-2 && z>x[k+1]{k+=1};let t=(z-x[k])/h[k],t2=t*t,t3=t2*t;return (2*t3-3*t2+1)*y[k]+(t3-2*t2+t)*h[k]*m[k]+(-2*t3+3*t2)*y[k+1]+(t3-t2)*h[k]*m[k+1]}
    }
    static func design(_ spec:CurveSpec,fs:Int,taps:Int)throws->([Double],Int) {
        let y=spec.points.map{$0[1]};if y.allSatisfy({$0==y[0]}){return ([y[0]],0)}
        guard taps>=3,taps%2==1 else{throw FieldError.invalid("Nonconstant FIR curves require odd tap count >= 3")}
        // scipy firwin2: interpolate dense desired response onto power-of-two FFT mesh,
        // apply linear phase, inverse real FFT, retain taps and symmetric Hann window.
        let mesh=NativeFFT.size(taps)+1,n=2*(mesh-1),dense=max(8193,4*taps+1)
        let freq=(0..<dense).map{Double($0)*Double(fs)/2/Double(dense-1)},desired=evaluate(spec,frequencies:freq)
        var r=Array(repeating:0.0,count:n),im=r
        for k in 0..<mesh {let pos=Double(k)*Double(dense-1)/Double(mesh-1),a=min(Int(pos),dense-2),v=desired[a]+(desired[a+1]-desired[a])*(pos-Double(a));let phase = -Double.pi*Double(taps-1)/2*Double(k)/Double(mesh-1);r[k]=v*cos(phase);im[k]=v*sin(phase)}
        for k in 1..<mesh-1 {r[n-k]=r[k];im[n-k] = -im[k]};im[0]=0;im[mesh-1]=0
        NativeFFT.transform(&r,&im,inverse:true)
        return ((0..<taps).map{r[$0]*(0.5-0.5*cos(2*Double.pi*Double($0)/Double(taps-1)))},(taps-1)/2)
    }
}

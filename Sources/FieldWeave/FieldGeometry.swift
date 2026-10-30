import Foundation
import simd

struct FieldVertex {
    var position: SIMD4<Float>
    var color: SIMD4<Float>
    var meta: SIMD4<Float>
}
struct FieldGeometry {
    var particles: [FieldVertex] = []
    var lines: [FieldVertex] = []
    var surfaces: [FieldVertex] = []

    static func build(seed: UInt32 = 4021) -> FieldGeometry {
        var g = FieldGeometry()
        var state = seed
        let tau = Double.pi * 2
        let low = SIMD3<Double>(1,0.30,0.09), mid = SIMD3<Double>(0.53,1,0.64)
        let high = SIMD3<Double>(0.18,0.47,1), vocal = SIMD3<Double>(0.70,0.43,1), ear = SIMD3<Double>(0.66,0.79,1)
        func random() -> Double { state = 1664525 &* state &+ 1013904223; return Double(state)/4294967296 }
        func normal() -> Double { sqrt(-2 * log(max(random(),1e-8))) * cos(tau * random()) }
        func vertex(_ p: SIMD3<Double>, _ c: SIMD3<Double>, _ alpha: Double = 1, _ size: Double = 1, _ layer: Double = 6, _ flow: Double = 0) -> FieldVertex {
            FieldVertex(position:SIMD4(Float(p.x),Float(p.y),Float(p.z),0),color:SIMD4(Float(c.x),Float(c.y),Float(c.z),Float(alpha)),meta:SIMD4(Float(size),Float(layer),Float(random()*tau),Float(flow)))
        }
        func point(_ p: SIMD3<Double>, _ c: SIMD3<Double>, _ alpha: Double, _ size: Double, _ layer: Double, _ flow: Double = 0) { g.particles.append(vertex(p,c,alpha,size,layer,flow)) }
        func line(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Double>, _ alpha: Double, _ layer: Double = 6) { g.lines.append(vertex(a,c,alpha,1,layer)); g.lines.append(vertex(b,c,alpha,1,layer)) }
        func path(_ n: Int, _ color: SIMD3<Double>, _ alpha: Double, _ layer: Double = 6, _ fn: (Double)->SIMD3<Double>) {
            for i in 0..<n { line(fn(Double(i)/Double(n)),fn(Double(i+1)/Double(n)),color,alpha,layer) }
        }
        func earPoint(_ side: Double, _ r: Double, _ t: Double) -> SIMD3<Double> {
            let shape=1+0.055*cos(3*t)-0.025*sin(2*t)
            return SIMD3(side*(0.625+0.075*r*cos(t))+0.102*r*sin(t)*shape,-0.035+0.325*r*cos(t),0.08+0.13*(1-r*r)+0.025*sin(t))
        }
        func vocalHeight(_ x: Double, _ z: Double) -> Double {
            func peak(_ center:Double,_ sigma:Double,_ amp:Double) -> Double { amp*exp(-pow((x-center-z*0.23)/sigma,2)) }
            return 0.355+z*0.10+peak(-0.035,0.055,0.155)+peak(0.185,0.072,0.095)+peak(-0.22,0.064,0.055)-peak(0.095,0.055,0.025)+0.008*cos(z*29+x*24)*exp(-pow(x/0.35,4))
        }
        for _ in 0..<5900 {
            let t=random()*tau, r=0.87+normal()*0.047, front=(sin(t)+1)/2
            let p=SIMD3(cos(t)*r,-0.385+normal()*0.021,sin(t)*r*0.73)
            point(p,low,0.28+front*0.62,0.55+pow(random(),5)*3.4,0,0.45+random()*0.25)
        }
        for _ in 0..<1600 {
            let t=random()*tau,r=0.89+normal()*0.095
            let p=SIMD3(cos(t)*r,-0.40+normal()*0.057,sin(t)*r*0.77)
            point(p,low,0.12+random()*0.27,0.4+random()*1.1,0,0.3)
        }
        for _ in 0..<2100 {
            let t=random()*tau,r=0.89+normal()*0.075
            let p=SIMD3(r*cos(t),-0.48+normal()*0.063,r*0.76*sin(t))
            point(p,low,0.09+random()*0.25,0.6+pow(random(),4)*2.2,0,0.2)
        }
        for side in [-1.0,1.0] { for _ in 0..<750 {
            let p=SIMD3(side*(0.36+normal()*0.077),-0.24+normal()*0.045,normal()*0.16)
            point(p,low,0.2+random()*0.65,0.6+pow(random(),4)*3.3,0)
        }}
        for _ in 0..<4000 {
            let t=random()*tau,y=0.03+random()*0.69,r=sqrt(max(0.08,1-pow((y-0.03)/0.86,2)))*(0.89+normal()*0.025)
            let a=(pow(sin(t),2)*0.65+0.12)*(1-(y/0.95)*0.18)
            point(SIMD3(cos(t)*r,y,sin(t)*r*0.72),high,a,0.5+pow(random(),5)*2.7,2,0.20)
        }
        for side in [-1.0,1.0] { for _ in 0..<1200 {
            let p=SIMD3(side*(0.56+normal()*0.072),0.565+normal()*0.047,normal()*0.14)
            point(p,high,0.4+random()*0.65,0.65+pow(random(),3)*2.5,2)
        }}
        for side in [-1.0,1.0] { for _ in 0..<1800 {
            let spread=random()<0.65 ? 0.055:0.12
            let p=SIMD3(side*(0.455+normal()*spread),0.15+normal()*0.05,normal()*0.15)
            point(p,mid,0.25+random()*0.58,0.5+pow(random(),4)*2.4,1)
        }}
        for _ in 0..<1300 {
            let t=random()*tau,r=0.85+normal()*0.04
            let p=SIMD3(r*cos(t),0.025+normal()*0.035,r*0.62*sin(t))
            point(p,mid,0.1+random()*0.23,0.45+random(),1,0.3)
        }
        for i in 0..<15 {
            let t=0.12+Double.pi*Double(i)/14,r=0.88,p=SIMD3(r*cos(t),-0.385,r*0.73*sin(t))
            point(p,low,0.85,6.5+random()*2.5,0)
            for _ in 0..<45 { let q=SIMD3(p.x+normal()*0.012,p.y+normal()*0.012,p.z+normal()*0.012); point(q,low,0.45,1+random(),0) }
        }
        for i in 0..<1450 {
            let c=i%3 == 0 ? low:high,p=SIMD3((random()-0.5)*2.35,(random()-0.5)*1.77,(random()-0.5)*1.65)
            point(p,c,0.06+random()*0.26,0.3+pow(random(),9)*1.3,5)
        }
        for i in 0..<15 {
            let y = -0.64+Double(i)*0.09,r=0.90*sqrt(max(0.2,1-pow((y-0.03)/0.98,2)))
            path(160,SIMD3(0.25,0.44,0.60),(i%3 == 0 ? 0.20:0.09)*1.10) { t in SIMD3(r*cos(t*tau),y,r*0.75*sin(t*tau)) }
        }
        for i in 0..<9 {
            let angle=Double(i)*Double.pi/9
            path(170,SIMD3(0.19,0.34,0.49),0.05) { t in let a=t*tau; return SIMD3(0.94*cos(a)*cos(angle),0.015+0.75*sin(a),0.71*cos(a)*sin(angle)) }
        }
        for k in 0..<7 {
            let r=0.81+Double(k)*0.035
            path(180,low,k%2 == 1 ? 0.08:0.17,0) { t in SIMD3(r*cos(t*tau),-0.39+sin(t*tau*3+Double(k))*0.018,r*0.75*sin(t*tau)) }
        }
        for side in [-1.0,1.0] {
            let n=120,rings=17
            for k in 1...rings { path(n,ear,k == rings ? 0.95:0.16+0.16*Double(k)/Double(rings),4) { t in earPoint(side,Double(k)/Double(rings),t*tau) } }
            for k in 0..<rings { for i in 0..<n {
                let t=Double(i)/Double(n)*tau,t1=Double(i+1)/Double(n)*tau,r=Double(k)/Double(rings),r1=Double(k+1)/Double(rings)
                let a=earPoint(side,r,t),b=earPoint(side,r1,t),c=earPoint(side,r1,t1),d=earPoint(side,r,t1)
                let col=SIMD3(0.53+0.20*r1,0.63+0.18*r1,0.84+0.12*r1),alpha=0.055+0.14*pow(r1,4)
                for p in [a,b,c,a,c,d] { g.surfaces.append(vertex(p,col,alpha,1,4)) }
            }}
            for i in 0..<12 {
                let z=0.095+Double(i)*0.003
                path(100,vocal,0.065,4) { t in var p=earPoint(side,0.35+Double(i)*0.043,t*tau);p.z=z+0.08*sin(t*tau);return p }
            }
            for _ in 0..<650 {
                let t=random()*tau,r=0.985+normal()*0.012,p=earPoint(side,r,t)
                point(p,cos(t)>0.05 ? ear:vocal,0.25+random()*0.55,0.65+pow(random(),3)*1.4,4)
            }
        }
        let nx=112,nz=26
        for j in 0..<nz {
            let z = -0.11+Double(j)/Double(nz-1)*0.22
            path(nx,vocal,0.12+0.25*Double(j)/Double(nz),3) { t in let x = -0.38+t*0.76; return SIMD3(x,vocalHeight(x,z),z) }
        }
        for i in stride(from:0,through:nx,by:3) {
            let x = -0.38+Double(i)/Double(nx)*0.76
            path(nz,vocal,0.16,3) { t in let z = -0.11+t*0.22;return SIMD3(x,vocalHeight(x,z),z) }
        }
        for j in 0..<(nz-1) { for i in 0..<nx {
            let x = -0.38+Double(i)/Double(nx)*0.76,x1 = -0.38+Double(i+1)/Double(nx)*0.76
            let z = -0.11+Double(j)/Double(nz-1)*0.22,z1 = -0.11+Double(j+1)/Double(nz-1)*0.22
            for (a,b) in [(x,z),(x1,z),(x1,z1),(x,z),(x1,z1),(x,z1)] { g.surfaces.append(vertex(SIMD3(a,vocalHeight(a,b),b),vocal,0.023,1,3)) }
        }}
        for i in 0..<5 {
            path(130,SIMD3(0.18,0.41,0.63),0.11) { t in SIMD3(cos(t*tau)*(0.13+Double(i)*0.046),-0.15-Double(i)*0.067,sin(t*tau)*(0.11+Double(i)*0.04)) }
        }
        path(120,SIMD3(0.16,0.29,0.43),0.12) { t in let a=t*tau;return SIMD3(0.125*cos(a),-0.02+0.21*sin(a),0.08) }
        point(SIMD3(0,-0.83,0),SIMD3(0.24,0.55,1),0.9,12,6)
        point(SIMD3(0,0.65,0),SIMD3(0.3,0.55,0.9),0.7,4,6)
        return g
    }
}

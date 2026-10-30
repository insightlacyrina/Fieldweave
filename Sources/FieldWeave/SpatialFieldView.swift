import AppKit
import MetalKit
import SwiftUI
import simd

struct FieldVisualOptions: Equatable {
    var lowWidth=1.2, midWidth=1.1, highWidth=1.3
    var centerPan=0.0, centerGainDb=0.0, depth=1.0, glow=1.0
    var centerElevationDegrees=0.0
    var lowIntensity=1.0, midIntensity=1.0, highIntensity=1.0
    var motion=true, contours=true, grid=false
    var lowVisible=true, midVisible=true, highVisible=true
    // The product uses Z as height; the renderer's upright axis is Y.
    var centerHeightOffset:Double {max(-45,min(45,centerElevationDegrees))/45*0.30}
}
private struct FieldUniforms {
    var viewport:SIMD2<Float>; var unit:Float; var time:Float
    var width:SIMD4<Float>; var layers:SIMD4<Float>; var effects:SIMD4<Float>; var center:SIMD4<Float>
}

struct SpatialFieldView: View {
    @AppStorage(AppLanguage.key) private var interfaceLanguage = "en"
    var options:FieldVisualOptions
    @FWState private var rendererError:String?
    var body: some View {
        ZStack {
            FieldBackdrop(options:options)
            NativeMetalField(options:options,error:$rendererError)
                .accessibilityLabel(L("Conceptual sound field; fixed origin, blue highs, green mids, orange lows, purple center Mid."))
            FieldAxes(options:options).allowsHitTesting(false)
            if let rendererError {
                VStack(spacing:12) { Image(systemName:"exclamationmark.triangle").font(.largeTitle); Text(L("Metal sound field unavailable")); Text(rendererError).font(.caption).textSelection(.enabled) }
                    .padding(24).background(.regularMaterial,in:RoundedRectangle(cornerRadius:16)).padding()
            }
        }
        .clipped()
    }
}

private func projectField(_ p:SIMD3<Double>,size:CGSize,options:FieldVisualOptions) -> CGPoint {
    let z=p.z*(0.7+0.3*options.depth),unit=min(size.width/2.36,size.height/1.88),perspective=1/(1+z*0.12)
    return CGPoint(x:size.width/2+p.x*unit*perspective,y:size.height/2-(p.y*0.94-z*0.33)*unit*perspective)
}
private struct FieldBackdrop:View {
    @AppStorage(AppLanguage.key) private var interfaceLanguage = "en"
    let options:FieldVisualOptions
    var body:some View {
        Canvas { context,size in
            let middle=CGPoint(x:size.width/2,y:size.height*0.52)
            context.fill(Path(CGRect(origin:.zero,size:size)),with:.radialGradient(Gradient(colors:[Color(red:0.031,green:0.078,blue:0.125),Color(red:0.016,green:0.039,blue:0.055)]),center:middle,startRadius:0,endRadius:size.width*0.65))
            let fog:[(SIMD3<Double>,Color,Double)]=[
                (SIMD3(-0.57,0.57,0),.blue,0.05),(SIMD3(0.57,0.57,0),.blue,0.05),
                (SIMD3(-0.49,0.16,0),.green,0.035),(SIMD3(0.49,0.16,0),.green,0.035),
                (SIMD3(0,-0.38,0),.orange,0.035),(SIMD3(options.centerPan*0.32,0.43+options.centerHeightOffset,0),.purple,0.04)]
            for (p,color,alpha) in fog {
                let center=projectField(p,size:size,options:options),r=min(size.width,size.height)*0.19
                let rect=CGRect(x:center.x-r,y:center.y-r,width:2*r,height:2*r)
                context.fill(Path(rect),with:.radialGradient(Gradient(colors:[color.opacity(alpha*options.glow),color.opacity(0)]),center:center,startRadius:0,endRadius:r))
            }
        }
    }
}
private struct FieldAxes:View {
    @AppStorage(AppLanguage.key) private var interfaceLanguage = "en"
    let options:FieldVisualOptions
    var body:some View {
        Canvas { context,size in
            func project(_ p:SIMD3<Double>)->CGPoint { projectField(p,size:size,options:options) }
            func line(_ a:SIMD3<Double>,_ b:SIMD3<Double>,_ alpha:Double) {
                var path=Path();path.move(to:project(a));path.addLine(to:project(b))
                context.stroke(path,with:.color(Color(red:0.53,green:0.67,blue:0.77).opacity(alpha)),lineWidth:0.65)
            }
            if options.grid { for i in -10...10 {
                line(SIMD3(Double(i)/10,-0.48,-1),SIMD3(Double(i)/10,-0.48,1),0.09)
                line(SIMD3(-1,-0.48,Double(i)/10),SIMD3(1,-0.48,Double(i)/10),0.09)
            }}
            line(SIMD3(0,-0.85,0),SIMD3(0,0.89,0),0.48)
            line(SIMD3(-1.03,-0.015,0),SIMD3(1.03,-0.015,0),0.21)
            line(SIMD3(0,-0.36,-0.94),SIMD3(0,-0.36,0.97),0.18)
            let labels:[(String,SIMD3<Double>,Double,Double)]=[("HEIGHT",SIMD3(0,0.89,0),0,-15),("FRONT",SIMD3(0,-0.85,0),0,16),("LEFT",SIMD3(-1.03,-0.015,0),-8,0),("RIGHT",SIMD3(1.03,-0.015,0),10,0),("DEPTH",SIMD3(0.98,-0.37,-0.18),0,0)]
            for (text,p,dx,dy) in labels {
                let q=project(p),point=CGPoint(x:max(25,min(size.width-25,q.x+dx)),y:max(14,min(size.height-14,q.y+dy)))
                context.draw(Text(L(text)).font(.system(size:10,weight:.medium,design:.monospaced)).foregroundColor(Color(red:0.75,green:0.82,blue:0.87)),at:point)
            }
        }
    }
}

private final class FixedFieldMTKView:MTKView {
    override var acceptsFirstResponder:Bool { false }
    override func scrollWheel(with event:NSEvent) {}
    override func magnify(with event:NSEvent) {}
    override func rotate(with event:NSEvent) {}
    override func mouseDown(with event:NSEvent) {}
    override func mouseDragged(with event:NSEvent) {}
    override func smartMagnify(with event:NSEvent) {}
}
private struct NativeMetalField:NSViewRepresentable {
    let options:FieldVisualOptions
    @Binding var error:String?
    func makeCoordinator()->Coordinator { Coordinator() }
    func makeNSView(context:Context)->MTKView {
        let view=FixedFieldMTKView(frame:.zero,device:MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor=MTLClearColor(red:0,green:0,blue:0,alpha:0)
        view.framebufferOnly=true;view.preferredFramesPerSecond=60
        view.layer?.isOpaque=false;view.wantsLayer=true;view.layer?.backgroundColor=NSColor.clear.cgColor
        do {
            let renderer=try FieldMetalRenderer(view:view)
            renderer.options=options;context.coordinator.renderer=renderer;view.delegate=renderer
        } catch { DispatchQueue.main.async { self.error=error.localizedDescription } }
        return view
    }
    func updateNSView(_ view:MTKView,context:Context) {context.coordinator.renderer?.options=options}
    static func dismantleNSView(_ view:MTKView,coordinator:Coordinator) {view.isPaused=true;view.delegate=nil;coordinator.renderer=nil}
    final class Coordinator { var renderer:FieldMetalRenderer? }
}
private final class FieldMetalRenderer:NSObject,MTKViewDelegate {
    var options=FieldVisualOptions()
    private let queue:MTLCommandQueue
    private let solidPipeline:MTLRenderPipelineState,pointPipeline:MTLRenderPipelineState
    private let particleBuffer:MTLBuffer,lineBuffer:MTLBuffer,surfaceBuffer:MTLBuffer
    private let particleCount:Int,lineCount:Int,surfaceCount:Int
    private var lastFrame=ProcessInfo.processInfo.systemUptime,time:Double=0
    init(view:MTKView) throws {
        guard let device=view.device,let queue=device.makeCommandQueue() else {throw NSError(domain:"FieldWeave.Metal",code:1,userInfo:[NSLocalizedDescriptionKey:"此 Mac 没有可用的 Metal 设备。"])}
        self.queue=queue
        guard let url=Bundle.module.url(forResource:"FieldShaders",withExtension:"metal",subdirectory:"Resources") else {throw NSError(domain:"FieldWeave.Metal",code:2,userInfo:[NSLocalizedDescriptionKey:"找不到内置 Metal 着色器。"])}
        let library=try device.makeLibrary(source:String(contentsOf:url,encoding:.utf8),options:nil)
        func pipeline(_ fragment:String)throws->MTLRenderPipelineState {
            let descriptor=MTLRenderPipelineDescriptor()
            descriptor.vertexFunction=library.makeFunction(name:"fieldVertex")
            descriptor.fragmentFunction=library.makeFunction(name:fragment)
            descriptor.colorAttachments[0].pixelFormat=view.colorPixelFormat
            descriptor.colorAttachments[0].isBlendingEnabled=true
            descriptor.colorAttachments[0].rgbBlendOperation = .add
            descriptor.colorAttachments[0].alphaBlendOperation = .add
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .one
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try device.makeRenderPipelineState(descriptor:descriptor)
        }
        solidPipeline=try pipeline("fieldSolid");pointPipeline=try pipeline("fieldParticle")
        let geometry=FieldGeometry.build()
        particleCount=geometry.particles.count;lineCount=geometry.lines.count;surfaceCount=geometry.surfaces.count
        func buffer(_ vertices:[FieldVertex])throws->MTLBuffer {
            guard let b=device.makeBuffer(bytes:vertices,length:vertices.count*MemoryLayout<FieldVertex>.stride,options:.storageModeShared) else {throw NSError(domain:"FieldWeave.Metal",code:3,userInfo:[NSLocalizedDescriptionKey:"声场顶点内存分配失败。"])}
            return b
        }
        particleBuffer=try buffer(geometry.particles);lineBuffer=try buffer(geometry.lines);surfaceBuffer=try buffer(geometry.surfaces)
        super.init()
    }
    func mtkView(_ view:MTKView,drawableSizeWillChange size:CGSize) {}
    func draw(in view:MTKView) {
        let now=ProcessInfo.processInfo.systemUptime,delta=min(max(now-lastFrame,0),0.06);lastFrame=now
        if options.motion && view.window?.occlusionState.contains(.visible) == true {time+=delta}
        guard view.bounds.width>0,view.bounds.height>0,let descriptor=view.currentRenderPassDescriptor,let drawable=view.currentDrawable,let command=queue.makeCommandBuffer(),let encoder=command.makeRenderCommandEncoder(descriptor:descriptor) else {return}
        let w=Float(view.bounds.width),h=Float(view.bounds.height),scale=Float(view.drawableSize.width/view.bounds.width)
        let o=options
        var uniforms=FieldUniforms(viewport:SIMD2(w,h),unit:min(w/2.36,h/1.88),time:Float(time),width:SIMD4(Float(o.lowWidth/1.2),Float(o.midWidth/1.1),Float(o.highWidth/1.3),Float(o.centerHeightOffset)),layers:SIMD4(Float(o.lowVisible ? o.lowIntensity:0),Float(o.midVisible ? o.midIntensity:0),Float(o.highVisible ? o.highIntensity:0),0),effects:SIMD4(Float(o.depth),Float(o.glow),1,scale),center:SIMD4(Float(o.centerPan),Float(pow(10,o.centerGainDb/20)),0,0))
        func draw(_ buffer:MTLBuffer,_ count:Int,_ primitive:MTLPrimitiveType,_ points:Bool,_ glow:Bool) {
            uniforms.center.z=glow ? 1:0;uniforms.center.w=points ? 1:0
            encoder.setRenderPipelineState(points ? pointPipeline:solidPipeline)
            encoder.setVertexBuffer(buffer,offset:0,index:0)
            encoder.setVertexBytes(&uniforms,length:MemoryLayout<FieldUniforms>.stride,index:1)
            encoder.drawPrimitives(type:primitive,vertexStart:0,vertexCount:count)
        }
        draw(surfaceBuffer,surfaceCount,.triangle,false,false)
        if o.contours {draw(lineBuffer,lineCount,.line,false,false)}
        draw(particleBuffer,particleCount,.point,true,true);draw(particleBuffer,particleCount,.point,true,false)
        encoder.endEncoding();command.present(drawable);command.commit()
    }
}

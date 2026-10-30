import AppKit
import Foundation
let destination=CommandLine.arguments[1]
let iconset=URL(fileURLWithPath:destination).deletingLastPathComponent().appendingPathComponent("FieldWeave.iconset")
try FileManager.default.createDirectory(at:iconset,withIntermediateDirectories:true)
func render(_ size:Int)->Data {
    let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:size*4,bitsPerPixel:32)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep)
    let s=CGFloat(size),rect=NSRect(x:0,y:0,width:s,height:s)
    NSColor(red:0.025,green:0.05,blue:0.08,alpha:1).setFill()
    NSBezierPath(roundedRect:rect.insetBy(dx:s*0.02,dy:s*0.02),xRadius:s*0.22,yRadius:s*0.22).fill()
    let colors:[NSColor]=[NSColor(red:0.25,green:0.55,blue:1,alpha:1),NSColor(red:0.60,green:0.96,blue:0.72,alpha:1),NSColor(red:1,green:0.37,blue:0.14,alpha:1)]
    for band in 0..<3 {
        for ring in 0..<8 {
            let path=NSBezierPath();let w=s*(0.60+CGFloat(ring)*0.016),h=s*0.19
            for i in 0...200 {
                let t=CGFloat(i)/200 * .pi*2,x=s/2+cos(t)*w/2,y=s*(0.72-CGFloat(band)*0.20)+sin(t)*h/2
                if i==0 {path.move(to:NSPoint(x:x,y:y))} else {path.line(to:NSPoint(x:x,y:y))}
            }
            colors[band].withAlphaComponent(0.12+CGFloat(ring)*0.045).setStroke();path.lineWidth=max(0.5,s*0.0015);path.stroke()
        }
    }
    let wave=NSBezierPath()
    for i in 0...180 {let x=CGFloat(i)/180,y=0.51+0.10*exp(-pow((x-0.48)/0.07,2))+0.055*exp(-pow((x-0.67)/0.08,2));let p=NSPoint(x:s*(0.22+x*0.56),y:s*y);if i==0{wave.move(to:p)}else{wave.line(to:p)}}
    NSColor(red:0.78,green:0.57,blue:1,alpha:0.95).setStroke();wave.lineWidth=s*0.007;wave.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using:.png,properties:[:])!
}
for size in [16,32,128,256,512] {
    try render(size).write(to:iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size*2).write(to:iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let p=Process();p.executableURL=URL(fileURLWithPath:"/usr/bin/iconutil");p.arguments=["-c","icns",iconset.path,"-o",destination];try p.run();p.waitUntilExit();guard p.terminationStatus==0 else {exit(1)}
try FileManager.default.removeItem(at:iconset)

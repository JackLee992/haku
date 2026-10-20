import AppKit
import Foundation
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
for (name, size) in [("Icon60@2x.png", 120), ("Icon60@3x.png", 180)] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(size)/180
    let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
    NSColor(calibratedRed: 0.035, green: 0.09, blue: 0.12, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: 0,y: 0,width: 180,height: 180)).fill()
    NSColor(calibratedRed: 0.34, green: 0.89, blue: 0.76, alpha: 1).setStroke()
    let mark = NSBezierPath();mark.lineWidth = 15;mark.lineCapStyle = .round;mark.lineJoinStyle = .round
    mark.move(to: NSPoint(x: 54,y: 48));mark.line(to: NSPoint(x: 54,y: 132))
    mark.move(to: NSPoint(x: 126,y: 48));mark.line(to: NSPoint(x: 126,y: 132))
    mark.move(to: NSPoint(x: 54,y: 90));mark.line(to: NSPoint(x: 104,y: 90));mark.curve(to: NSPoint(x: 126,y: 114),controlPoint1: NSPoint(x: 120,y: 90),controlPoint2: NSPoint(x: 126,y: 99));mark.stroke()
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
}

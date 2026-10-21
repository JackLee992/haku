import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: icon.swift OUTPUT_DIRECTORY MASTER_PNG")
}
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let sourceURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = NSImage(contentsOf: sourceURL)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
      source.width == 1024, source.height == 1024,
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
    fatalError("The icon master must be a readable 1024 by 1024 image")
}
for (name, size) in [("Icon60@2x.png", 120), ("Icon60@3x.png", 180)] {
    guard let context = CGContext(data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: size * 4, space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        fatalError("Cannot create the opaque icon bitmap")
    }
    context.interpolationQuality = .high
    context.draw(source, in: CGRect(x: 0, y: 0, width: size, height: size))
    let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
    try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
}

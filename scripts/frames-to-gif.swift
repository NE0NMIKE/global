// Combines numbered PNG frames into a looping animated GIF, resized to a
// given width, using ImageIO (no third-party tools needed).
//
//   swift scripts/frames-to-gif.swift <frames-dir> <out.gif> <width> <fps>
import AppKit
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 5, let width = Int(args[3]), let fps = Double(args[4]) else {
    print("usage: frames-to-gif.swift <frames-dir> <out.gif> <width> <fps>")
    exit(2)
}
let dir = URL(fileURLWithPath: args[1])
let frames = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "png" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
guard !frames.isEmpty,
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL,
                                                 UTType.gif.identifier as CFString, frames.count, nil)
else { print("no frames or cannot write"); exit(1) }

CGImageDestinationSetProperties(dest, [
    kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],   // loop forever
] as CFDictionary)
let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]] as CFDictionary

for url in frames {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, [
              kCGImageSourceCreateThumbnailFromImageAlways: true,
              kCGImageSourceThumbnailMaxPixelSize: width,
          ] as CFDictionary)
    else { continue }
    CGImageDestinationAddImage(dest, thumb, frameProps)
}
guard CGImageDestinationFinalize(dest) else { print("failed to write GIF"); exit(1) }
print("✓ \(args[2]) (\(frames.count) frames)")

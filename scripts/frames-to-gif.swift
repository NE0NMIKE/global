// Combines numbered PNG frames into a looping animated GIF, resized to a
// given width, using ImageIO (no third-party tools needed).
//
//   swift -O scripts/frames-to-gif.swift <frames-dir> <out.gif> <width> <fps> [dither]
//
// GIFs have 256 colours per frame, so smooth gradients band. `dither` (in
// 8-bit levels, e.g. 10) adds a fixed 8×8 Bayer pattern before encoding: it
// turns bands into fine texture and, being identical every frame, doesn't shimmer.
import AppKit
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 5, let width = Int(args[3]), let fps = Double(args[4]) else {
    print("usage: frames-to-gif.swift <frames-dir> <out.gif> <width> <fps> [dither]")
    exit(2)
}
let dither = args.count > 5 ? Double(args[5]) ?? 0 : 0

/// 8×8 ordered-dither thresholds, 0…63.
let bayer: [Int] = {
    var m = [0]
    var n = 1
    while n < 8 {
        var next = [Int](repeating: 0, count: 4 * n * n)
        for y in 0..<n { for x in 0..<n {
            let v = 4 * m[y * n + x]
            next[y * 2 * n + x] = v
            next[y * 2 * n + x + n] = v + 2
            next[(y + n) * 2 * n + x] = v + 3
            next[(y + n) * 2 * n + x + n] = v + 1
        } }
        m = next
        n *= 2
    }
    return m
}()

/// Adds the Bayer pattern (±dither/2 levels) to every colour channel.
func dithered(_ image: CGImage) -> CGImage {
    guard dither > 0 else { return image }
    let w = image.width, h = image.height
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
          let data = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return image }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    for y in 0..<h {
        for x in 0..<w {
            let offset = Int(((Double(bayer[(y % 8) * 8 + x % 8]) + 0.5) / 64 - 0.5) * dither)
            let i = (y * w + x) * 4
            for c in 0..<3 { data[i + c] = UInt8(clamping: Int(data[i + c]) + offset) }
        }
    }
    return ctx.makeImage() ?? image
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
    CGImageDestinationAddImage(dest, dithered(thumb), frameProps)
}
guard CGImageDestinationFinalize(dest) else { print("failed to write GIF"); exit(1) }
print("✓ \(args[2]) (\(frames.count) frames)")

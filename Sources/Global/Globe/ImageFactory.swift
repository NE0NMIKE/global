import AppKit

/// Procedurally drawn textures: glows, rings, gradients and backdrops.
enum ImageFactory {
    /// Draws into a bitmap and returns a CGImage. Uses premultiplied BGRA, the
    /// layout Core Animation and Metal use natively, so images can be shown
    /// without a converted second copy.
    static func draw(_ width: Int, _ height: Int, _ body: (CGContext) -> Void) -> CGImage? {
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.interpolationQuality = .high
        ctx.setShouldAntialias(true)
        body(ctx)
        return ctx.makeImage()
    }

    /// White radial falloff (centre opaque → edge transparent). Tint via material.multiply.
    static func radialGlow(size: Int = 256, falloff: CGFloat = 2.2) -> CGImage? {
        draw(size, size) { ctx in
            let c = CGFloat(size) / 2
            var stops: [CGFloat] = []
            var colours: [CGColor] = []
            for i in 0...16 {
                let r = CGFloat(i) / 16
                stops.append(r)
                colours.append(CGColor(gray: 1, alpha: pow(1 - r, falloff)))
            }
            let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                               colors: colours as CFArray, locations: stops)!
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: c, y: c), startRadius: 0,
                                   endCenter: CGPoint(x: c, y: c), endRadius: c, options: [])
        }
    }

    /// Soft-edged white disc filling the image (dot-matrix dots).
    static func disc(size: Int = 64) -> CGImage? {
        draw(size, size) { ctx in
            let inset = CGFloat(size) * 0.06
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: inset, y: inset,
                                       width: CGFloat(size) - 2 * inset, height: CGFloat(size) - 2 * inset))
        }
    }

    /// Thin white ring (ripple animation).
    static func ring(size: Int = 256, lineFraction: CGFloat = 0.05) -> CGImage? {
        draw(size, size) { ctx in
            let s = CGFloat(size), lw = s * lineFraction
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
            ctx.setLineWidth(lw)
            ctx.strokeEllipse(in: CGRect(x: lw, y: lw, width: s - 2 * lw, height: s - 2 * lw))
        }
    }

    /// Location pin drawn as a ring with a centre dot, in two colours.
    static func ringMarker(size: Int = 256, ring: NSColor, fill: NSColor, centre: NSColor) -> CGImage? {
        draw(size, size) { ctx in
            let s = CGFloat(size)
            let lw = s * 0.07
            let r = CGRect(x: lw, y: lw, width: s - 2 * lw, height: s - 2 * lw)
            ctx.setFillColor(fill.cgColor)
            ctx.fillEllipse(in: r)
            ctx.setStrokeColor(ring.cgColor)
            ctx.setLineWidth(lw)
            ctx.strokeEllipse(in: r)
            let d = s * 0.30
            ctx.setFillColor(centre.cgColor)
            ctx.fillEllipse(in: CGRect(x: (s - d) / 2, y: (s - d) / 2, width: d, height: d))
        }
    }

    /// Atmosphere halo for a disc whose edge sits at `edge` (fraction of the half-size).
    /// Transparent inside, bright at the limb, fading outward.
    static func atmosphere(size: Int = 1024, edge: CGFloat, falloff: CGFloat = 14) -> CGImage? {
        draw(size, size) { ctx in
            let c = CGFloat(size) / 2
            var stops: [CGFloat] = [0, max(0, edge - 0.02)]
            var colours: [CGColor] = [CGColor(gray: 1, alpha: 0), CGColor(gray: 1, alpha: 0)]
            for i in 0...24 {
                let t = CGFloat(i) / 24
                let r = edge + (1 - edge) * t
                stops.append(r)
                colours.append(CGColor(gray: 1, alpha: 0.9 * exp(-(r - edge) * falloff)))
            }
            let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                               colors: colours as CFArray, locations: stops)!
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: c, y: c), startRadius: 0,
                                   endCenter: CGPoint(x: c, y: c), endRadius: c, options: [])
        }
    }

    /// Horizontal gradient strip (used along the arc: u = 0 → `a`, u = 1 → `b`).
    static func horizontalGradient(_ a: NSColor, _ b: NSColor, width: Int = 256) -> CGImage? {
        draw(width, 4) { ctx in
            let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                               colors: [a.cgColor, b.cgColor] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: width, y: 0), options: [])
        }
    }

    /// Grayscale land mask as a CGImage (white = land), for the silhouette style.
    static func landMask(_ land: LandData) -> CGImage? {
        guard !land.mask.isEmpty else { return nil }
        let data = Data(land.mask) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: land.maskWidth, height: land.maskHeight, bitsPerComponent: 8,
                       bitsPerPixel: 8, bytesPerRow: land.maskWidth,
                       space: CGColorSpaceCreateDeviceGray(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Full-screen backdrop (see `drawBackdrop`).
    /// Drawn at the view's exact pixel size so nothing is stretched.
    static func backdrop(pixelSize: CGSize, theme: GlobeTheme, globeCentre: CGPoint,
                         globeRadius: CGFloat, scale: CGFloat) -> CGImage? {
        draw(Int(pixelSize.width), Int(pixelSize.height)) { ctx in
            drawBackdrop(in: ctx, width: Int(pixelSize.width), height: Int(pixelSize.height), theme: theme,
                         globeCentre: globeCentre, globeRadius: globeRadius, scale: scale)
        }
    }

    /// Draws the backdrop into any bitmap context of `width` × `height` pixels
    /// (bottom-left origin; `globeCentre` and `globeRadius` in pixels).
    static func drawBackdrop(in ctx: CGContext, width w: Int, height h: Int, theme: GlobeTheme,
                             globeCentre: CGPoint, globeRadius: CGFloat, scale: CGFloat) {
        switch theme.backdrop {
        case .gradient:
            drawGradient(in: ctx, width: w, height: h, theme: theme, globeCentre: globeCentre,
                         globeRadius: globeRadius)
            drawStars(in: ctx, width: w, height: h, density: theme.starDensity, scale: scale) {
                // Keep the globe's disc clear.
                hypot($0.x - globeCentre.x, $0.y - globeCentre.y) < globeRadius * 1.02 ? 0 : 1
            }
        case .sun:
            drawSun(in: ctx, width: w, height: h, theme: theme, globeCentre: globeCentre,
                    globeRadius: globeRadius, scale: scale)
        }
    }

    /// Radial gradient, brightest around the globe, fading to a vignette.
    private static func drawGradient(in ctx: CGContext, width w: Int, height h: Int, theme: GlobeTheme,
                                     globeCentre: CGPoint, globeRadius: CGFloat) {
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: [theme.background.cgColor, theme.backgroundEdge.cgColor] as CFArray,
                           locations: [0, 1])!
        ctx.setFillColor(theme.backgroundEdge.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let far = hypot(CGFloat(w), CGFloat(h))
        ctx.drawRadialGradient(g, startCenter: globeCentre, startRadius: globeRadius * 0.6,
                               endCenter: globeCentre, endRadius: far * 0.75,
                               options: [.drawsAfterEndLocation])
    }

    /// Where the sun sits for a globe: up and to the right of it (behind the
    /// info panel, so the panel's dark text stays on a bright background),
    /// large enough to run off the top and bottom of the screen.
    static func sunDisc(height: CGFloat, globeCentre: CGPoint, globeRadius r: CGFloat) -> (centre: CGPoint, radius: CGFloat) {
        (CGPoint(x: globeCentre.x + 1.25 * r, y: globeCentre.y + 0.55 * r), 0.78 * height)
    }

    /// Dark space with a giant sun behind the globe (Realistic, light).
    private static func drawSun(in ctx: CGContext, width w: Int, height h: Int, theme: GlobeTheme,
                                globeCentre: CGPoint, globeRadius: CGFloat, scale: CGFloat) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)
        let H = CGFloat(h)
        let (centre, radius) = sunDisc(height: H, globeCentre: globeCentre, globeRadius: globeRadius)

        // Space, warming towards the sun.
        ctx.setFillColor(theme.backgroundEdge.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let sky = CGGradient(colorsSpace: space,
                             colors: [srgb(0x2A2418), srgb(0x0D0E16), theme.backgroundEdge.cgColor] as CFArray,
                             locations: [0, 0.45, 1])!
        ctx.drawRadialGradient(sky, startCenter: centre, startRadius: radius, endCenter: centre,
                               endRadius: radius + hypot(CGFloat(w), H) * 0.6, options: [.drawsAfterEndLocation])

        // Stars, fading out in the sun's glare.
        drawStars(in: ctx, width: w, height: h, density: theme.starDensity, scale: scale) {
            min(1, max(0, (hypot($0.x - centre.x, $0.y - centre.y) - radius) / (0.5 * H)))
        }

        // Corona: warm light falling off outside the disc.
        let corona = CGGradient(colorsSpace: space,
                                colors: [srgb(0xFFD58A, 0.85), srgb(0xFFB860, 0.35),
                                         srgb(0xF29A4A, 0.12), srgb(0xE07A3A, 0)] as CFArray,
                                locations: [0, 0.08, 0.3, 1])!
        ctx.drawRadialGradient(corona, startCenter: centre, startRadius: radius, endCenter: centre,
                               endRadius: radius + 0.55 * H, options: [])

        // Photosphere, darker and warmer towards the limb.
        let disc = CGGradient(colorsSpace: space,
                              colors: [srgb(0xFFFDF6), srgb(0xFFF7E4), srgb(0xFFE9BC),
                                       srgb(0xFFD48A), srgb(0xFFBE66)] as CFArray,
                              locations: [0, 0.55, 0.82, 0.96, 1])!
        ctx.drawRadialGradient(disc, startCenter: centre, startRadius: 0, endCenter: centre,
                               endRadius: radius, options: [])
    }

    /// Deterministic starfield (seeded) so every launch looks the same.
    /// `visibility` scales each star's opacity by its position (0 hides it).
    private static func drawStars(in ctx: CGContext, width w: Int, height h: Int, density: CGFloat,
                                  scale: CGFloat, visibility: (CGPoint) -> CGFloat) {
        guard density > 0 else { return }
        var rng = SeededRandom(seed: 0x6C0BA1)
        let area = CGFloat(w * h) / (scale * scale)
        let count = Int(area / 2600 * density)
        for _ in 0..<count {
            let p = CGPoint(x: CGFloat(rng.next()) * CGFloat(w), y: CGFloat(rng.next()) * CGFloat(h))
            let v = visibility(p)
            guard v > 0 else { continue }
            let m = CGFloat(rng.next())
            let size = (m > 0.985 ? 1.6 : m > 0.9 ? 1.1 : 0.7) * scale
            let alpha = (0.25 + 0.75 * pow(CGFloat(rng.next()), 2.5)) * density * v
            // Slight colour temperature variation.
            let t = CGFloat(rng.next())
            ctx.setFillColor(CGColor(srgbRed: 0.85 + 0.15 * t, green: 0.88 + 0.08 * t,
                                     blue: 1.0 - 0.12 * t, alpha: min(1, alpha)))
            ctx.fillEllipse(in: CGRect(x: p.x, y: p.y, width: size, height: size))
        }
    }

    private static func srgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

/// Small deterministic PRNG (SplitMix64) returning values in 0…1.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z = z ^ (z >> 31)
        return Double(z >> 11) / Double(1 << 53)
    }
}

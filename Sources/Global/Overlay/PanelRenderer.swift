import AppKit

/// Draws the info panel and marker tags as bitmaps (crisp SF typography via
/// AppKit text drawing), which the panel layer and tag nodes then display.
enum PanelRenderer {

    // MARK: - Fonts

    private static func font(_ size: CGFloat, _ weight: NSFont.Weight, _ face: GlobeTheme.Typeface) -> NSFont {
        switch face {
        case .sans: return NSFont.systemFont(ofSize: size, weight: weight)
        case .mono: return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        }
    }

    private static func digits(_ size: CGFloat, _ weight: NSFont.Weight, _ face: GlobeTheme.Typeface) -> NSFont {
        switch face {
        case .sans: return NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        case .mono: return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        }
    }

    private static func text(_ s: String, _ font: NSFont, _ colour: NSColor, kern: CGFloat = 0) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: colour, .kern: kern])
    }

    // MARK: - Info panel

    struct Output {
        var image: CGImage
        var size: CGSize        // points
    }

    /// Renders the panel at `scale` pixels per point.
    static func panel(_ c: InfoContent, theme t: GlobeTheme, width: CGFloat, scale: CGFloat) -> Output? {
        let face = t.typeface
        let pad: CGFloat = 32
        let inner = width - pad * 2

        // Build the text runs top to bottom with their spacing.
        enum Item {
            case moon
            case text(NSAttributedString, spacingAfter: CGFloat)
            /// Title on the left, short detail right-aligned on the same baseline.
            case row(NSAttributedString, trailing: NSAttributedString, spacingAfter: CGFloat)
            case rule(spacingAfter: CGFloat)
            case big(NSAttributedString, unit: NSAttributedString, spacingAfter: CGFloat)
        }

        let titleFont = font(13, .semibold, face)
        let timeFont = digits(13, .regular, face)
        var items: [Item] = [.moon]

        // "ALEX IN PARIS           14:32"
        for line in [c.me, c.partner] {
            items.append(.row(text(line.title.uppercased(), titleFont, t.ink, kern: 1.6),
                              trailing: text(line.detail, timeFont, t.inkSecondary, kern: 0.4),
                              spacingAfter: 12))
        }
        items.append(.rule(spacingAfter: 18))

        if let d = c.distance {
            let big = text(d, digits(76, face == .mono ? .light : .ultraLight, face), t.ink, kern: -1)
            let unit = text(c.distanceUnit.uppercased(), font(15, .medium, face), t.inkSecondary, kern: 1.5)
            items.append(.big(big, unit: unit, spacingAfter: 6))
        }
        if let diff = c.timeDifference {
            items.append(.text(text(diff.uppercased(), font(12, .medium, face), t.ink, kern: 1.8), spacingAfter: 8))
        }
        for foot in c.footnotes {
            items.append(.text(text(foot.uppercased(), font(10.5, .medium, face), t.inkSecondary, kern: 1.6),
                               spacingAfter: 4))
        }

        // Measure.
        let moonSize: CGFloat = 26
        var height = pad
        for item in items {
            switch item {
            case .moon: height += moonSize + 22
            case let .text(s, after): height += ceil(s.size().height) + after
            case let .row(s, trailing, after): height += ceil(max(s.size().height, trailing.size().height)) + after
            case let .rule(after): height += 1 + after
            case let .big(s, _, after): height += ceil(s.size().height) * 0.92 + after
            }
        }
        height += pad - 4
        let size = CGSize(width: width, height: ceil(height))

        guard let image = ImageFactory.draw(Int(size.width * scale), Int(size.height * scale), { ctx in
            ctx.scaleBy(x: scale, y: scale)
            let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = ns
            defer { NSGraphicsContext.restoreGraphicsState() }

            drawGlassCard(CGRect(origin: .zero, size: size), theme: t)

            var y = size.height - pad   // drawing top-down in a bottom-left space
            for item in items {
                switch item {
                case .moon:
                    let r = CGRect(x: pad, y: y - moonSize, width: moonSize, height: moonSize)
                    drawMoon(in: r, phase: c.moonPhase, theme: t)
                    y -= moonSize + 22
                case let .text(s, after):
                    let h = ceil(s.size().height)
                    s.draw(with: CGRect(x: pad, y: y - h, width: inner, height: h),
                           options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
                    y -= h + after
                case let .row(title, trailing, after):
                    let h = ceil(max(title.size().height, trailing.size().height))
                    let tw = ceil(trailing.size().width)
                    // Both runs are 13 pt, so drawing from the same top keeps their baselines level.
                    trailing.draw(at: CGPoint(x: pad + inner - tw, y: y - h))
                    let room = inner - (tw > 0 ? tw + 16 : 0)
                    title.draw(with: CGRect(x: pad, y: y - h, width: room, height: h),
                               options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
                    y -= h + after
                case let .rule(after):
                    t.rule.setFill()
                    CGRect(x: pad, y: y - 1, width: inner, height: 1).fill()
                    y -= 1 + after
                case let .big(s, unit, after):
                    let sz = s.size()
                    let h = ceil(sz.height)
                    s.draw(at: CGPoint(x: pad - 3, y: y - h))
                    let font = s.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
                    let baseline = y - h - (font?.descender ?? 0)
                    let unitFont = unit.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
                    unit.draw(at: CGPoint(x: pad - 3 + sz.width + 8,
                                          y: baseline + (unitFont?.descender ?? 0)))
                    y -= h * 0.92 + after
                }
            }
        }) else { return nil }
        return Output(image: image, size: size)
    }

    // MARK: - Marker tag

    /// Capsule tag: colour dot, "[Name] in [City]", and an optional detail line.
    static func tag(_ line: InfoContent.Line, colour: NSColor, theme t: GlobeTheme, scale: CGFloat) -> Output? {
        let title = text(line.title, font(13, .semibold, t.typeface), t.ink)
        let detail = line.detail.isEmpty ? nil : text(line.detail, digits(11, .regular, t.typeface), t.inkSecondary)
        let ts = title.size(), ds = detail?.size() ?? .zero
        let dot: CGFloat = 8
        let hPad: CGFloat = 14, vPad: CGFloat = 8
        let textW = max(ts.width, ds.width)
        let textH = ts.height + (detail == nil ? 0 : ds.height + 1)
        let size = CGSize(width: ceil(hPad + dot + 9 + textW + hPad), height: ceil(textH + vPad * 2))

        guard let image = ImageFactory.draw(Int(size.width * scale), Int(size.height * scale), { ctx in
            ctx.scaleBy(x: scale, y: scale)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            defer { NSGraphicsContext.restoreGraphicsState() }

            drawGlassCard(CGRect(origin: .zero, size: size), theme: t, radius: min(16, size.height / 2))
            colour.setFill()
            NSBezierPath(ovalIn: CGRect(x: hPad, y: (size.height - dot) / 2, width: dot, height: dot)).fill()
            let x = hPad + dot + 9
            title.draw(at: CGPoint(x: x, y: size.height - vPad - ts.height))
            detail?.draw(at: CGPoint(x: x, y: vPad))
        }) else { return nil }
        return Output(image: image, size: size)
    }

    // MARK: - Pieces

    /// Translucent card in the style of macOS materials: a faint fill, a
    /// hairline border brighter at the top edge, and generous corner radius.
    private static func drawGlassCard(_ rect: CGRect, theme t: GlobeTheme, radius: CGFloat = 26) {
        let r = rect.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
        // Light cards take a paler shade of the backdrop rather than pure white,
        // so they don't glare against an off-white background.
        let lightFill = (t.background.blended(withFraction: 0.5, of: .white) ?? .white).withAlphaComponent(0.6)
        (t.isDark ? NSColor(white: 1, alpha: 0.055) : lightFill).setFill()
        path.fill()

        let top = t.isDark ? NSColor(white: 1, alpha: 0.22) : NSColor(white: 1, alpha: 0.95)
        let bottom = t.isDark ? NSColor(white: 1, alpha: 0.06) : NSColor(white: 0, alpha: 0.08)
        NSGraphicsContext.saveGraphicsState()
        path.lineWidth = 1
        path.setClip()
        if let g = NSGradient(starting: bottom, ending: top) {
            // Stroke with a vertical gradient by clipping to the outline.
            let outline = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
            outline.lineWidth = 2
            if let cg = NSGraphicsContext.current?.cgContext {
                cg.addPath(outline.cgPathCompat)
                cg.setLineWidth(2)
                cg.replacePathWithStrokedPath()
                cg.clip()
                g.draw(in: rect, angle: 90)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Moon phase glyph: dim disc with the lit portion drawn on top.
    private static func drawMoon(in rect: CGRect, phase p: Double, theme t: GlobeTheme) {
        let r = rect.width / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        (t.isDark ? NSColor(white: 1, alpha: 0.10) : NSColor(white: 0, alpha: 0.08)).setFill()
        NSBezierPath(ovalIn: rect).fill()

        let side: CGFloat = p < 0.5 ? 1 : -1
        let k = CGFloat(cos(2 * .pi * p))
        let lit = NSBezierPath()
        let steps = 48
        for i in 0...steps {   // lit limb, top → bottom
            let θ = CGFloat.pi / 2 - CGFloat.pi * CGFloat(i) / CGFloat(steps)
            let pt = CGPoint(x: c.x + side * r * cos(θ), y: c.y + r * sin(θ))
            i == 0 ? lit.move(to: pt) : lit.line(to: pt)
        }
        for i in 0...steps {   // terminator, bottom → top
            let θ = -CGFloat.pi / 2 + CGFloat.pi * CGFloat(i) / CGFloat(steps)
            lit.line(to: CGPoint(x: c.x + side * r * cos(θ) * k, y: c.y + r * sin(θ)))
        }
        lit.close()
        (t.isDark ? NSColor(white: 0.96, alpha: 0.92) : t.ink.withAlphaComponent(0.75)).setFill()
        lit.fill()

        (t.isDark ? NSColor(white: 1, alpha: 0.25) : NSColor(white: 0, alpha: 0.2)).setStroke()
        let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
        ring.lineWidth = 1
        ring.stroke()
    }
}

extension NSBezierPath {
    /// `cgPath` is only public from macOS 14; build it manually for 13.
    var cgPathCompat: CGPath {
        let path = CGMutablePath()
        var pts = [CGPoint](repeating: .zero, count: 3)
        for i in 0..<elementCount {
            switch element(at: i, associatedPoints: &pts) {
            case .moveTo: path.move(to: pts[0])
            case .lineTo: path.addLine(to: pts[0])
            case .cubicCurveTo: path.addCurve(to: pts[2], control1: pts[0], control2: pts[1])
            case .quadraticCurveTo: path.addQuadCurve(to: pts[1], control: pts[0])
            case .closePath: path.closeSubpath()
            @unknown default: break
            }
        }
        return path
    }
}

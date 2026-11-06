import AppKit
import IOSurface

/// Window content for one display.
///
/// Only the globe moves, so only the globe is rendered every frame:
///   1. backdrop: gradient and starfield, the view's own layer contents
///      (drawn once per layout or theme change);
///   2. `GlobeView`: a transparent SceneKit view covering just the globe;
///   3. info panel: a layer whose bitmap is redrawn only when its text changes.
/// Core Animation composites the static layers without redrawing them.
final class WallpaperView: NSView {
    let globeView: GlobeView
    private let panelView = NSView()

    private var model = RenderModel()
    private(set) var layout: GlobeLayout?
    private var backdropKey: String?
    private var backdrop: BackdropSurface?
    private var sceneBackgroundKey: String?
    private var panelKey: String?
    private var panelImage: CGImage?
    private var panelSize: CGSize = .zero

    init(frame: NSRect, frameRate: Int) {
        globeView = GlobeView(frame: .zero, frameRate: frameRate)
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.contentsGravity = .resize
        addSubview(globeView)

        panelView.wantsLayer = true
        panelView.layerContentsRedrawPolicy = .never
        panelView.layer?.contentsGravity = .resize
        panelView.isHidden = true
        addSubview(panelView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var isAnimating: Bool { globeView.isAnimating }

    private var backingScale: CGFloat {
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    private var theme: GlobeTheme { GlobeTheme.theme(for: model.style, dark: model.isDark) }

    // MARK: - Inputs

    func setModel(_ model: RenderModel) {
        self.model = model
        relayout()
        globeView.setModel(model, showsPanel: layout?.panelAnchor != nil)
        refreshPanel()
    }

    func setFrameRate(_ fps: Int) { globeView.setFrameRate(fps) }

    func setAnimating(_ on: Bool) { globeView.setAnimating(on) }

    /// Called periodically: keeps the panel's clocks current and, while
    /// paused, re-renders the globe so the day/night line still moves.
    func tick(refreshGlobe: Bool) {
        refreshPanel()
        if refreshGlobe && !globeView.isAnimating { globeView.refreshStill() }
    }

    // MARK: - Layout

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        relayout()
        refreshPanel()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        backdropKey = nil
        panelKey = nil
        relayout()
        refreshPanel()
    }

    private func relayout() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let l = GlobeLayout.compute(viewSize: bounds.size, globeScale: model.globeScale,
                                    showPanel: model.showInfoPanel)
        layout = l
        let tags = TagNodes.isNeeded(model: model, showsPanel: l.panelAnchor != nil)
        let rect = l.sceneRect(withTags: tags)
        if globeView.frame != rect { globeView.frame = rect }
        globeView.setLayout(l.local(in: rect))
        updateBackdrop(l)

        let bgKey = "\(backdropKey ?? "")-\(rect)"
        if bgKey != sceneBackgroundKey {
            sceneBackgroundKey = bgKey
            globeView.setBackground(backdrop?.image(
                pixelRect: WallpaperView.pixelRect(rect, viewSize: l.viewSize, scale: backingScale)))
        }
    }

    /// `rect` (points, bottom-left origin) as pixels with a top-left origin,
    /// the way bitmaps are addressed.
    static func pixelRect(_ rect: CGRect, viewSize: CGSize, scale: CGFloat) -> CGRect {
        CGRect(x: rect.minX * scale, y: (viewSize.height - rect.maxY) * scale,
               width: rect.width * scale, height: rect.height * scale).integral
    }

    /// The part of `backdrop` under `rect` (points, bottom-left origin).
    static func crop(_ backdrop: CGImage, to rect: CGRect, viewSize: CGSize, scale: CGFloat) -> CGImage? {
        backdrop.cropping(to: pixelRect(rect, viewSize: viewSize, scale: scale))
    }

    private func updateBackdrop(_ layout: GlobeLayout) {
        let scale = backingScale
        let t = theme
        let key = "\(layout)-\(scale)-\(t.isDark)-\(t.backdrop)-\(t.background)-\(t.backgroundEdge)-\(t.starDensity)"
        guard key != backdropKey else { return }
        backdropKey = key
        backdrop = BackdropSurface(layout: layout, theme: t, scale: scale)
        withoutAnimation {
            layer?.contents = backdrop?.surface
            layer?.contentsScale = scale
        }
    }

    static func backdrop(layout: GlobeLayout, theme: GlobeTheme, scale: CGFloat) -> CGImage? {
        let px = CGSize(width: layout.viewSize.width * scale, height: layout.viewSize.height * scale)
        let centre = CGPoint(x: layout.globeCentre.x * scale, y: layout.globeCentre.y * scale)
        return ImageFactory.backdrop(pixelSize: px, theme: theme, globeCentre: centre,
                                     globeRadius: layout.globeRadius * scale, scale: scale)
    }

    // MARK: - Panel

    private func refreshPanel(now: Date = Date()) {
        guard let layout, layout.panelAnchor != nil else {
            panelView.isHidden = true
            return
        }
        let scale = backingScale
        let t = theme
        let content = InfoContent(model: model, now: now)
        let key = "\(t.isDark)-\(model.style)-\(scale)-\(layout.panelWidth)-\(content.panelCacheKey)"
        if key != panelKey, let out = PanelRenderer.panel(content, theme: t, width: layout.panelWidth, scale: scale) {
            panelKey = key
            panelImage = out.image
            panelSize = out.size
            withoutAnimation {
                panelView.layer?.contents = out.image
                panelView.layer?.contentsScale = scale
            }
        }
        guard let rect = layout.panelRect(size: panelSize) else { return }
        withoutAnimation {
            if panelView.frame != rect { panelView.frame = rect }
            panelView.isHidden = false
        }
    }

    private func withoutAnimation(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }

    // MARK: - Debug

    /// The current frame as the window server would composite it.
    func compositeSnapshot() -> CGImage? {
        let scene = globeView.snapshot().cgImage(forProposedRect: nil, context: nil, hints: nil)
        let panelRect = panelView.isHidden ? nil : panelView.frame
        return WallpaperComposer.compose(viewSize: bounds.size, scale: backingScale,
                                         backdrop: backdrop?.image(), scene: scene, sceneRect: globeView.frame,
                                         panel: panelRect == nil ? nil : panelImage, panelRect: panelRect)
    }
}

extension GlobeLayout {
    /// Where a panel of `size` sits: left edge at the anchor, vertically centred on it.
    func panelRect(size: CGSize) -> CGRect? {
        guard let a = panelAnchor, size.width > 0 else { return nil }
        return CGRect(x: a.x, y: (a.y - size.height / 2).rounded(), width: size.width, height: size.height)
    }
}

/// Flattens the wallpaper's layers into one image (offscreen snapshots and
/// debug captures; on screen, Core Animation does this).
enum WallpaperComposer {
    static func compose(viewSize: CGSize, scale: CGFloat, backdrop: CGImage?,
                        scene: CGImage?, sceneRect: CGRect,
                        panel: CGImage?, panelRect: CGRect?) -> CGImage? {
        ImageFactory.draw(Int(viewSize.width * scale), Int(viewSize.height * scale)) { ctx in
            ctx.scaleBy(x: scale, y: scale)
            if let backdrop {
                ctx.draw(backdrop, in: CGRect(origin: .zero, size: viewSize))
            } else {
                ctx.setFillColor(.black)
                ctx.fill(CGRect(origin: .zero, size: viewSize))
            }
            if let scene { ctx.draw(scene, in: sceneRect) }
            if let panel, let panelRect { ctx.draw(panel, in: panelRect) }
        }
    }
}

/// The static backdrop, drawn straight into an IOSurface that Core Animation
/// displays without copying. (A CGImage as layer contents is held twice:
/// once by the app and once as Core Animation's own copy.)
final class BackdropSurface {
    let surface: IOSurface
    private let width: Int
    private let height: Int

    init?(layout: GlobeLayout, theme: GlobeTheme, scale: CGFloat) {
        let w = Int((layout.viewSize.width * scale).rounded())
        let h = Int((layout.viewSize.height * scale).rounded())
        guard w > 0, h > 0, let surface = IOSurface(properties: [
            .width: w, .height: h, .bytesPerElement: 4,
            .bytesPerRow: IOSurfaceAlignProperty(kIOSurfaceBytesPerRow, w * 4),
            .pixelFormat: 0x4247_5241,   // 'BGRA'
        ]) else { return nil }
        self.surface = surface
        width = w
        height = h

        // Tag the pixels as sRGB so they are colour-matched like any image.
        if let space = CGColorSpace(name: CGColorSpace.sRGB)?.copyPropertyList() {
            IOSurfaceSetValue(surface, kIOSurfaceColorSpace, space)
        }

        surface.lock(options: [], seed: nil)
        defer { surface.unlock(options: [], seed: nil) }
        guard let ctx = context(data: surface.baseAddress, width: w, height: h,
                                bytesPerRow: surface.bytesPerRow) else { return nil }
        let centre = CGPoint(x: layout.globeCentre.x * scale, y: layout.globeCentre.y * scale)
        ImageFactory.drawBackdrop(in: ctx, width: w, height: h, theme: theme, globeCentre: centre,
                                  globeRadius: layout.globeRadius * scale, scale: scale)
    }

    /// A copy of part of the backdrop (pixels, top-left origin), or all of it.
    func image(pixelRect: CGRect? = nil) -> CGImage? {
        let r = (pixelRect ?? CGRect(x: 0, y: 0, width: width, height: height))
            .intersection(CGRect(x: 0, y: 0, width: width, height: height))
        let x = Int(r.minX), y = Int(r.minY), w = Int(r.width), h = Int(r.height)
        guard w > 0, h > 0, let ctx = context(data: nil, width: w, height: h, bytesPerRow: 0),
              let dst = ctx.data else { return nil }

        surface.lock(options: .readOnly, seed: nil)
        defer { surface.unlock(options: .readOnly, seed: nil) }
        let src = surface.baseAddress
        // Row 0 is the top in both buffers, so rows copy straight across.
        for row in 0..<h {
            memcpy(dst + row * ctx.bytesPerRow, src + (y + row) * surface.bytesPerRow + x * 4, w * 4)
        }
        return ctx.makeImage()
    }

    private func context(data: UnsafeMutableRawPointer?, width: Int, height: Int, bytesPerRow: Int) -> CGContext? {
        CGContext(data: data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    }
}

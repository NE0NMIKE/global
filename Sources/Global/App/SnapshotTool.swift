import AppKit
import Metal
import SceneKit

/// Offscreen renderer for checking styles without installing the wallpaper:
///
///   Global --snapshot <output-dir> [--size 1600x1000] [--style dotMatrix] [--light]
///
/// Writes one PNG per style × appearance (or just the requested ones).
enum SnapshotTool {
    static func run(arguments: [String]) -> Int32 {
        guard let i = arguments.firstIndex(of: "--snapshot"), i + 1 < arguments.count else {
            print("usage: Global --snapshot <dir> [--size WxH] [--style name] [--light|--dark] [--daynight] [--tags] [--nopanel] [--time seconds]")
            return 2
        }
        let dir = URL(fileURLWithPath: arguments[i + 1])
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var size = CGSize(width: 1600, height: 1000)
        if let s = value("--size", arguments) {
            let parts = s.split(separator: "x").compactMap { Double($0) }
            if parts.count == 2 { size = CGSize(width: parts[0], height: parts[1]) }
        }
        let styles = value("--style", arguments).flatMap(GlobeStyle.init(rawValue:)).map { [$0] } ?? GlobeStyle.allCases
        var appearances: [Bool] = [true, false]
        if arguments.contains("--light") { appearances = [false] }
        if arguments.contains("--dark") { appearances = [true] }
        let time = value("--time", arguments).flatMap(Double.init) ?? 0

        guard let device = MTLCreateSystemDefaultDevice() else {
            print("No Metal device")
            return 1
        }

        for style in styles {
            for dark in appearances {
                var model = RenderModel()
                model.style = style
                model.isDark = dark
                model.showDayNight = arguments.contains("--daynight")
                model.showGlobeTags = arguments.contains("--tags")
                model.showInfoPanel = !arguments.contains("--nopanel")
                model.me.name = "Alex"
                model.partner.name = "Sam"
                model.sinceDate = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1))
                if arguments.contains("--spin") { model.motion = .spinSettle }

                let name = "\(style.rawValue)-\(dark ? "dark" : "light").png"
                let url = dir.appendingPathComponent(name)
                if render(model: model, size: size, device: device, time: time, to: url) {
                    print("wrote \(url.path)")
                } else {
                    print("failed \(name)")
                }
            }
        }
        return 0
    }

    /// Renders the 1024×1024 app icon: the realistic globe on a dark
    /// continuous-corner tile, in the style of current macOS icons.
    static func renderIcon(to url: URL) -> Int32 {
        guard let device = MTLCreateSystemDefaultDevice() else { return 1 }
        let px: CGFloat = 1024
        var model = RenderModel()
        model.style = .realistic
        model.isDark = true
        model.showInfoPanel = false
        model.globeScale = 0.66

        let globe = GlobeScene()
        globe.device = device
        globe.apply(model)
        let layout = GlobeLayout.compute(viewSize: CGSize(width: px, height: px), globeScale: model.globeScale,
                                         showPanel: false)
        globe.applyLayout(layout)
        globe.scene.background.contents = NSColor.clear
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = globe.scene
        renderer.pointOfView = globe.cameraNode
        globe.update(at: 0, model: model)
        let render = renderer.snapshot(atTime: 1, with: CGSize(width: px, height: px), antialiasingMode: .multisampling4X)

        // Compose: macOS icon grid — 824 pt tile centred in 1024 with a soft shadow.
        guard let icon = ImageFactory.draw(Int(px), Int(px), { ctx in
            let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
            let path = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185).cgPathCompat
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28,
                          color: CGColor(gray: 0, alpha: 0.45))
            ctx.addPath(path)
            ctx.setFillColor(CGColor(gray: 0.02, alpha: 1))
            ctx.fillPath()
            ctx.restoreGState()

            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            let bg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                colors: [CGColor(srgbRed: 0.06, green: 0.08, blue: 0.16, alpha: 1),
                                         CGColor(srgbRed: 0.0, green: 0.0, blue: 0.02, alpha: 1)] as CFArray,
                                locations: [0, 1])!
            ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
            var rng = SeededRandom(seed: 42)
            for _ in 0..<90 {
                let x = 100 + CGFloat(rng.next()) * 824, y = 100 + CGFloat(rng.next()) * 824
                let a = 0.2 + 0.6 * CGFloat(rng.next())
                ctx.setFillColor(CGColor(gray: 1, alpha: a))
                let r = CGFloat(rng.next()) > 0.9 ? 3.0 : 1.8
                ctx.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
            }
            if let cg = render.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: px, height: px))
            }
            ctx.restoreGState()

            // Hairline highlight along the tile edge.
            ctx.addPath(path)
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.14))
            ctx.setLineWidth(3)
            ctx.strokePath()
        }) else { return 1 }

        let rep = NSBitmapImageRep(cgImage: icon)
        guard let png = rep.representation(using: .png, properties: [:]) else { return 1 }
        do { try png.write(to: url) } catch { return 1 }
        print("wrote \(url.path)")
        return 0
    }

    private static func value(_ flag: String, _ args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// Renders one frame the way `WallpaperView` composes it on screen:
    /// static backdrop, the globe scene in its own rect, then the panel.
    private static func render(model: RenderModel, size: CGSize, device: MTLDevice,
                               time: TimeInterval, to url: URL) -> Bool {
        let scale: CGFloat = 2
        let now = Date()
        let layout = GlobeLayout.compute(viewSize: size, globeScale: model.globeScale,
                                         showPanel: model.showInfoPanel)
        let showsPanel = layout.panelAnchor != nil
        let showsTags = TagNodes.isNeeded(model: model, showsPanel: showsPanel)
        let sceneRect = layout.sceneRect(withTags: showsTags)
        let local = layout.local(in: sceneRect)

        let globe = GlobeScene()
        globe.device = device
        globe.apply(model)
        globe.applyLayout(local)
        let backdrop = WallpaperView.backdrop(layout: layout, theme: globe.theme, scale: scale)
        globe.scene.background.contents = backdrop.flatMap {
            WallpaperView.crop($0, to: sceneRect, viewSize: size, scale: scale)
        }

        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = globe.scene
        renderer.pointOfView = globe.cameraNode
        let t = time > 0 ? time : now.timeIntervalSinceReferenceDate
        globe.update(at: t, model: model)
        let tags = TagNodes()
        tags.backingScale = scale
        globe.scene.rootNode.addChildNode(tags.root)
        tags.update(globe: globe, layout: local, model: model, showsPanel: showsPanel, now: now)
        let scene = renderer.snapshot(atTime: 1, with: CGSize(width: sceneRect.width * scale,
                                                              height: sceneRect.height * scale),
                                      antialiasingMode: .multisampling4X)

        let theme = globe.theme
        let panel = showsPanel
            ? PanelRenderer.panel(InfoContent(model: model, now: now), theme: theme, width: layout.panelWidth, scale: scale)
            : nil
        guard let image = WallpaperComposer.compose(
            viewSize: size, scale: scale,
            backdrop: backdrop,
            scene: scene.cgImage(forProposedRect: nil, context: nil, hints: nil), sceneRect: sceneRect,
            panel: panel?.image, panelRect: panel.flatMap { layout.panelRect(size: $0.size) }),
            let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { return false }
        return (try? png.write(to: url)) != nil
    }
}

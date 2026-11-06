import AppKit
import SceneKit
import simd

/// The "[Name] in [City]" marker tags and the distance tag, drawn as flat
/// planes in the 3D scene itself, in front of the globe.
///
/// The camera is orthographic with one world unit = one globe radius, so a
/// screen position maps directly to world x/y. Keeping the tags in SceneKit
/// avoids a separate SpriteKit overlay pass every frame. (The info panel is
/// a static Core Animation layer instead; see `WallpaperView`.)
///
/// Bitmaps are re-rendered only when their text or theme changes; positions
/// are updated every frame on the render thread.
final class TagNodes {
    /// Non-rotating parent; add to the scene's root node.
    let root = SCNNode()
    private let meTag = TagNodes.makeNode()
    private let partnerTag = TagNodes.makeNode()
    private let distanceTag = TagNodes.makeNode()
    private var sizes: [ObjectIdentifier: CGSize] = [:]

    private var content: InfoContent?
    private var contentTime: TimeInterval = 0
    private var renderKey: String?
    private var lastStyle: GlobeStyle?
    private var lastDark: Bool?
    private var lastScale: CGFloat?

    /// Pixels per point for the bitmaps (set from the screen).
    var backingScale: CGFloat = 2

    /// Whether any tag would be visible for this model.
    static func isNeeded(model: RenderModel, showsPanel: Bool) -> Bool {
        model.showGlobeTags || (model.showDistance && !showsPanel)
    }

    init() {
        root.position = SCNVector3(0, 0, 3)   // in front of the globe (radius 1)
        for n in [meTag, partnerTag, distanceTag] { root.addChildNode(n) }
        root.isHidden = true
    }

    private static func makeNode() -> SCNNode {
        let plane = SCNPlane(width: 0.1, height: 0.1)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = NSColor.clear
        m.diffuse.mipFilter = .none
        m.readsFromDepthBuffer = false
        m.writesToDepthBuffer = false
        m.blendMode = .alpha
        plane.materials = [m]
        let node = SCNNode(geometry: plane)
        node.renderingOrder = 100
        node.isHidden = true
        return node
    }

    /// Called every frame on the render thread, with the globe's state lock
    /// held. `layout` is in the scene view's coordinates.
    func update(globe: GlobeScene, layout: GlobeLayout, model: RenderModel, showsPanel: Bool, now: Date) {
        guard TagNodes.isNeeded(model: model, showsPanel: showsPanel), layout.globeRadius > 0 else {
            if !root.isHidden { root.isHidden = true }
            return
        }
        root.isHidden = false
        let theme = globe.theme

        // Refresh text at most every couple of seconds (times change per
        // minute), and only then check whether the bitmaps need redrawing.
        let t = now.timeIntervalSinceReferenceDate
        if content == nil || t - contentTime > 2 || model.style != lastStyle || theme.isDark != lastDark
            || backingScale != lastScale {
            let fresh = InfoContent(model: model, now: now)
            content = fresh
            contentTime = t
            lastStyle = model.style
            lastDark = theme.isDark
            lastScale = backingScale
            let cacheKey = "\(theme.isDark)-\(model.style)-\(backingScale)-\(fresh.tagCacheKey)"
            if cacheKey != renderKey {
                renderTextures(content: fresh, theme: theme)
                renderKey = cacheKey
            }
        }

        // Tags beside each marker, on the side facing away from the other person.
        let mePt = globe.screenPoint(globe.meVector * 1.003, layout: layout)
        let partnerPt = globe.screenPoint(globe.partnerVector * 1.003, layout: layout)
        place(meTag, at: mePt, awayFrom: partnerPt, visible: model.showGlobeTags,
              opacity: globe.facingOpacity(globe.meVector), layout: layout)
        place(partnerTag, at: partnerPt, awayFrom: mePt, visible: model.showGlobeTags,
              opacity: globe.facingOpacity(globe.partnerVector), layout: layout)

        // Distance tag above the top of the arc, only when the panel isn't showing it.
        if model.showDistance && !showsPanel, let size = sizes[ObjectIdentifier(distanceTag)] {
            let apex = globe.screenPoint(globe.arcApex, layout: layout)
            let centre = CGPoint(x: apex.x, y: apex.y + 22)
            position(distanceTag, centre: centre, size: size, layout: layout)
            distanceTag.opacity = CGFloat(globe.facingOpacity(simd_normalize(globe.arcApex)))
            distanceTag.isHidden = false
        } else {
            distanceTag.isHidden = true
        }
    }

    private func place(_ tag: SCNNode, at p: CGPoint, awayFrom other: CGPoint,
                       visible: Bool, opacity: Double, layout: GlobeLayout) {
        guard visible, let size = sizes[ObjectIdentifier(tag)] else { tag.isHidden = true; return }
        let leftSide = p.x < other.x
        let cx = leftSide ? p.x - 16 - size.width / 2 : p.x + 16 + size.width / 2
        position(tag, centre: CGPoint(x: cx, y: p.y), size: size, layout: layout)
        tag.opacity = CGFloat(opacity)
        tag.isHidden = false
    }

    /// Places a tag of `size` points centred on a screen point.
    private func position(_ tag: SCNNode, centre: CGPoint, size: CGSize, layout: GlobeLayout) {
        let r = layout.globeRadius
        // Snap the tag's edge to the pixel grid so the text stays sharp.
        let scale = backingScale
        let left = ((centre.x - size.width / 2) * scale).rounded() / scale
        let bottom = ((centre.y - size.height / 2) * scale).rounded() / scale
        let x = (left + size.width / 2 - layout.globeCentre.x) / r
        let y = (bottom + size.height / 2 - layout.globeCentre.y) / r
        tag.simdPosition = SIMD3<Float>(Float(x), Float(y), 0)
        if let plane = tag.geometry as? SCNPlane {
            let w = size.width / r, h = size.height / r
            if plane.width != w { plane.width = w }
            if plane.height != h { plane.height = h }
        }
    }

    private func renderTextures(content: InfoContent, theme: GlobeTheme) {
        let s = backingScale
        func set(_ node: SCNNode, _ out: PanelRenderer.Output?) {
            guard let out else { sizes[ObjectIdentifier(node)] = nil; return }
            node.geometry?.firstMaterial?.diffuse.contents = out.image
            sizes[ObjectIdentifier(node)] = out.size
        }
        set(meTag, PanelRenderer.tag(content.meTag, colour: theme.meColor, theme: theme, scale: s))
        set(partnerTag, PanelRenderer.tag(content.partnerTag, colour: theme.partnerColor, theme: theme, scale: s))
        let arcColour = theme.meColor.blended(withFraction: 0.5, of: theme.partnerColor) ?? theme.meColor
        set(distanceTag, content.distance.flatMap {
            PanelRenderer.tag(.init(title: "\($0) \(content.distanceUnit)", detail: ""),
                              colour: arcColour, theme: theme, scale: s)
        })
    }
}

extension InfoContent {
    /// Cheap change detector for the tag bitmaps.
    var tagCacheKey: String {
        [meTag.title, meTag.detail, partnerTag.title, partnerTag.detail, distance ?? "", distanceUnit]
            .joined(separator: "|")
    }

    /// Cheap change detector for the panel bitmap.
    var panelCacheKey: String {
        [me.title, me.detail, partner.title, partner.detail, distance ?? "", distanceUnit,
         timeDifference ?? "", footnotes.joined(), String(format: "%.2f", moonPhase)]
            .joined(separator: "|")
    }
}

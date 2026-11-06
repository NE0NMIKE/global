import AppKit
import MetalKit
import SceneKit
import simd

/// Where things sit on screen, in points (origin bottom-left, as AppKit
/// and SceneKit projection use on macOS).
struct GlobeLayout: Equatable {
    var viewSize: CGSize
    var globeCentre: CGPoint
    var globeRadius: CGFloat
    /// Left edge (x) and vertical centre (y) of the info panel; nil when hidden.
    var panelAnchor: CGPoint?
    var panelWidth: CGFloat

    /// Centres the globe + panel composition on screen.
    static func compute(viewSize: CGSize, globeScale: Double, showPanel: Bool) -> GlobeLayout {
        let w = viewSize.width, h = viewSize.height
        var diameter = CGFloat(globeScale) * min(h, w * 0.9)
        let panelWidth: CGFloat = 400
        var gap = max(48, diameter * 0.12)

        guard showPanel else {
            return GlobeLayout(viewSize: viewSize, globeCentre: CGPoint(x: w / 2, y: h / 2),
                               globeRadius: diameter / 2, panelAnchor: nil, panelWidth: panelWidth)
        }
        // Shrink the globe if the composition would not fit the width.
        let maxWidth = w * 0.92
        if diameter + gap + panelWidth > maxWidth {
            diameter = max(120, maxWidth - gap - panelWidth)
            gap = max(32, diameter * 0.1)
        }
        let total = diameter + gap + panelWidth
        let left = (w - total) / 2
        let centre = CGPoint(x: left + diameter / 2, y: h / 2)
        return GlobeLayout(viewSize: viewSize, globeCentre: centre, globeRadius: diameter / 2,
                           panelAnchor: CGPoint(x: left + diameter + gap, y: h / 2),
                           panelWidth: panelWidth)
    }

    /// The part of the view the 3D scene actually needs: the globe, its glow,
    /// markers and arc, plus room for tags when they are shown. Everything
    /// outside this rect is static and drawn once by Core Animation, so the
    /// GPU only redraws a fraction of the screen each frame.
    func sceneRect(withTags: Bool) -> CGRect {
        let r = globeRadius
        let halfW = r * 1.22 + (withTags ? 240 : 0)
        let halfH = r * 1.22 + (withTags ? 70 : 0)
        let rect = CGRect(x: globeCentre.x - halfW, y: globeCentre.y - halfH,
                          width: halfW * 2, height: halfH * 2).integral
        return rect.intersection(CGRect(origin: .zero, size: viewSize))
    }

    /// This layout expressed in the coordinate space of `rect` (for the scene view).
    func local(in rect: CGRect) -> GlobeLayout {
        GlobeLayout(viewSize: rect.size,
                    globeCentre: CGPoint(x: globeCentre.x - rect.minX, y: globeCentre.y - rect.minY),
                    globeRadius: globeRadius, panelAnchor: nil, panelWidth: panelWidth)
    }
}

/// The 3D scene for one display: globe, markers and arc.
///
/// `apply(_:)` makes structural changes and runs on the main thread;
/// `update(at:model:)` runs every frame on SceneKit's render thread and only
/// touches transforms, opacities and shader uniforms.
final class GlobeScene {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    /// Rotating node that holds everything attached to the Earth.
    let earth = SCNNode()

    private let surfaceRoot = SCNNode()
    private let peopleRoot = SCNNode()
    /// Non-rotating decoration (atmosphere glow, limb outline).
    private let fixedRoot = SCNNode()

    private(set) var theme = GlobeTheme.theme(for: .realistic, dark: true)
    private var shadedMaterials: [SCNMaterial] = []
    private var builtStyleKey: String?
    private var builtPeopleKey: String?

    private let motion = MotionController()

    /// Metal device of the renderer, used to share GPU textures between
    /// displays. When nil, textures fall back to images SceneKit uploads itself.
    var device: MTLDevice?

    /// Serialises structural rebuilds (main thread) against per-frame updates
    /// (render thread), which share `shadedMaterials`, markers and vectors.
    let stateLock = NSRecursiveLock()

    /// Marker nodes and their globe-space unit vectors (for labels and fading).
    private(set) var meMarker: SCNNode?
    private(set) var partnerMarker: SCNNode?
    private(set) var meVector = SIMD3<Double>(0, 0, 1)
    private(set) var partnerVector = SIMD3<Double>(0, 0, 1)
    /// Highest point of the arc, in globe space (for the distance tag).
    private(set) var arcApex = SIMD3<Double>(0, 0, 1)

    private var sunCache: (time: TimeInterval, vector: SIMD3<Double>)?
    /// Last uniforms pushed to the shaders; KVC writes are skipped when unchanged.
    private var lastUniforms: (sun: SIMD3<Float>, dayNight: Float)?

    /// Key light used when the real day/night overlay is off (view space).
    private static let keyLight = simd_normalize(SIMD3<Float>(-0.55, 0.42, 0.72))

    init() {
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = 1 / 0.62
        camera.zNear = 1
        camera.zFar = 20
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 10)
        scene.rootNode.addChildNode(cameraNode)

        scene.rootNode.addChildNode(fixedRoot)
        scene.rootNode.addChildNode(earth)
        earth.addChildNode(surfaceRoot)
        earth.addChildNode(peopleRoot)
        // Replaced by the matching crop of the static backdrop (see WallpaperView).
        scene.background.contents = NSColor.black
    }

    // MARK: - Layout

    /// Positions the orthographic camera so the globe lands at `layout.globeCentre`.
    func applyLayout(_ layout: GlobeLayout) {
        guard layout.globeRadius > 0 else { return }
        let worldPerPoint = 1 / Double(layout.globeRadius)
        cameraNode.camera?.orthographicScale = Double(layout.viewSize.height / 2) * worldPerPoint
        let dx = Double(layout.viewSize.width / 2 - layout.globeCentre.x) * worldPerPoint
        let dy = Double(layout.viewSize.height / 2 - layout.globeCentre.y) * worldPerPoint
        cameraNode.position = SCNVector3(dx, dy, 10)
    }

    // MARK: - Structure (main thread)

    func apply(_ model: RenderModel) {
        // Lock order everywhere: SceneKit's transaction lock, then stateLock.
        // The render thread may already hold SceneKit's lock when it calls
        // update(), so taking them in the same order avoids deadlock.
        SCNTransaction.lock()
        stateLock.lock()
        defer {
            stateLock.unlock()
            SCNTransaction.unlock()
        }
        // Night lights are only sampled with the day/night overlay on, so the
        // realistic style is rebuilt (and the texture loaded) only when needed.
        let needsNight = model.style == .realistic && model.showDayNight
        let styleKey = "\(model.style.rawValue)-\(model.isDark)-\(needsNight)"
        if styleKey != builtStyleKey {
            theme = GlobeTheme.theme(for: model.style, dark: model.isDark)
            SCNTransaction.begin()
            SCNTransaction.disableActions = true
            buildSurface(needsNight: needsNight)
            SCNTransaction.commit()
            builtStyleKey = styleKey
            builtPeopleKey = nil
        }

        let peopleKey = "\(model.me.coordinate)-\(model.partner.coordinate)"
        if peopleKey != builtPeopleKey {
            SCNTransaction.begin()
            SCNTransaction.disableActions = true
            buildPeople(me: model.me.coordinate, partner: model.partner.coordinate)
            SCNTransaction.commit()
            builtPeopleKey = peopleKey
        }
    }

    private func buildSurface(needsNight: Bool) {
        surfaceRoot.childNodes.forEach { $0.removeFromParentNode() }
        fixedRoot.childNodes.forEach { $0.removeFromParentNode() }
        shadedMaterials.removeAll()
        lastUniforms = nil

        let t = theme
        let sphere = GeometryFactory.sphere()
        let sphereNode = SCNNode(geometry: sphere)
        surfaceRoot.addChildNode(sphereNode)

        switch t.surface {
        case .photo:
            let m = SCNMaterial()
            m.lightingModel = .blinn
            m.diffuse.contents = Textures.photo(.day, device: device)
            m.emission.contents = needsNight ? Textures.photo(.night, device: device) : NSColor.black
            m.specular.contents = Textures.photo(.water, device: device)
            for p in [m.diffuse, m.emission, m.specular] {
                p.mipFilter = .linear
                p.wrapS = .repeat
                p.maxAnisotropy = 8
            }
            m.shaderModifiers = [.fragment: Shaders.photoEarth]
            m.setValue(vector(t.glow ?? .white), forKey: "rimColor")
            m.setValue(t.isDark ? 0.55 : 0.4, forKey: "rimStrength")
            sphere.materials = [m]
            shadedMaterials.append(m)

        case .dots, .outline, .filled:
            let m = SCNMaterial()
            // Lambert (not constant) so SceneKit provides _surface.normal to the
            // shader; there are no lights, and the shader sets the final colour.
            m.lightingModel = .lambert
            if t.surface == .filled, let mask = Textures.landMask {
                m.diffuse.contents = mask
                m.diffuse.mipFilter = .linear
                m.setValue(1.0, forKey: "useMask")
            } else {
                m.diffuse.contents = NSColor.white
                m.setValue(0.0, forKey: "useMask")
            }
            m.shaderModifiers = [.fragment: Shaders.flatSphere]
            m.setValue(vector(t.ocean), forKey: "oceanColor")
            m.setValue(vector(t.land), forKey: "landColor")
            m.setValue(vector(t.night), forKey: "nightColor")
            m.setValue(t.nightStrength, forKey: "nightStrength")
            sphere.materials = [m]
            shadedMaterials.append(m)
        }

        // Natural Earth data is parsed lazily, only by styles that draw it.
        if t.surface == .outline || t.surface == .filled {
            let land = LandData.shared
            if let g = t.graticule,
               let geo = GeometryFactory.ribbons(GeometryFactory.graticuleLines(), radius: 1.0008,
                                                 width: Double(t.coastWidth) * 0.55) {
                addInk(geo, colour: g)
            }
            if let b = t.borders,
               let geo = GeometryFactory.ribbons(land.borders, radius: 1.0012,
                                                 width: Double(t.coastWidth) * 0.5) {
                addInk(geo, colour: b)
            }
            if t.coastWidth > 0,
               let geo = GeometryFactory.ribbons(land.rings, radius: 1.0016, width: Double(t.coastWidth)) {
                addInk(geo, colour: t.coast)
            }
        }

        if t.surface == .dots, let geo = GeometryFactory.landDots(LandData.shared, dotRadius: 0.0062) {
            let m = SCNMaterial()
            m.lightingModel = .lambert
            m.diffuse.contents = Textures.disc
            m.multiply.contents = t.land
            m.isDoubleSided = true
            m.writesToDepthBuffer = false
            m.blendMode = .alpha
            m.shaderModifiers = [.fragment: Shaders.inkShade]
            m.setValue(vector(t.night), forKey: "nightColor")
            m.setValue(t.nightStrength, forKey: "nightStrength")
            geo.materials = [m]
            shadedMaterials.append(m)
            let node = SCNNode(geometry: geo)
            node.renderingOrder = 5
            surfaceRoot.addChildNode(node)
        }

        // Atmosphere glow: a camera-facing halo just outside the limb.
        if let glow = t.glow {
            let extent: CGFloat = 1.16
            let plane = SCNPlane(width: extent * 2, height: extent * 2)
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = Textures.atmosphere(edge: 1 / extent, falloff: t.isDark ? 30 : 36)
            m.multiply.contents = glow
            m.diffuse.intensity = t.glowStrength
            m.blendMode = t.isDark ? .add : .alpha
            m.writesToDepthBuffer = false
            plane.materials = [m]
            let node = SCNNode(geometry: plane)
            node.renderingOrder = -1
            fixedRoot.addChildNode(node)
        }

        // Thin outline around the sphere.
        if let limb = t.limb, let geo = GeometryFactory.flatRing(radius: 1.0, width: 0.0045) {
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = limb
            m.isDoubleSided = true
            geo.materials = [m]
            fixedRoot.addChildNode(SCNNode(geometry: geo))
        }
    }

    private func addInk(_ geometry: SCNGeometry, colour: NSColor) {
        let m = SCNMaterial()
        m.lightingModel = .lambert
        m.diffuse.contents = colour
        m.isDoubleSided = true
        m.shaderModifiers = [.fragment: Shaders.inkShade]
        m.setValue(vector(theme.night), forKey: "nightColor")
        m.setValue(theme.nightStrength, forKey: "nightStrength")
        geometry.materials = [m]
        shadedMaterials.append(m)
        surfaceRoot.addChildNode(SCNNode(geometry: geometry))
    }

    private func buildPeople(me: GeoCoordinate, partner: GeoCoordinate) {
        peopleRoot.childNodes.forEach { $0.removeFromParentNode() }
        let t = theme

        meVector = GeoMath.unitVector(me)
        partnerVector = GeoMath.unitVector(partner)

        let meNode = makeMarker(at: meVector, colour: t.meColor, phase: 0)
        let partnerNode = makeMarker(at: partnerVector, colour: t.partnerColor, phase: 1.3)
        peopleRoot.addChildNode(meNode)
        peopleRoot.addChildNode(partnerNode)
        meMarker = meNode
        partnerMarker = partnerNode

        // Arc between the two (skipped if they are in the same place).
        let angle = GeoMath.centralAngle(me, partner)
        guard angle > 0.002 else { arcApex = meVector * 1.02; return }
        let lift = Double(t.arcLift) * min(1, angle / 1.2)
        let pts = GeometryFactory.arcPoints(from: me, to: partner, lift: lift)
        arcApex = pts[pts.count / 2]

        switch t.arcStyle {
        case .glow:
            let gradient = Textures.gradient(t.meColor, t.partnerColor)
            for (radius, base, order) in [(0.0042, 0.75, 11), (0.013, 0.16, 10)] {
                guard let geo = GeometryFactory.tube(pts, radius: radius) else { continue }
                let m = SCNMaterial()
                m.lightingModel = .constant
                m.diffuse.contents = gradient
                m.blendMode = t.isDark ? .add : .alpha
                m.writesToDepthBuffer = false
                m.isDoubleSided = false
                m.shaderModifiers = [.fragment: Shaders.arcGlow]
                m.setValue(7.0, forKey: "pulsePeriod")
                m.setValue(base, forKey: "baseLevel")
                geo.materials = [m]
                let node = SCNNode(geometry: geo)
                node.renderingOrder = order
                peopleRoot.addChildNode(node)
            }

        case .dashed:
            guard let geo = GeometryFactory.dashedRibbon(pts, width: 0.0065) else { break }
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = t.meColor.blended(withFraction: 0.5, of: t.partnerColor) ?? t.meColor
            m.isDoubleSided = true
            geo.materials = [m]
            peopleRoot.addChildNode(SCNNode(geometry: geo))
        }
    }

    private func makeMarker(at v: SIMD3<Double>, colour: NSColor, phase: Double) -> SCNNode {
        let node = SCNNode()
        node.simdPosition = SIMD3<Float>(Float(v.x), Float(v.y), Float(v.z)) * 1.003
        // Orient so local +Z is the surface normal (for the tangent ripple).
        node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 0, 1),
                                          to: SIMD3<Float>(Float(v.x), Float(v.y), Float(v.z)))
        let dark = theme.isDark

        switch theme.markerStyle {
        case .glow:
            let core = SCNNode(geometry: SCNSphere(radius: 0.011))
            let cm = SCNMaterial()
            cm.lightingModel = .constant
            cm.diffuse.contents = colour.blended(withFraction: 0.45, of: .white) ?? colour
            core.geometry?.materials = [cm]
            core.renderingOrder = 20
            node.addChildNode(core)

            let halo = SCNNode(geometry: SCNPlane(width: 0.12, height: 0.12))
            let hm = SCNMaterial()
            hm.lightingModel = .constant
            hm.diffuse.contents = Textures.glow
            hm.multiply.contents = colour
            hm.blendMode = dark ? .add : .alpha
            hm.writesToDepthBuffer = false
            hm.readsFromDepthBuffer = false
            halo.geometry?.materials = [hm]
            halo.constraints = [SCNBillboardConstraint()]
            halo.renderingOrder = 19
            node.addChildNode(halo)
            let pulse = SCNAction.sequence([
                .wait(duration: phase),
                .repeatForever(.sequence([
                    .fadeOpacity(to: 0.55, duration: 1.4),
                    .fadeOpacity(to: 1.0, duration: 1.4),
                ])),
            ])
            pulse.timingMode = .easeInEaseOut
            halo.runAction(pulse)

        case .ring:
            let size: CGFloat = 0.058
            let pin = SCNNode(geometry: SCNPlane(width: size, height: size))
            let pm = SCNMaterial()
            pm.lightingModel = .constant
            pm.diffuse.contents = ImageFactory.ringMarker(
                ring: colour, fill: colour.withAlphaComponent(0.22), centre: colour)
            pm.writesToDepthBuffer = false
            pm.readsFromDepthBuffer = false
            pin.geometry?.materials = [pm]
            pin.constraints = [SCNBillboardConstraint()]
            pin.renderingOrder = 20
            node.addChildNode(pin)
        }

        // Ripple: a ring that expands across the surface and fades.
        let ripple = SCNNode(geometry: SCNPlane(width: 0.2, height: 0.2))
        let rm = SCNMaterial()
        rm.lightingModel = .constant
        rm.diffuse.contents = Textures.ring
        rm.multiply.contents = colour
        rm.blendMode = dark ? .add : .alpha
        rm.writesToDepthBuffer = false
        rm.isDoubleSided = true
        ripple.geometry?.materials = [rm]
        ripple.renderingOrder = 18
        ripple.opacity = 0
        node.addChildNode(ripple)
        let grow = SCNAction.group([
            .scale(to: 1, duration: 2.8),
            .sequence([.fadeOpacity(to: 0.75, duration: 0.15), .fadeOut(duration: 2.65)]),
        ])
        grow.timingMode = .easeOut
        ripple.runAction(.sequence([
            .wait(duration: phase),
            .repeatForever(.sequence([.scale(to: 0.1, duration: 0), grow, .wait(duration: 1.2)])),
        ]))

        return node
    }

    // MARK: - Per frame (render thread)

    func update(at time: TimeInterval, model: RenderModel) {
        stateLock.lock()
        defer { stateLock.unlock() }
        let q = motion.orientation(for: model, at: time)
        earth.simdOrientation = q

        // Light direction in view space (camera looks down −Z, no rotation).
        let sun: SIMD3<Float>
        if model.showDayNight {
            let local = subsolarVector(at: time)
            sun = q.act(SIMD3<Float>(Float(local.x), Float(local.y), Float(local.z)))
        } else {
            sun = GlobeScene.keyLight
        }
        // With day/night off the light is fixed in view space, so after the
        // first frame there is nothing to send.
        let dayNight: Float = model.showDayNight ? 1 : 0
        let changed = lastUniforms.map { $0.dayNight != dayNight || simd_distance($0.sun, sun) >= 1e-5 } ?? true
        if changed {
            let sunValue = NSValue(scnVector3: SCNVector3(sun.x, sun.y, sun.z))
            for m in shadedMaterials {
                m.setValue(sunValue, forKey: "sunDir")
                m.setValue(dayNight, forKey: "dayNight")
            }
            lastUniforms = (sun, dayNight)
        }

        // Fade markers out as they turn towards the far side.
        meMarker?.opacity = CGFloat(facingOpacity(meVector, q))
        partnerMarker?.opacity = CGFloat(facingOpacity(partnerVector, q))
    }

    /// 0…1 visibility for a globe-space unit vector under orientation `q`.
    func facingOpacity(_ v: SIMD3<Double>, _ q: simd_quatf? = nil) -> Double {
        let rot = q ?? earth.simdOrientation
        let z = Double(rot.act(SIMD3<Float>(Float(v.x), Float(v.y), Float(v.z))).z)
        let t = min(1, max(0, (z - 0.02) / 0.18))
        return t * t * (3 - 2 * t)
    }

    /// Screen position (points, bottom-left origin) of a globe-space point.
    /// Exact for the orthographic camera, and independent of any renderer.
    func screenPoint(_ v: SIMD3<Double>, layout: GlobeLayout) -> CGPoint {
        let p = earth.simdOrientation.act(SIMD3<Float>(Float(v.x), Float(v.y), Float(v.z)))
        return CGPoint(x: layout.globeCentre.x + CGFloat(p.x) * layout.globeRadius,
                       y: layout.globeCentre.y + CGFloat(p.y) * layout.globeRadius)
    }

    /// World-space position of a globe-space point under the current orientation.
    func worldPosition(_ v: SIMD3<Double>) -> SCNVector3 {
        let p = earth.simdOrientation.act(SIMD3<Float>(Float(v.x), Float(v.y), Float(v.z)))
        return SCNVector3(p.x, p.y, p.z)
    }

    private func subsolarVector(at time: TimeInterval) -> SIMD3<Double> {
        if let c = sunCache, abs(c.time - time) < 20 { return c.vector }
        let v = GeoMath.unitVector(SunPosition.subsolarPoint(at: Date(timeIntervalSinceReferenceDate: time)))
        sunCache = (time, v)
        return v
    }

    /// Colour as a linear-light float3 for shader uniforms (SceneKit shades
    /// in linear space; passing sRGB values directly would wash colours out).
    private func vector(_ c: NSColor) -> NSValue {
        let s = c.usingColorSpace(.sRGB) ?? c
        func lin(_ v: CGFloat) -> CGFloat {
            v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return NSValue(scnVector3: SCNVector3(lin(s.redComponent), lin(s.greenComponent), lin(s.blueComponent)))
    }
}

/// Shared, lazily loaded textures.
///
/// The large photo textures are loaded straight into GPU memory with
/// MetalKit (no decoded CPU copy), shared by every display, and released
/// once no scene uses them.
enum Textures {
    enum Photo: String {
        case day = "Textures/earth-day.jpg"
        case night = "Textures/earth-night.jpg"
        case water = "Textures/earth-water.png"
    }

    static let glow: CGImage? = ImageFactory.radialGlow()
    static let disc: CGImage? = ImageFactory.disc()
    static let ring: CGImage? = ImageFactory.ring()
    /// Static lets are lazy, so this is only built for the silhouette style.
    static let landMask: CGImage? = ImageFactory.landMask(LandData.shared)

    private final class Weak { weak var texture: MTLTexture? }
    private static let photoCache = Locked<[String: Weak]>([:])

    /// GPU texture for a photo, or a plain image if there is no device.
    static func photo(_ photo: Photo, device: MTLDevice?) -> Any? {
        guard let device else { return load(photo.rawValue) }
        let key = "\(device.registryID)-\(photo.rawValue)"
        if let t = photoCache.get()[key]?.texture { return t }
        guard let url = try? ResourceLocator.url(for: photo.rawValue) else {
            Log.error("Missing texture \(photo.rawValue)")
            return nil
        }
        do {
            let texture = try MTKTextureLoader(device: device).newTexture(URL: url, options: [
                .SRGB: true,
                .generateMipmaps: true,
                .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
                .textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue),
            ])
            photoCache.mutate { cache in
                let box = Weak()
                box.texture = texture
                cache[key] = box
            }
            return texture
        } catch {
            Log.error("Texture \(photo.rawValue) failed to load: \(error)")
            return load(photo.rawValue)
        }
    }

    private static let atmosphereCache = Locked<[String: CGImage]>([:])
    static func atmosphere(edge: CGFloat, falloff: CGFloat) -> CGImage? {
        let key = "\(edge)-\(falloff)"
        if let c = atmosphereCache.get()[key] { return c }
        let img = ImageFactory.atmosphere(edge: edge, falloff: falloff)
        if let img { atmosphereCache.mutate { $0[key] = img } }
        return img
    }

    static func gradient(_ a: NSColor, _ b: NSColor) -> CGImage? {
        ImageFactory.horizontalGradient(a, b)
    }

    private static func load(_ path: String) -> NSImage? {
        guard let url = try? ResourceLocator.url(for: path), let img = NSImage(contentsOf: url) else {
            Log.error("Missing texture \(path)")
            return nil
        }
        return img
    }
}

import AppKit
import SceneKit

/// SceneKit view that renders only the globe region of a display (see
/// `GlobeLayout.sceneRect`). The backdrop and info panel around it are static
/// layers owned by `WallpaperView`.
///
/// The view is opaque: its scene background is the exact crop of the backdrop
/// it covers, so it blends seamlessly into the layer around it while glows
/// and halos still blend against real pixels (SceneKit's alpha blending does
/// not produce correct alpha for compositing over a transparent view).
final class GlobeView: SCNView, SCNSceneRendererDelegate {
    let globe = GlobeScene()
    private let tags = TagNodes()

    /// Latest model and layout (in this view's coordinates), readable from
    /// the render thread.
    private let modelBox = Locked(RenderModel())
    private let layoutBox = Locked<GlobeLayout?>(nil)
    /// Whether the info panel is on screen (it shows the distance instead of the arc tag).
    private let showsPanelBox = Locked(false)

    private(set) var isAnimating = true

    // MARK: Adaptive frame rate
    //
    // Most of the time the globe drifts by well under a point per frame, so
    // rendering at the full rate only costs power. The view measures how fast
    // the surface actually moves on screen and renders just fast enough to
    // keep each step below `maxStep`, between `minFrameRate` and the user's
    // chosen rate (which is used in full during spins and transitions).

    static let minFrameRate = 15
    private static let maxStep = 0.6                  // points per frame
    private let maxFrameRateBox = Locked(30)
    private var currentFrameRate = 30                 // main thread
    private var lastOrientation: (time: TimeInterval, q: simd_quatf)?   // render thread
    private var wantedFrameRate = 30                  // render thread
    private var wantedSince: TimeInterval = 0         // render thread

    #if DEBUG
    private var frameCount = 0
    private var frameWindowStart = Date()
    #endif

    init(frame: NSRect, frameRate: Int) {
        super.init(frame: frame, options: [
            SCNView.Option.preferredRenderingAPI.rawValue: NSNumber(value: SCNRenderingAPI.metal.rawValue),
            SCNView.Option.preferLowPowerDevice.rawValue: NSNumber(value: true),
        ])
        globe.device = device
        globe.scene.rootNode.addChildNode(tags.root)
        scene = globe.scene
        pointOfView = globe.cameraNode
        delegate = self
        rendersContinuously = true
        isPlaying = true
        backgroundColor = .black
        allowsCameraControl = false
        isJitteringEnabled = false
        setFrameRate(frameRate)
        updateAntialiasing()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Inputs (main thread)

    func setModel(_ model: RenderModel, showsPanel: Bool) {
        modelBox.set(model)
        showsPanelBox.set(showsPanel)
        globe.apply(model)
        if !isAnimating { refreshStill() }
    }

    /// Sets the layout in this view's own coordinates.
    func setLayout(_ layout: GlobeLayout) {
        guard layout != layoutBox.get() else { return }
        layoutBox.set(layout)
        globe.applyLayout(layout)
        if !isAnimating { refreshStill() }
    }

    /// The piece of the backdrop behind this view, at the screen's pixel density.
    func setBackground(_ image: CGImage?) {
        SCNTransaction.lock()
        globe.scene.background.contents = image ?? NSColor.black
        SCNTransaction.unlock()
        if !isAnimating { refreshStill() }
    }

    /// The user's maximum frame rate.
    func setFrameRate(_ fps: Int) {
        maxFrameRateBox.set(fps)
        applyFrameRate(fps)
    }

    private func applyFrameRate(_ fps: Int) {
        currentFrameRate = fps
        preferredFramesPerSecond = fps
    }

    /// Pauses or resumes animation. When paused the last frame stays on screen.
    func setAnimating(_ on: Bool) {
        guard on != isAnimating else { return }
        isAnimating = on
        isPlaying = on
        rendersContinuously = on
        if !on { refreshStill() }
    }

    /// Re-renders one frame while paused (e.g. to move the day/night line).
    func refreshStill() {
        guard let layout = layoutBox.get() else { return }
        SCNTransaction.lock()
        globe.stateLock.lock()
        updateFrame(layout: layout, now: Date())
        globe.stateLock.unlock()
        SCNTransaction.unlock()
        needsDisplay = true
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        globe.stateLock.lock()
        tags.backingScale = window?.backingScaleFactor ?? 2
        globe.stateLock.unlock()
        updateAntialiasing()
    }

    /// Retina pixels are small enough that 2× MSAA looks the same as 4× at
    /// half the memory and fill cost; standard-density displays keep 4×.
    private func updateAntialiasing() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let mode: SCNAntialiasingMode = scale >= 2 ? .multisampling2X : .multisampling4X
        if antialiasingMode != mode { antialiasingMode = mode }
    }

    // MARK: - SCNSceneRendererDelegate (render thread)

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard let layout = layoutBox.get() else { return }
        // Hold the lock across globe and tags so a main-thread rebuild can't interleave.
        globe.stateLock.lock()
        defer { globe.stateLock.unlock() }
        let now = Date()
        updateFrame(layout: layout, now: now)
        adaptFrameRate(layout: layout, now: now.timeIntervalSinceReferenceDate)

        #if DEBUG
        frameCount += 1
        let elapsed = Date().timeIntervalSince(frameWindowStart)
        if elapsed >= 10 {
            Log.info(String(format: "%@ %.1f fps (target %d)", "\(Int(bounds.width))x\(Int(bounds.height))",
                            Double(frameCount) / elapsed, wantedFrameRate))
            frameCount = 0
            frameWindowStart = Date()
        }
        #endif
    }

    private func updateFrame(layout: GlobeLayout, now: Date) {
        let m = modelBox.get()
        globe.update(at: now.timeIntervalSinceReferenceDate, model: m)
        tags.update(globe: globe, layout: layout, model: m, showsPanel: showsPanelBox.get(), now: now)
    }

    /// Picks the lowest frame rate that keeps on-screen motion smooth.
    private func adaptFrameRate(layout: GlobeLayout, now: TimeInterval) {
        let q = globe.earth.simdOrientation
        defer { lastOrientation = (now, q) }
        guard let last = lastOrientation, now - last.time > 0.001 else { return }

        // Rotation since the last frame (the relative quaternion's vector part
        // is accurate for tiny angles) → fastest surface speed in points/s.
        let relative = q * last.q.inverse
        let angle = 2 * Double(asin(min(1, simd_length(relative.imag))))
        let pointsPerSecond = angle / (now - last.time) * Double(layout.globeRadius)

        let maxRate = maxFrameRateBox.get()
        let minRate = min(GlobeView.minFrameRate, maxRate)
        let needed = pointsPerSecond / GlobeView.maxStep
        // Snap to a few steps so the rate doesn't wander frame to frame.
        let steps = [minRate, 20, 30, 60].filter { $0 >= minRate && $0 <= maxRate }
        let wanted = steps.first { Double($0) >= needed } ?? maxRate

        // Speed up at once; slow down only after a couple of calm seconds.
        if wanted > wantedFrameRate || (wanted < wantedFrameRate && now - wantedSince > 2) {
            wantedFrameRate = wanted
            wantedSince = now
            DispatchQueue.main.async { [weak self] in
                guard let self, self.currentFrameRate != wanted else { return }
                self.applyFrameRate(wanted)
            }
        } else if wanted >= wantedFrameRate {
            wantedSince = now
        }
    }
}

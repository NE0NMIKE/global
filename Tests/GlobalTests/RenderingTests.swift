import AppKit
import Testing
@testable import Global

@Suite struct RenderingTests {
    private func pixels(_ image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return buf
    }

    /// The IOSurface backdrop (shown on screen) and its crops (the scene
    /// view's background) must match the CGImage backdrop exactly, or a seam
    /// would show around the globe.
    @Test func testBackdropSurfaceMatchesImage() throws {
        let theme = GlobeTheme.theme(for: .realistic, dark: true)
        let layout = GlobeLayout.compute(viewSize: CGSize(width: 900, height: 600), globeScale: 0.62, showPanel: true)
        let scale: CGFloat = 2
        let reference = try #require(WallpaperView.backdrop(layout: layout, theme: theme, scale: scale))
        let surface = try #require(BackdropSurface(layout: layout, theme: theme, scale: scale))

        let full = try #require(surface.image())
        #expect(full.width == reference.width && full.height == reference.height)
        #expect(pixels(full) == pixels(reference))

        let rect = layout.sceneRect(withTags: false)
        let crop = try #require(surface.image(pixelRect: WallpaperView.pixelRect(rect, viewSize: layout.viewSize, scale: scale)))
        let refCrop = try #require(WallpaperView.crop(reference, to: rect, viewSize: layout.viewSize, scale: scale))
        #expect(pixels(crop) == pixels(refCrop))
    }

    @Test func testSceneRectContainsGlobeAndGlow() {
        let layout = GlobeLayout.compute(viewSize: CGSize(width: 3440, height: 1440), globeScale: 0.62, showPanel: true)
        let rect = layout.sceneRect(withTags: false)
        let r = layout.globeRadius * 1.16   // atmosphere extent
        #expect(rect.contains(CGRect(x: layout.globeCentre.x - r, y: layout.globeCentre.y - r, width: 2 * r, height: 2 * r)))
        // The panel sits outside the scene view, so it never needs re-rendering.
        let panel = layout.panelRect(size: CGSize(width: layout.panelWidth, height: 300))!
        #expect(!rect.intersects(panel))
        // Local layout puts the globe at the same place on screen.
        let local = layout.local(in: rect)
        #expect(local.globeCentre.x + rect.minX == layout.globeCentre.x)
    }
}

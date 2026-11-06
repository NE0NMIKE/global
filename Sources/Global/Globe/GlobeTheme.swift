import AppKit

/// Everything that varies between globe styles and appearances: palette,
/// surface treatment and typography. The renderer is style-agnostic.
///
/// Every style has a dark variant (globe floating in black space with stars)
/// and a light variant (globe on a soft off-white backdrop, or for Realistic,
/// in front of a giant sun).
struct GlobeTheme {
    /// How the sphere's surface is drawn.
    enum Surface {
        case photo      // NASA day/night textures
        case dots       // land as a dot grid
        case outline    // coastlines and borders as fine lines
        case filled     // solid land silhouettes
    }

    enum ArcStyle { case glow, dashed }
    enum MarkerStyle { case glow, ring }
    enum Typeface { case sans, mono }

    /// What fills the screen behind the globe.
    enum Backdrop {
        case gradient   // `background` → `backgroundEdge` radial gradient
        case sun        // dark space with a giant sun behind the globe
    }

    var surface: Surface
    var isDark: Bool

    // Backdrop
    var backdrop: Backdrop = .gradient
    var background: NSColor              // centre of the backdrop gradient; tints the light panel card
    var backgroundEdge: NSColor          // vignette colour at the screen edges
    var starDensity: CGFloat             // 0 = none

    // Sphere
    var ocean: NSColor
    var land: NSColor                    // fill (filled) or dot colour (dots)
    var coast: NSColor
    var coastWidth: Float                // world units (globe radius = 1)
    var borders: NSColor?                // country borders, nil = hidden
    var graticule: NSColor?              // lat/long grid, nil = hidden
    var limb: NSColor?                   // thin outline around the sphere
    var night: NSColor                   // colour the night side shades towards
    var nightStrength: Float             // 0…1
    var glow: NSColor?                   // atmosphere glow, nil = none
    var glowStrength: CGFloat

    // Markers and arc
    var meColor: NSColor
    var partnerColor: NSColor
    var markerStyle: MarkerStyle
    var arcStyle: ArcStyle
    var arcLift: Float                   // peak height above the surface

    // Typography
    var ink: NSColor
    var inkSecondary: NSColor
    var rule: NSColor                    // divider lines
    var typeface: Typeface

    static func theme(for style: GlobeStyle, dark: Bool) -> GlobeTheme {
        var t: GlobeTheme
        switch style {
        case .realistic: t = dark ? .realisticDark : .realisticLight
        case .dotMatrix: t = dark ? .dotsDark : .dotsLight
        case .lineArt: t = dark ? .linesDark : .linesLight
        case .silhouette: t = dark ? .silhouetteDark : .silhouetteLight
        }
        t.isDark = dark
        return t
    }
}

private func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// MARK: - Shared backdrops and ink

private extension GlobeTheme {
    static func darkBase(surface: Surface) -> GlobeTheme {
        GlobeTheme(
            surface: surface, isDark: true,
            background: rgb(0x07080C), backgroundEdge: rgb(0x000000), starDensity: 1,
            ocean: rgb(0x0B1A33), land: rgb(0x000000), coast: rgb(0x000000), coastWidth: 0,
            borders: nil, graticule: nil, limb: nil,
            night: rgb(0x000000), nightStrength: 1,
            glow: nil, glowStrength: 0,
            meColor: rgb(0xFFBD4D), partnerColor: rgb(0xFF6B9E), markerStyle: .glow,
            arcStyle: .glow, arcLift: 0.10,
            ink: rgb(0xF5F5F7), inkSecondary: rgb(0xF5F5F7, 0.55), rule: rgb(0xFFFFFF, 0.16),
            typeface: .sans)
    }

    static func lightBase(surface: Surface) -> GlobeTheme {
        GlobeTheme(
            surface: surface, isDark: false,
            background: rgb(0xFAFAFA), backgroundEdge: rgb(0xE4E5EA), starDensity: 0,
            ocean: rgb(0xDDE6F0), land: rgb(0x000000), coast: rgb(0x000000), coastWidth: 0,
            borders: nil, graticule: nil, limb: nil,
            night: rgb(0x9AA3B5), nightStrength: 0.5,
            glow: nil, glowStrength: 0,
            meColor: rgb(0xF08C00), partnerColor: rgb(0xE0316E), markerStyle: .ring,
            arcStyle: .dashed, arcLift: 0.03,
            ink: rgb(0x1D1D1F), inkSecondary: rgb(0x1D1D1F, 0.55), rule: rgb(0x000000, 0.12),
            typeface: .sans)
    }
}

// MARK: - Styles

extension GlobeTheme {
    static let realisticDark: GlobeTheme = {
        var t = darkBase(surface: .photo)
        t.glow = rgb(0x5A9EFF); t.glowStrength = 0.65
        t.arcLift = 0.12
        return t
    }()

    static let realisticLight: GlobeTheme = {
        var t = lightBase(surface: .photo)
        t.night = rgb(0x1A2238); t.nightStrength = 0.85
        t.glow = rgb(0x7FB2FF); t.glowStrength = 0.55
        t.markerStyle = .glow; t.arcStyle = .glow; t.arcLift = 0.12
        t.meColor = rgb(0xFFB02E); t.partnerColor = rgb(0xFF4F8B)
        // The panel sits on the sun's disc, so the card takes its warm white.
        t.backdrop = .sun; t.starDensity = 1
        t.background = rgb(0xFFF6E6); t.backgroundEdge = rgb(0x05060B)
        return t
    }()

    static let dotsDark: GlobeTheme = {
        var t = darkBase(surface: .dots)
        t.ocean = rgb(0x0A1120); t.land = rgb(0x5FD6F2)
        t.night = rgb(0x060A14); t.nightStrength = 0.85
        t.glow = rgb(0x2FC4EE); t.glowStrength = 0.45
        t.limb = rgb(0x2A4A66)
        t.typeface = .mono; t.arcLift = 0.14
        return t
    }()

    static let dotsLight: GlobeTheme = {
        var t = lightBase(surface: .dots)
        t.background = rgb(0xE8EBEF); t.backgroundEdge = rgb(0xD2D7DE)   // mist
        t.ocean = rgb(0xEEF1F5); t.land = rgb(0x2E5C8A)
        t.night = rgb(0xC4CCD8); t.nightStrength = 0.6
        t.limb = rgb(0xC9D1DC)
        t.typeface = .mono; t.markerStyle = .glow; t.arcStyle = .glow; t.arcLift = 0.14
        return t
    }()

    static let linesDark: GlobeTheme = {
        var t = darkBase(surface: .outline)
        t.ocean = rgb(0x0C0F1A)
        t.coast = rgb(0x9AA6CC); t.coastWidth = 0.0028
        t.borders = rgb(0x39425F); t.graticule = rgb(0x1F2539)
        t.limb = rgb(0xE9C58F)
        t.night = rgb(0x06080F); t.nightStrength = 0.75
        t.meColor = rgb(0xF4C27A); t.partnerColor = rgb(0xF4C27A)
        t.arcLift = 0.04
        return t
    }()

    static let linesLight: GlobeTheme = {
        var t = lightBase(surface: .outline)
        t.background = rgb(0xE6E5E2); t.backgroundEdge = rgb(0xD2D1CD)   // stone
        t.ocean = rgb(0xF7F7F8)
        t.coast = rgb(0x2C2E35); t.coastWidth = 0.0026
        t.borders = rgb(0xA5A9B4); t.graticule = rgb(0xDADCE2)
        t.limb = rgb(0x2C2E35)
        t.night = rgb(0xD5D8DF); t.nightStrength = 0.6
        t.meColor = rgb(0x1D1D1F); t.partnerColor = rgb(0x1D1D1F)
        return t
    }()

    static let silhouetteDark: GlobeTheme = {
        var t = darkBase(surface: .filled)
        t.ocean = rgb(0x16181F); t.land = rgb(0xC9C2B4)
        t.coast = rgb(0xDAD4C7); t.coastWidth = 0.0012
        t.limb = rgb(0x3A3D47)
        t.night = rgb(0x0A0B0F); t.nightStrength = 0.8
        t.meColor = rgb(0xF4C27A); t.partnerColor = rgb(0xF4C27A)
        t.arcStyle = .dashed; t.markerStyle = .ring; t.arcLift = 0.03
        return t
    }()

    static let silhouetteLight: GlobeTheme = {
        var t = lightBase(surface: .filled)
        t.ocean = rgb(0xECE7DD); t.land = rgb(0x5B4A3A)
        t.coast = rgb(0x4A3B2E); t.coastWidth = 0.0012
        t.limb = rgb(0xCFC6B6)
        t.night = rgb(0xBDB4A3); t.nightStrength = 0.55
        t.meColor = rgb(0xFFFFFF); t.partnerColor = rgb(0xFFFFFF)
        t.ink = rgb(0x3E3226); t.inkSecondary = rgb(0x3E3226, 0.6); t.rule = rgb(0x3E3226, 0.18)
        t.background = rgb(0xEEEBE5); t.backgroundEdge = rgb(0xDAD5CC)   // paper
        return t
    }()
}

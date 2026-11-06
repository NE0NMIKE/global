import Foundation

/// The visual styles the globe can be drawn in. Each has dark and light variants.
enum GlobeStyle: String, CaseIterable, Codable, Identifiable {
    case realistic
    case dotMatrix
    case lineArt
    case silhouette

    var id: String { rawValue }

    var title: String {
        switch self {
        case .realistic: return "Realistic"
        case .dotMatrix: return "Dot Matrix"
        case .lineArt: return "Line Art"
        case .silhouette: return "Silhouette"
        }
    }

    var symbol: String {
        switch self {
        case .realistic: return "globe.europe.africa.fill"
        case .dotMatrix: return "circle.grid.3x3.fill"
        case .lineArt: return "globe"
        case .silhouette: return "circle.lefthalf.filled"
        }
    }
}

/// Dark = globe in black space; Light = globe on a pale backdrop.
enum AppearanceMode: String, CaseIterable, Codable, Identifiable {
    case system, dark, light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Match System"
        case .dark: return "Dark"
        case .light: return "Light"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .dark: return "moon.fill"
        case .light: return "sun.max.fill"
        }
    }
}

/// How the globe moves.
enum MotionMode: String, CaseIterable, Codable, Identifiable {
    /// Always faces the midpoint between the two people, with a gentle sway.
    case framed
    /// Spins slowly through one full turn, then eases back to frame both people.
    case spinSettle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .framed: return "Framed on Both of You"
        case .spinSettle: return "Spin, Then Settle"
        }
    }

    var symbol: String {
        switch self {
        case .framed: return "scope"
        case .spinSettle: return "arrow.triangle.2.circlepath"
        }
    }
}

/// One of the two people shown on the globe.
struct Person: Equatable {
    var name: String
    var coordinate: GeoCoordinate
    /// Human-readable place, e.g. "Paris". Empty if unknown.
    var city: String
    /// IANA time zone identifier, e.g. "Europe/Paris".
    var timeZoneID: String

    /// "Alex in Paris", or just "Alex" when the city is unknown.
    var title: String {
        city.isEmpty ? name : "\(name) in \(city)"
    }
}

extension Person {
    init(place: Place, name: String) {
        self.init(name: name, coordinate: place.coordinate, city: place.city, timeZoneID: place.timeZoneID)
    }
}

/// Everything the renderer needs for a frame, copied as a value so the
/// SceneKit render thread never touches main-thread objects.
struct RenderModel: Equatable {
    var style: GlobeStyle = .realistic
    var motion: MotionMode = .framed
    // Placeholders until the app is set up (see `AppModel.rebuildModel`).
    var me = Person(place: .placeholderMe, name: "You")
    var partner = Person(place: .placeholderPartner, name: "Partner")
    var showDistance = true
    var showLocalTimes = true
    var showDayNight = false
    var useMiles = false
    var use24Hour = true
    /// Globe diameter as a fraction of the screen height.
    var globeScale: Double = 0.62
    /// Multiplier on all motion speeds (1 = default).
    var motionSpeed: Double = 1
    /// Resolved appearance (system setting already applied).
    var isDark = true
    /// Typographic panel beside the globe (names, distance, time difference).
    var showInfoPanel = true
    /// Small "[Name] in [City]" tags next to the markers on the globe itself.
    var showGlobeTags = false
    /// Optional "Since …" line in the info panel.
    var sinceDate: Date?
}

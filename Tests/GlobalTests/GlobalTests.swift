import Foundation
import Testing
import simd
@testable import Global

@Suite struct GeoMathTests {
    @Test func testParisTokyoDistance() {
        // Great-circle distance is ~9,620 km.
        #expect(isClose(GeoMath.distanceKm(.paris, .tokyo), 9712, 30))
    }

    @Test func testDistanceIsSymmetricAndZeroForSamePoint() {
        #expect(isClose(GeoMath.distanceKm(.paris, .paris), 0, 1e-9))
        #expect(isClose(GeoMath.distanceKm(.paris, .tokyo), GeoMath.distanceKm(.tokyo, .paris), 1e-9))
    }

    @Test func testUnitVectorRoundTrip() {
        for c in [GeoCoordinate.paris, .tokyo, GeoCoordinate(latitude: -33.9, longitude: 151.2),
                  GeoCoordinate(latitude: 0, longitude: 179.9)] {
            let back = GeoMath.coordinate(GeoMath.unitVector(c))
            #expect(isClose(back.latitude, c.latitude, 1e-9))
            #expect(isClose(back.longitude, c.longitude, 1e-9))
        }
    }

    @Test func testOrientationBringsCentreToCamera() {
        // The point we face must end up on +Z (towards the camera) with north up.
        let c = GeoCoordinate(latitude: 37, longitude: 57)
        let q = GeoMath.orientation(facing: c)
        let v = GeoMath.unitVector(c)
        let p = q.act(SIMD3<Float>(Float(v.x), Float(v.y), Float(v.z)))
        #expect(isClose(p.x, 0, 1e-5))
        #expect(isClose(p.y, 0, 1e-5))
        #expect(isClose(p.z, 1, 1e-5))
        // The north pole stays in the upper half.
        let north = q.act(SIMD3<Float>(0, 1, 0))
        #expect(north.y > 0)
        #expect(isClose(north.x, 0, 1e-5))
    }

    @Test func testMidpointIsEquidistant() {
        let mid = GeoMath.midpoint(.paris, .tokyo)
        #expect(isClose(GeoMath.distanceKm(mid, .paris), GeoMath.distanceKm(mid, .tokyo), 1))
    }

    @Test func testRoundingToCityLevel() {
        let r = GeoCoordinate(latitude: 51.5072, longitude: -0.1276).rounded(toPlaces: 1)
        #expect(r.latitude == 51.5)
        #expect(r.longitude == -0.1)
    }

    @Test func testWrapLongitude() {
        #expect(isClose(GeoMath.wrapLongitude(190), -170, 1e-9))
        #expect(isClose(GeoMath.wrapLongitude(-190), 170, 1e-9))
        #expect(isClose(GeoMath.wrapLongitude(45), 45, 1e-9))
    }
}

@Suite struct SunAndMoonTests {
    private func date(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        return f.date(from: s)!
    }

    @Test func testSubsolarLatitudeAtSolstices() {
        // June solstice: sun over the Tropic of Cancer (~23.4°N).
        #expect(isClose(SunPosition.subsolarPoint(at: date("2026-06-21T12:00:00Z")).latitude, 23.4, 0.3))
        // December solstice: Tropic of Capricorn.
        #expect(isClose(SunPosition.subsolarPoint(at: date("2026-12-21T12:00:00Z")).latitude, -23.4, 0.3))
    }

    @Test func testSubsolarLongitudeNearGreenwichAtNoonUTC() {
        // At 12:00 UTC the sun is within a few degrees of 0° (equation of time ≤ ~16 min ≈ 4°).
        let p = SunPosition.subsolarPoint(at: date("2026-03-20T12:00:00Z"))
        #expect(isClose(p.longitude, 0, 4.5))
        #expect(isClose(p.latitude, 0, 0.6))
    }

    @Test func testMoonPhaseKnownFullMoon() {
        // Full moon: 2026-01-03 10:03 UTC.
        #expect(isClose(MoonPhase.phase(at: date("2026-01-03T10:03:00Z")), 0.5, 0.03))
    }
}

@Suite struct InfoContentTests {
    @Test func testTimeDifferenceParisTokyo() {
        let me = Person(name: "Alex", coordinate: .paris, city: "Paris", timeZoneID: "Europe/Paris")
        let her = Person(name: "Sam", coordinate: .tokyo, city: "Tokyo", timeZoneID: "Asia/Tokyo")
        let winter = ISO8601DateFormatter().date(from: "2026-11-05T12:00:00Z")!
        #expect(InfoContent.timeDifference(partner: her, me: me, now: winter) == "Sam is 8 hours ahead")
        let summer = ISO8601DateFormatter().date(from: "2026-07-01T12:00:00Z")!
        #expect(InfoContent.timeDifference(partner: her, me: me, now: summer) == "Sam is 7 hours ahead")
        #expect(InfoContent.timeDifference(partner: me, me: her, now: winter) == "Alex is 8 hours behind")
    }

    @Test func testHalfHourZone() {
        let me = Person(name: "A", coordinate: .paris, city: "", timeZoneID: "UTC")
        let india = Person(name: "B", coordinate: .paris, city: "", timeZoneID: "Asia/Kolkata")
        #expect(InfoContent.timeDifference(partner: india, me: me, now: Date()) == "B is 5½ hours ahead")
    }

    @Test func testTitleFormat() {
        let p = Person(name: "Sam", coordinate: .tokyo, city: "Tokyo", timeZoneID: "Asia/Tokyo")
        #expect(p.title == "Sam in Tokyo")
        var q = p
        q.city = ""
        #expect(q.title == "Sam")
    }
}

@Suite struct LandDataTests {
    @Test func testLandMask() {
        let land = LandData.shared
        #expect(!(land.rings.isEmpty))
        #expect(land.isLand(GeoCoordinate(latitude: 48.8, longitude: 2.3)))     // Paris
        #expect(land.isLand(GeoCoordinate(latitude: -25, longitude: 134)))      // Australia
        #expect(!(land.isLand(GeoCoordinate(latitude: 0, longitude: -30))))       // Atlantic
        #expect(!(land.isLand(GeoCoordinate(latitude: 30, longitude: 160))))      // Pacific
    }
}

/// Floating-point comparison helper.
func isClose<T: BinaryFloatingPoint>(_ a: T, _ b: T, _ tolerance: T) -> Bool {
    abs(a - b) <= tolerance
}

@Suite struct SettingsTests {
    @Test func testPartnerPlacePersists() throws {
        let suite = "GlobalTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(AppSettings(defaults: defaults).partnerPlace == nil)
        let paris = Place(coordinate: GeoCoordinate(latitude: 48.9, longitude: 2.3), city: "Paris",
                          timeZoneID: "Europe/Paris")
        AppSettings(defaults: defaults).partnerPlace = paris
        #expect(AppSettings(defaults: defaults).partnerPlace == paris)
    }
}

@Suite struct CityLookupTests {
    @Test func testDisplayName() {
        #expect(CityLookup.displayName(found: "Macau SAR, China", query: "macau") == "Macau")
        #expect(CityLookup.displayName(found: "Tokyo", query: "tokyo") == "Tokyo")
        #expect(CityLookup.displayName(found: "Paris", query: "Paris, France") == "Paris")
        #expect(CityLookup.displayName(found: "New York", query: "NYC") == "New York")
    }
}

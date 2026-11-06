import Foundation
import simd

/// A latitude/longitude pair in degrees.
struct GeoCoordinate: Codable, Equatable, Hashable {
    var latitude: Double
    var longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Rounded to `places` decimal places (1 ≈ 11 km, 2 ≈ 1.1 km).
    func rounded(toPlaces places: Int) -> GeoCoordinate {
        let f = pow(10.0, Double(places))
        return GeoCoordinate(latitude: (latitude * f).rounded() / f,
                             longitude: (longitude * f).rounded() / f)
    }

    // Placeholder places, shown until the app is set up.
    static let paris = GeoCoordinate(latitude: 48.8566, longitude: 2.3522)
    static let tokyo = GeoCoordinate(latitude: 35.6762, longitude: 139.6503)
}

/// Spherical geometry helpers.
///
/// Globe-space convention (used everywhere in the renderer):
///   x = cos(lat)·sin(lon),  y = sin(lat),  z = cos(lat)·cos(lon)
/// so (0°, 0°) faces +Z (towards the camera when unrotated) and north is +Y.
enum GeoMath {
    static let earthRadiusKm = 6371.0088

    @inline(__always) static func rad(_ deg: Double) -> Double { deg * .pi / 180 }
    @inline(__always) static func deg(_ rad: Double) -> Double { rad * 180 / .pi }

    /// Unit vector in globe space for a coordinate.
    static func unitVector(_ c: GeoCoordinate) -> SIMD3<Double> {
        let lat = rad(c.latitude), lon = rad(c.longitude)
        return SIMD3(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon))
    }

    /// Inverse of `unitVector`.
    static func coordinate(_ v: SIMD3<Double>) -> GeoCoordinate {
        let n = simd_normalize(v)
        return GeoCoordinate(latitude: deg(asin(max(-1, min(1, n.y)))),
                             longitude: deg(atan2(n.x, n.z)))
    }

    /// Central angle between two coordinates, in radians (haversine — stable for small angles).
    static func centralAngle(_ a: GeoCoordinate, _ b: GeoCoordinate) -> Double {
        let φ1 = rad(a.latitude), φ2 = rad(b.latitude)
        let dφ = φ2 - φ1, dλ = rad(b.longitude - a.longitude)
        let h = sin(dφ / 2) * sin(dφ / 2) + cos(φ1) * cos(φ2) * sin(dλ / 2) * sin(dλ / 2)
        return 2 * asin(min(1, sqrt(h)))
    }

    /// Great-circle distance in kilometres.
    static func distanceKm(_ a: GeoCoordinate, _ b: GeoCoordinate) -> Double {
        centralAngle(a, b) * earthRadiusKm
    }

    /// Point along the great circle from `a` to `b` at fraction `t` (unit vectors, slerp).
    static func slerp(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ t: Double) -> SIMD3<Double> {
        let d = max(-1, min(1, simd_dot(a, b)))
        let ω = acos(d)
        if ω < 1e-6 { return a }
        if abs(ω - .pi) < 1e-6 {
            // Antipodal: any great circle works; pick one through the poles-ish axis.
            let axis = simd_normalize(simd_cross(a, abs(a.y) < 0.9 ? SIMD3(0, 1, 0) : SIMD3(1, 0, 0)))
            let q = simd_quatd(angle: ω * t, axis: axis)
            return q.act(a)
        }
        let s = sin(ω)
        return (sin((1 - t) * ω) / s) * a + (sin(t * ω) / s) * b
    }

    /// Great-circle midpoint of two coordinates.
    static func midpoint(_ a: GeoCoordinate, _ b: GeoCoordinate) -> GeoCoordinate {
        coordinate(slerp(unitVector(a), unitVector(b), 0.5))
    }

    /// Orientation for the globe node such that `centre` faces +Z (the camera)
    /// with north kept upright: R = Rx(lat) · Ry(−lon).
    static func orientation(facing centre: GeoCoordinate) -> simd_quatf {
        let ry = simd_quatf(angle: Float(-rad(centre.longitude)), axis: SIMD3(0, 1, 0))
        let rx = simd_quatf(angle: Float(rad(centre.latitude)), axis: SIMD3(1, 0, 0))
        return rx * ry
    }

    /// Wraps a longitude into −180…180.
    static func wrapLongitude(_ lon: Double) -> Double {
        var l = lon.truncatingRemainder(dividingBy: 360)
        if l > 180 { l -= 360 }
        if l < -180 { l += 360 }
        return l
    }
}

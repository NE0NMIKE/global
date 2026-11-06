import Foundation
import simd

/// Computes the globe's orientation for any moment.
///
/// Motion is a pure function of wall-clock time, so every display shows the
/// same orientation without coordination. Changes of mode, people or speed
/// are smoothed by slerping from the previous orientation over a short blend.
final class MotionController {
    // Tunables (seconds at speed 1).
    static let swayPeriodLon = 48.0
    static let swayPeriodLat = 71.0
    static let swayAmplitudeLon = 7.0     // degrees
    static let swayAmplitudeLat = 2.5     // degrees
    static let spinDuration = 150.0       // one full turn
    static let holdDuration = 35.0        // framed pause between turns
    static let blendDuration = 2.5

    private struct Key: Equatable {
        var motion: MotionMode
        var a: GeoCoordinate
        var b: GeoCoordinate
        var speed: Double
    }

    private var key: Key?
    private var last: simd_quatf?
    private var blendFrom: simd_quatf?
    private var blendStart: TimeInterval = 0

    /// Orientation for the globe node at `time` (seconds since reference date).
    func orientation(for model: RenderModel, at time: TimeInterval) -> simd_quatf {
        let k = Key(motion: model.motion, a: model.me.coordinate, b: model.partner.coordinate,
                    speed: model.motionSpeed)
        if k != key {
            if key != nil, let last { blendFrom = last; blendStart = time }
            key = k
        }

        var q = MotionController.target(for: model, at: time)

        if let from = blendFrom {
            let p = min(1, (time - blendStart) / MotionController.blendDuration)
            let e = Float(p * p * (3 - 2 * p))
            q = simd_slerp(from, q, e)
            if p >= 1 { blendFrom = nil }
        }
        last = q
        return q
    }

    /// The point the camera frames: great-circle midpoint, pulled towards the
    /// equator a little so the poles don't dominate the view.
    static func framingCentre(_ a: GeoCoordinate, _ b: GeoCoordinate) -> GeoCoordinate {
        var mid = GeoMath.midpoint(a, b)
        mid.latitude *= 0.8
        return mid
    }

    static func target(for model: RenderModel, at time: TimeInterval) -> simd_quatf {
        let speed = max(0.05, model.motionSpeed)
        let t = time * speed
        let centre = framingCentre(model.me.coordinate, model.partner.coordinate)

        switch model.motion {
        case .framed:
            let lon = centre.longitude + swayAmplitudeLon * sin(2 * .pi * t / swayPeriodLon)
            let lat = centre.latitude + swayAmplitudeLat * sin(2 * .pi * t / swayPeriodLat)
            return GeoMath.orientation(facing: GeoCoordinate(latitude: lat, longitude: lon))

        case .spinSettle:
            let cycle = spinDuration + holdDuration
            let phase = t.truncatingRemainder(dividingBy: cycle)
            if phase < spinDuration {
                // One full eastward turn; zero velocity at both ends.
                let p = phase / spinDuration
                let eased = p - sin(2 * .pi * p) / (2 * .pi)
                // The view's centre longitude decreases as the Earth turns eastward.
                let lon = centre.longitude - 360 * eased
                // Dip towards a lower latitude mid-spin for a more classic view.
                let lat = centre.latitude + (18 - centre.latitude) * 0.5 * sin(.pi * p)
                return GeoMath.orientation(facing: GeoCoordinate(latitude: lat, longitude: lon))
            } else {
                // Framed hold with a sway that starts and ends at rest.
                let h = (phase - spinDuration) / holdDuration
                let lon = centre.longitude + 5 * sin(2 * .pi * h) * sin(.pi * h)
                return GeoMath.orientation(facing: GeoCoordinate(latitude: centre.latitude, longitude: lon))
            }
        }
    }
}

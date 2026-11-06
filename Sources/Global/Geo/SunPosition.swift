import Foundation

/// Approximate subsolar point (where the sun is directly overhead).
///
/// Uses the NOAA low-precision solar position equations — accurate to a
/// fraction of a degree, which is far more than a wallpaper needs.
enum SunPosition {
    static func subsolarPoint(at date: Date) -> GeoCoordinate {
        // Days since J2000.0 (2000-01-01 12:00 UTC).
        let jd = date.timeIntervalSince1970 / 86400 + 2440587.5
        let n = jd - 2451545.0

        // Mean longitude and mean anomaly of the sun (degrees).
        let L = (280.460 + 0.9856474 * n).truncatingRemainder(dividingBy: 360)
        let g = GeoMath.rad((357.528 + 0.9856003 * n).truncatingRemainder(dividingBy: 360))

        // Ecliptic longitude and obliquity.
        let λ = GeoMath.rad(L + 1.915 * sin(g) + 0.020 * sin(2 * g))
        let ε = GeoMath.rad(23.439 - 0.0000004 * n)

        // Declination = latitude of the subsolar point.
        let declination = asin(sin(ε) * sin(λ))

        // Right ascension → equation of time → subsolar longitude.
        let α = atan2(cos(ε) * sin(λ), cos(λ))
        var eqTimeDeg = L - GeoMath.deg(α) // degrees; 1° = 4 min
        eqTimeDeg = eqTimeDeg.truncatingRemainder(dividingBy: 360)
        if eqTimeDeg > 180 { eqTimeDeg -= 360 }
        if eqTimeDeg < -180 { eqTimeDeg += 360 }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = cal.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let utcHours = Double(comps.hour ?? 0)
            + Double(comps.minute ?? 0) / 60
            + (Double(comps.second ?? 0) + Double(comps.nanosecond ?? 0) / 1e9) / 3600

        let lon = GeoMath.wrapLongitude(-15 * (utcHours - 12) - eqTimeDeg)
        return GeoCoordinate(latitude: GeoMath.deg(declination), longitude: lon)
    }
}

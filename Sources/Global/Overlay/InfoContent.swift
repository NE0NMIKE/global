import Foundation

/// The text shown in the info panel and on-globe tags, derived from the
/// render model at a given moment. Pure value — easy to compare and test.
struct InfoContent: Equatable {
    struct Line: Equatable {
        var title: String       // "Alex in Paris"
        var detail: String      // local time, "14:32" (empty when hidden)
    }

    var me: Line
    var partner: Line
    var distance: String?       // "9,630"
    var distanceUnit: String    // "km"
    var timeDifference: String? // "Sam is 8 hours ahead"
    var footnotes: [String]     // ["Since January 2026"]
    var moonPhase: Double       // 0 = new, 0.5 = full

    /// Tag text next to each marker.
    var meTag: Line
    var partnerTag: Line

    init(model: RenderModel, now: Date) {
        func time(_ p: Person) -> String {
            Format.localTime(now, timeZoneID: p.timeZoneID, use24Hour: model.use24Hour)
        }
        func detail(_ p: Person) -> String {
            model.showLocalTimes ? time(p) : ""
        }

        me = Line(title: model.me.title, detail: detail(model.me))
        partner = Line(title: model.partner.title, detail: detail(model.partner))
        meTag = me
        partnerTag = partner

        if model.showDistance {
            let km = GeoMath.distanceKm(model.me.coordinate, model.partner.coordinate)
            let value = model.useMiles ? km * 0.621371 : km
            let nf = NumberFormatter()
            nf.numberStyle = .decimal
            nf.locale = Locale(identifier: "en_GB")
            nf.maximumFractionDigits = 0
            distance = nf.string(from: NSNumber(value: value.rounded())) ?? "\(Int(value))"
        } else {
            distance = nil
        }
        distanceUnit = model.useMiles ? "mi" : "km"

        if model.showLocalTimes {
            timeDifference = InfoContent.timeDifference(partner: model.partner, me: model.me, now: now)
        } else {
            timeDifference = nil
        }

        var foot: [String] = []
        if let since = model.sinceDate {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_GB")
            df.dateFormat = "MMMM yyyy"
            foot.append("Since \(df.string(from: since))")
        }
        footnotes = foot

        moonPhase = MoonPhase.phase(at: now)
    }

    /// "Sam is 8 hours ahead", "Sam is 5½ hours behind", "Same time zone".
    static func timeDifference(partner: Person, me: Person, now: Date) -> String {
        let tzP = TimeZone(identifier: partner.timeZoneID) ?? .current
        let tzM = TimeZone(identifier: me.timeZoneID) ?? .current
        let diff = tzP.secondsFromGMT(for: now) - tzM.secondsFromGMT(for: now)
        if diff == 0 { return "Same time zone" }
        let hours = Double(abs(diff)) / 3600
        let whole = Int(hours)
        let frac = hours - Double(whole)
        var number = "\(whole)"
        if abs(frac - 0.5) < 0.01 { number += "½" }
        else if abs(frac - 0.75) < 0.01 { number += "¾" }
        else if abs(frac - 0.25) < 0.01 { number += "¼" }
        let unit = (hours == 1) ? "hour" : "hours"
        return "\(partner.name) is \(number) \(unit) \(diff > 0 ? "ahead" : "behind")"
    }
}

/// Lunar phase from a reference new moon and the mean synodic month.
enum MoonPhase {
    static let synodicMonth = 29.530588853
    /// 2000-01-06 18:14 UTC.
    static let referenceNewMoon = Date(timeIntervalSince1970: 947182440)

    /// 0 = new, 0.25 = first quarter, 0.5 = full, 0.75 = last quarter.
    static func phase(at date: Date) -> Double {
        let days = date.timeIntervalSince(referenceNewMoon) / 86400
        let p = (days / synodicMonth).truncatingRemainder(dividingBy: 1)
        return p < 0 ? p + 1 : p
    }

    static func name(_ p: Double) -> String {
        switch p {
        case ..<0.03, 0.97...: return "New Moon"
        case ..<0.22: return "Waxing Crescent"
        case ..<0.28: return "First Quarter"
        case ..<0.47: return "Waxing Gibbous"
        case ..<0.53: return "Full Moon"
        case ..<0.72: return "Waning Gibbous"
        case ..<0.78: return "Last Quarter"
        default: return "Waning Crescent"
        }
    }
}

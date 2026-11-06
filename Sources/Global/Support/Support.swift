import Foundation
import os

/// Thin wrapper over unified logging. View with:
///   log stream --predicate 'subsystem == "io.github.ne0nmike.global"'
enum Log {
    private static let logger = Logger(subsystem: "io.github.ne0nmike.global", category: "app")

    static func info(_ message: String) { logger.info("\(message, privacy: .public)") }
    static func error(_ message: String) { logger.error("\(message, privacy: .public)") }
    static func debug(_ message: String) { logger.debug("\(message, privacy: .public)") }
}

/// Finds bundled resources whether running as a packaged `.app`
/// (`Contents/Resources`) or straight from the repo via `swift run`.
enum ResourceLocator {
    enum Failure: Error { case notFound(String) }

    static func url(for relativePath: String) throws -> URL {
        let fm = FileManager.default
        var candidates: [URL] = []
        if let res = Bundle.main.resourceURL {
            candidates.append(res.appendingPathComponent(relativePath))
        }
        // `swift run` / `.build/<config>/Global` → walk up to the repo root.
        var dir = Bundle.main.executableURL?.deletingLastPathComponent()
        for _ in 0..<5 {
            guard let d = dir else { break }
            candidates.append(d.appendingPathComponent("Resources").appendingPathComponent(relativePath))
            dir = d.deletingLastPathComponent()
        }
        candidates.append(URL(fileURLWithPath: fm.currentDirectoryPath)
            .appendingPathComponent("Resources").appendingPathComponent(relativePath))

        if let hit = candidates.first(where: { fm.fileExists(atPath: $0.path) }) { return hit }
        throw Failure.notFound(relativePath)
    }
}

/// A tiny lock-protected box for values shared between the main thread and
/// SceneKit's render thread.
final class Locked<Value> {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) { self.value = value }

    func get() -> Value {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func set(_ newValue: Value) {
        lock.lock(); defer { lock.unlock() }
        value = newValue
    }

    func mutate(_ body: (inout Value) -> Void) {
        lock.lock(); defer { lock.unlock() }
        body(&value)
    }
}

/// Human-friendly formatting shared by the overlay and menus.
enum Format {
    /// "51.5°N 0.1°W".
    static func coordinates(_ c: GeoCoordinate) -> String {
        let lat = String(format: "%.1f°%@", abs(c.latitude), c.latitude >= 0 ? "N" : "S")
        let lon = String(format: "%.1f°%@", abs(c.longitude), c.longitude >= 0 ? "E" : "W")
        return "\(lat) \(lon)"
    }

    static func distance(km: Double, useMiles: Bool) -> String {
        let value = useMiles ? km * 0.621371 : km
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = 0
        nf.locale = Locale(identifier: "en_GB")
        let number = nf.string(from: NSNumber(value: value.rounded())) ?? "\(Int(value))"
        return "\(number) \(useMiles ? "mi" : "km") apart"
    }

    /// "14:32", or "Thu 06:32" when the day differs from the viewer's.
    static func localTime(_ date: Date, timeZoneID: String, use24Hour: Bool = true) -> String {
        let tz = TimeZone(identifier: timeZoneID) ?? .current
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_GB")
        df.timeZone = tz
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let theirDay = cal.component(.day, from: date)
        let myDay = Calendar.current.component(.day, from: date)
        let time = use24Hour ? "HH:mm" : "h:mm a"
        df.dateFormat = theirDay == myDay ? time : "EEE \(time)"
        return df.string(from: date)
    }
}

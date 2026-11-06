import Combine
import CoreLocation
import Foundation

/// A rounded, human-labelled location for this Mac.
struct Place: Codable, Equatable {
    var coordinate: GeoCoordinate
    var city: String
    var timeZoneID: String
}

/// Wraps Core Location for a Mac: coarse accuracy, rounded to city level
/// (1 decimal place ≈ 11 km) before anything else sees it, then reverse
/// geocoded to a city name and time zone. Nothing leaves this Mac.
///
/// Macs locate via nearby Wi-Fi, so fixes only arrive while awake and online.
/// The last known place is persisted and shown in the meantime.
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    /// Decimal places kept when rounding (1 = city level, as agreed).
    static let precision = 1

    @Published private(set) var place: Place?
    @Published private(set) var authorization: CLAuthorizationStatus
    @Published private(set) var lastError: String?

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var refreshTimer: Timer?
    private var isRunning = false
    private static let storeKey = "lastPlace"

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.distanceFilter = 2000
        if let data = UserDefaults.standard.data(forKey: Self.storeKey),
           let saved = try? JSONDecoder().decode(Place.self, from: data) {
            place = saved
        }
    }

    var isAuthorised: Bool {
        authorization == .authorizedAlways || authorization == .authorized
    }

    var authorisationDescription: String {
        switch authorization {
        case .notDetermined: return "Not requested yet"
        case .restricted: return "Restricted"
        case .denied: return "Denied"
        case .authorizedAlways, .authorized: return "Allowed"
        @unknown default: return "Unknown"
        }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        if manager.authorizationStatus == .notDetermined {
            // On macOS the permission prompt is reliably triggered by starting
            // updates; request explicitly as well for newer systems.
            manager.requestWhenInUseAuthorization()
            manager.startUpdatingLocation()
        }
        beginUpdates()
        // Wi-Fi positioning doesn't push updates often; ask periodically too.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            guard let self, self.isAuthorised else { return }
            self.manager.requestLocation()
        }
    }

    func stop() {
        isRunning = false
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func requestNow() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
            manager.startUpdatingLocation()
        } else if isAuthorised {
            manager.requestLocation()
        }
    }

    private func beginUpdates() {
        guard isAuthorised else { return }
        manager.startUpdatingLocation()
        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            manager.startMonitoringSignificantLocationChanges()
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorization = manager.authorizationStatus
            if self.isRunning { self.beginUpdates() }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last, loc.horizontalAccuracy >= 0 else { return }
        let raw = GeoCoordinate(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
        let rounded = raw.rounded(toPlaces: Self.precision)
        DispatchQueue.main.async { self.handle(rounded: rounded, original: loc) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // kCLErrorLocationUnknown is transient (e.g. offline); keep the last place.
        let code = (error as? CLError)?.code
        if code == .locationUnknown { return }
        let message: String
        switch code {
        case .denied:
            message = "Location access is off for Global. Turn it on in System Settings › Privacy & Security › Location Services (and check Location Services itself is on)."
        case .network:
            message = "No network connection — will retry when online."
        default:
            message = error.localizedDescription
        }
        DispatchQueue.main.async {
            self.lastError = message
            self.authorization = manager.authorizationStatus
        }
        Log.error("Location error: \(error.localizedDescription)")
    }

    // MARK: - Geocoding

    private func handle(rounded: GeoCoordinate, original: CLLocation) {
        lastError = nil
        let movedFar = place.map { GeoMath.distanceKm($0.coordinate, rounded) > 8 } ?? true
        if !movedFar, let current = place, !current.city.isEmpty {
            // Same city: keep the name, just take the new coordinate.
            if current.coordinate != rounded {
                var p = current
                p.coordinate = rounded
                publish(p)
            }
            return
        }
        // Geocode the *original* fix for a better city name; only the rounded
        // coordinate is ever stored.
        geocoder.cancelGeocode()
        geocoder.reverseGeocodeLocation(original) { [weak self] placemarks, error in
            DispatchQueue.main.async {
                guard let self else { return }
                let mark = placemarks?.first
                let city = mark?.locality ?? mark?.subAdministrativeArea ?? mark?.administrativeArea ?? ""
                let tz = mark?.timeZone?.identifier ?? TimeZone.current.identifier
                if let error { Log.error("Geocode failed: \(error.localizedDescription)") }
                self.publish(Place(coordinate: rounded, city: city, timeZoneID: tz))
            }
        }
    }

    private func publish(_ p: Place) {
        place = p
        if let data = try? JSONEncoder().encode(p) {
            UserDefaults.standard.set(data, forKey: Self.storeKey)
        }
    }
}

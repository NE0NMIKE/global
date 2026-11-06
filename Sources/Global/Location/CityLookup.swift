import CoreLocation

extension Place {
    // Shown until the app is set up and this Mac has found its location.
    static let placeholderMe = Place(coordinate: .paris, city: "Paris", timeZoneID: "Europe/Paris")
    static let placeholderPartner = Place(coordinate: .tokyo, city: "Tokyo", timeZoneID: "Asia/Tokyo")
}

/// Turns a typed city name ("Tokyo", "Paris, France") into a place with
/// coordinates and a time zone, using Apple's geocoder. Needs a network
/// connection but no Location permission.
enum CityLookup {
    enum Failure: LocalizedError {
        case notFound(String)
        case offline

        var errorDescription: String? {
            switch self {
            case .notFound(let query): return "Couldn’t find “\(query)”. Try adding the country."
            case .offline: return "Couldn’t reach Apple’s map service. Check the connection and try again."
            }
        }
    }

    static func place(for query: String) async throws -> Place {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let marks: [CLPlacemark]
        do {
            marks = try await CLGeocoder().geocodeAddressString(trimmed)
        } catch let error as CLError where error.code == .network {
            throw Failure.offline
        } catch {
            throw Failure.notFound(trimmed)
        }
        guard let mark = marks.first, let loc = mark.location else { throw Failure.notFound(trimmed) }
        let found = mark.locality ?? mark.subAdministrativeArea ?? mark.administrativeArea ?? mark.name ?? trimmed
        let city = displayName(found: found, query: trimmed)
        let coordinate = GeoCoordinate(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
        return Place(coordinate: coordinate.rounded(toPlaces: LocationService.precision), city: city,
                     timeZoneID: mark.timeZone?.identifier ?? TimeZone.current.identifier)
    }

    /// Apple sometimes returns a longer name than people use ("Macau SAR,
    /// China" for "macau"). If the result starts with what was typed
    /// (before any comma), keep just that part, in the result's capitalisation.
    static func displayName(found: String, query: String) -> String {
        let typed = query.split(separator: ",").first.map {
            $0.trimmingCharacters(in: .whitespaces)
        } ?? ""
        guard !typed.isEmpty, found.count > typed.count,
              found.lowercased().hasPrefix(typed.lowercased()) else { return found }
        return String(found.prefix(typed.count))
    }
}

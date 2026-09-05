import CoreLocation
import Foundation
import MapKit
import Observation

/// A hospital found live through Maps, rather than from the curated list.
struct NearbyHospital: Identifiable, Hashable {
    let id: String
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    let distance: CLLocationDistance?
    let phone: String?

    static func == (lhs: NearbyHospital, rhs: NearbyHospital) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var mapItem: MKMapItem {
        let placemark = MKPlacemark(coordinate: coordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = name
        return item
    }
}

/// Searches Apple Maps for hospitals around the user.
///
/// This is the trustworthy half of the Care screen: results, addresses and
/// phone numbers come from Maps' live database rather than from anything typed
/// into this repository, so they stay correct as places move and change.
@MainActor
@Observable
final class NearbyHospitalSearch {
    enum State: Equatable {
        case idle
        case searching
        case results([NearbyHospital])
        case empty
        case needsPermission
        case failed(String)
    }

    private(set) var state: State = .idle

    func search(around location: CLLocation?) async {
        guard let location else {
            state = .needsPermission
            return
        }
        state = .searching

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "hospital"
        request.resultTypes = [.pointOfInterest]
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.hospital])
        request.region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 15_000,
            longitudinalMeters: 15_000
        )

        do {
            let response = try await MKLocalSearch(request: request).start()
            let found = response.mapItems.compactMap { item -> NearbyHospital? in
                guard let name = item.name else { return nil }
                let coordinate = item.placemark.coordinate
                let itemLocation = CLLocation(latitude: coordinate.latitude,
                                              longitude: coordinate.longitude)
                return NearbyHospital(
                    id: "\(name)|\(coordinate.latitude),\(coordinate.longitude)",
                    name: name,
                    address: Self.address(from: item.placemark),
                    coordinate: coordinate,
                    distance: itemLocation.distance(from: location),
                    phone: item.phoneNumber
                )
            }
            .sorted { ($0.distance ?? .greatestFiniteMagnitude) < ($1.distance ?? .greatestFiniteMagnitude) }

            state = found.isEmpty ? .empty : .results(Array(found.prefix(25)))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private static func address(from placemark: MKPlacemark) -> String {
        [placemark.thoroughfare, placemark.subLocality, placemark.locality]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

enum MapsLauncher {
    /// Opens turn-by-turn directions to a coordinate.
    static func directions(to item: MKMapItem) {
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }

    /// Opens Maps searching for a place by name — used for the curated list,
    /// where no coordinate is stored on purpose.
    static func search(query: String) -> URL? {
        var components = URLComponents(string: "http://maps.apple.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }
}

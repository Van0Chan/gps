import Foundation
import MapKit

/// Spôsob prepojenia bodov pri plánovaní trasy.
enum PlannerMode: String, CaseIterable, Identifiable {
    case straight, driving, walking
    var id: String { rawValue }
    var title: String {
        switch self {
        case .straight: return "Priamo"
        case .driving: return "Po cestách"
        case .walking: return "Pešo"
        }
    }
    var systemImage: String {
        switch self {
        case .straight: return "line.diagonal"
        case .driving: return "car"
        case .walking: return "figure.walk"
        }
    }
}

enum RoutePlanner {
    /// Spojí body trasy – priamymi čiarami alebo podľa ciest (Apple Mapy).
    static func build(waypoints: [CLLocationCoordinate2D], mode: PlannerMode) async throws -> [CLLocationCoordinate2D] {
        guard waypoints.count > 1, mode != .straight else { return waypoints }
        var result: [CLLocationCoordinate2D] = []
        for (a, b) in zip(waypoints, waypoints.dropFirst()) {
            try Task.checkCancellation()
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: a))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: b))
            request.transportType = mode == .walking ? .walking : .automobile
            do {
                let response = try await MKDirections(request: request).calculate()
                if let route = response.routes.first {
                    var segment = route.polyline.allCoordinates
                    if !result.isEmpty, !segment.isEmpty { segment.removeFirst() }
                    result.append(contentsOf: segment)
                    continue
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Ak sa úsek nedá nájsť (more, bez ciest...), spojíme ho priamo.
            }
            if result.isEmpty { result.append(a) }
            result.append(b)
        }
        return result
    }

    /// Vyhľadanie miesta podľa názvu/adresy.
    static func search(_ query: String, near region: MKCoordinateRegion?) async -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let region { request.region = region }
        return (try? await MKLocalSearch(request: request).start().mapItems) ?? []
    }
}

extension MKPolyline {
    var allCoordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}

import Foundation
import CoreLocation

/// Štatistiky trasy: dĺžka, čas, rýchlosti a prevýšenie.
struct RouteStats {
    var distance: CLLocationDistance = 0
    var duration: TimeInterval?
    var averageSpeed: Double?
    var maxSpeed: Double?
    var elevationGain: Double = 0
    var elevationLoss: Double = 0
    var minAltitude: Double?
    var maxAltitude: Double?
    var pointCount: Int = 0

    init(points: [TrackPoint]) {
        pointCount = points.count
        guard points.count > 1 else {
            minAltitude = points.first?.altitude
            maxAltitude = points.first?.altitude
            return
        }

        var maxSpd: Double = 0
        var hasSpeed = false
        var lastAltitude: Double?

        for (index, point) in points.enumerated() {
            if let alt = point.altitude {
                minAltitude = min(minAltitude ?? alt, alt)
                maxAltitude = max(maxAltitude ?? alt, alt)
                if let last = lastAltitude {
                    let diff = alt - last
                    // Malé výkyvy (šum GPS) ignorujeme.
                    if abs(diff) >= 1 {
                        if diff > 0 { elevationGain += diff } else { elevationLoss -= diff }
                        lastAltitude = alt
                    }
                } else {
                    lastAltitude = alt
                }
            }

            if let s = point.speed {
                hasSpeed = true
                maxSpd = max(maxSpd, s)
            }

            guard index > 0 else { continue }
            let previous = points[index - 1]
            let segment = previous.location.distance(from: point.location)
            distance += segment

            if !hasSpeed, let t0 = previous.timestamp, let t1 = point.timestamp {
                let dt = t1.timeIntervalSince(t0)
                if dt > 0 { maxSpd = max(maxSpd, segment / dt) }
            }
        }

        if let start = points.first?.timestamp, let end = points.last?.timestamp {
            let total = end.timeIntervalSince(start)
            if total > 0 {
                duration = total
                averageSpeed = distance / total
                maxSpeed = maxSpd > 0 ? maxSpd : nil
            }
        } else if hasSpeed {
            maxSpeed = maxSpd
        }
    }
}

enum Geo {
    /// Azimut (0–360°) z bodu a do bodu b.
    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let deg = atan2(y, x) * 180 / .pi
        return (deg + 360).truncatingRemainder(dividingBy: 360)
    }

    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    static func interpolate(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, _ t: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: a.latitude + (b.latitude - a.latitude) * t,
            longitude: a.longitude + (b.longitude - a.longitude) * t
        )
    }

    static func totalDistance(_ coords: [CLLocationCoordinate2D]) -> Double {
        guard coords.count > 1 else { return 0 }
        return zip(coords, coords.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }
}

import Foundation
import CoreLocation

/// Jeden bod trasy (nahratý, naplánovaný alebo importovaný z GPX).
struct TrackPoint: Codable, Hashable {
    var latitude: Double
    var longitude: Double
    var altitude: Double?
    var timestamp: Date?
    var speed: Double?

    init(latitude: Double, longitude: Double, altitude: Double? = nil, timestamp: Date? = nil, speed: Double? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.timestamp = timestamp
        self.speed = speed
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    init(_ location: CLLocation) {
        self.init(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: location.verticalAccuracy >= 0 ? location.altitude : nil,
            timestamp: location.timestamp,
            speed: location.speed >= 0 ? location.speed : nil
        )
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}

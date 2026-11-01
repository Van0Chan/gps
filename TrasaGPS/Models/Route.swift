import Foundation
import SwiftData
import CoreLocation

enum RouteKind: String, Codable, CaseIterable {
    case recorded, planned, imported

    var title: String {
        switch self {
        case .recorded: return "Nahratá"
        case .planned: return "Naplánovaná"
        case .imported: return "Importovaná"
        }
    }

    var systemImage: String {
        switch self {
        case .recorded: return "record.circle"
        case .planned: return "point.topleft.down.to.point.bottomright.curvepath"
        case .imported: return "square.and.arrow.down"
        }
    }
}

@Model
final class Route {
    var name: String
    var createdAt: Date
    var kindRaw: String
    var pointsData: Data
    /// Uložená vzdialenosť v metroch (pre rýchle zobrazenie v zozname).
    var distance: Double

    init(name: String, kind: RouteKind, points: [TrackPoint], createdAt: Date = .now) {
        self.name = name
        self.createdAt = createdAt
        self.kindRaw = kind.rawValue
        self.pointsData = (try? JSONEncoder().encode(points)) ?? Data()
        self.distance = RouteStats(points: points).distance
    }

    var kind: RouteKind {
        RouteKind(rawValue: kindRaw) ?? .imported
    }

    var points: [TrackPoint] {
        get { (try? JSONDecoder().decode([TrackPoint].self, from: pointsData)) ?? [] }
        set {
            pointsData = (try? JSONEncoder().encode(newValue)) ?? Data()
            distance = RouteStats(points: newValue).distance
        }
    }

    var coordinates: [CLLocationCoordinate2D] {
        points.map(\.coordinate)
    }
}

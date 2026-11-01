import Foundation
import CoreLocation

enum UnitSystem: String, CaseIterable, Identifiable {
    case metric, imperial
    var id: String { rawValue }
    var title: String { self == .metric ? "Metrické (km, km/h)" : "Imperiálne (mi, mph)" }
}

enum Fmt {
    static func distance(_ meters: Double, _ units: UnitSystem) -> String {
        switch units {
        case .metric:
            return meters < 1000 ? String(format: "%.0f m", meters) : String(format: "%.2f km", meters / 1000)
        case .imperial:
            let feet = meters * 3.28084
            return feet < 1000 ? String(format: "%.0f ft", feet) : String(format: "%.2f mi", meters / 1609.344)
        }
    }

    static func speed(_ metersPerSecond: Double?, _ units: UnitSystem) -> String {
        guard let mps = metersPerSecond, mps >= 0 else { return "–" }
        switch units {
        case .metric: return String(format: "%.1f km/h", mps * 3.6)
        case .imperial: return String(format: "%.1f mph", mps * 2.236936)
        }
    }

    static func altitude(_ meters: Double?, _ units: UnitSystem) -> String {
        guard let m = meters else { return "–" }
        switch units {
        case .metric: return String(format: "%.0f m", m)
        case .imperial: return String(format: "%.0f ft", m * 3.28084)
        }
    }

    static func duration(_ seconds: TimeInterval?) -> String {
        guard let s = seconds, s.isFinite, s >= 0 else { return "–" }
        let total = Int(s.rounded())
        let h = total / 3600, m = (total % 3600) / 60, sec = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }

    static func coordinate(_ c: CLLocationCoordinate2D) -> String {
        String(format: "%.6f, %.6f", c.latitude, c.longitude)
    }

    /// Prevod rýchlosti zadanej v km/h alebo mph (podľa jednotiek) na m/s.
    static func toMetersPerSecond(_ value: Double, _ units: UnitSystem) -> Double {
        units == .metric ? value / 3.6 : value / 2.236936
    }

    static func fromMetersPerSecond(_ mps: Double, _ units: UnitSystem) -> Double {
        units == .metric ? mps * 3.6 : mps * 2.236936
    }

    static func speedUnit(_ units: UnitSystem) -> String { units == .metric ? "km/h" : "mph" }
}

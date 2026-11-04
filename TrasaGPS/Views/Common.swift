import SwiftUI
import MapKit

enum SettingsKey {
    static let units = "units"
    static let mapStyle = "mapStyle"
    static let simSpeedKmh = "simSpeedKmh"
    static let simLoop = "simLoop"
    static let simPingPong = "simPingPong"
    static let maxAccuracy = "maxAccuracy"
    static let minPointDistance = "minPointDistance"
}

enum MapStyleOption: String, CaseIterable, Identifiable {
    case standard, hybrid, imagery
    var id: String { rawValue }
    var title: String {
        switch self {
        case .standard: return "Štandardná"
        case .hybrid: return "Hybridná"
        case .imagery: return "Satelitná"
        }
    }
    var mapStyle: MapStyle {
        switch self {
        case .standard: return .standard(elevation: .realistic)
        case .hybrid: return .hybrid(elevation: .realistic)
        case .imagery: return .imagery(elevation: .realistic)
        }
    }
}

/// Spoločné spustenie simulácie z ľubovoľnej obrazovky.
@MainActor
enum SimulationLauncher {
    static func start(points: [TrackPoint], name: String, simulator: RouteSimulator, appState: AppState) {
        let defaults = UserDefaults.standard
        let kmh = defaults.double(forKey: SettingsKey.simSpeedKmh)
        simulator.load(points: points, name: name)
        simulator.speed = (kmh > 0 ? kmh : 5) / 3.6
        simulator.loop = defaults.bool(forKey: SettingsKey.simLoop)
        simulator.pingPong = defaults.bool(forKey: SettingsKey.simPingPong)
        simulator.play()
        appState.selectedTab = .map
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var systemImage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .font(.caption2)
            .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Značka simulovanej polohy so smerom pohybu.
struct SimulatedMarker: View {
    let heading: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(.orange.opacity(0.25))
                .frame(width: 44, height: 44)
            Circle()
                .fill(.orange)
                .frame(width: 22, height: 22)
                .overlay(Circle().stroke(.white, lineWidth: 3))
            Image(systemName: "location.north.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(heading))
        }
        .shadow(radius: 3)
    }
}

struct WaypointMarker: View {
    let number: Int
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        Text("\(number)")
            .font(.caption.bold())
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(Circle().fill(isFirst ? Color.green : isLast ? Color.red : Color.blue))
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(radius: 2)
    }
}

extension View {
    /// Spodný panel – na iOS 26+ v štýle Liquid Glass.
    func panelStyle() -> some View {
        self
            .padding(14)
            .glassBackground(in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
    }

    /// Liquid Glass na iOS 26+, inak systémový materiál.
    @ViewBuilder
    func glassBackground<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
    }
}

/// Tab bar sa pri posúvaní zmenší (iOS 26+ Liquid Glass).
struct TabBarMinimizeOnScroll: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}

import SwiftUI
import SwiftData

@main
struct TrasaGPSApp: App {
    @State private var appState = AppState()
    @State private var location = LocationManager()
    @State private var simulator = RouteSimulator()
    @State private var device = DeviceLocationController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(location)
                .environment(simulator)
                .environment(device)
                .onAppear {
                    device.onKeepAliveChange = { [location] enabled in
                        location.setBackgroundKeepAlive(enabled)
                    }
                }
                // Simulácia trasy sa posiela aj do celého iPhonu (ak je pripojený).
                .onChange(of: simulator.traveled) {
                    device.followSimulation(simulator.currentCoordinate)
                }
        }
        .modelContainer(for: Route.self)
    }
}

/// Zdieľaný stav aplikácie (napr. aktívna záložka).
@MainActor
@Observable
final class AppState {
    enum Tab: Hashable { case map, planner, routes, settings }
    var selectedTab: Tab = .map
}

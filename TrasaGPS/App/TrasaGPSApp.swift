import SwiftUI
import SwiftData

@main
struct TrasaGPSApp: App {
    @State private var appState = AppState()
    @State private var location = LocationManager()
    @State private var simulator = RouteSimulator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(location)
                .environment(simulator)
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

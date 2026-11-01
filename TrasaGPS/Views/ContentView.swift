import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @State private var openError: String?

    var body: some View {
        @Bindable var appState = appState
        TabView(selection: $appState.selectedTab) {
            LiveMapView()
                .tabItem { Label("Mapa", systemImage: "map") }
                .tag(AppState.Tab.map)
            PlannerView()
                .tabItem { Label("Plánovač", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                .tag(AppState.Tab.planner)
            RoutesListView()
                .tabItem { Label("Trasy", systemImage: "list.bullet") }
                .tag(AppState.Tab.routes)
            SettingsView()
                .tabItem { Label("Nastavenia", systemImage: "gearshape") }
                .tag(AppState.Tab.settings)
        }
        // Otvorenie .gpx súboru z aplikácie Súbory / zdieľania
        .onOpenURL { url in
            do {
                _ = try GPXImporter.importFile(at: url, into: context)
                appState.selectedTab = .routes
            } catch {
                openError = error.localizedDescription
            }
        }
        .alert("Import zlyhal", isPresented: Binding(get: { openError != nil }, set: { if !$0 { openError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(openError ?? "")
        }
    }
}

enum GPXImporter {
    @MainActor
    @discardableResult
    static func importFile(at url: URL, into context: ModelContext) throws -> Route {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let parsed = try GPX.parse(data: data)
        let name = parsed.name ?? url.deletingPathExtension().lastPathComponent
        let route = Route(name: name, kind: .imported, points: parsed.points)
        context.insert(route)
        try? context.save()
        return route
    }
}

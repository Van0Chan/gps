import SwiftUI
import SwiftData

/// Zoznam uložených trás + import GPX.
struct RoutesListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Route.createdAt, order: .reverse) private var routes: [Route]
    @AppStorage(SettingsKey.units) private var unitsRaw = UnitSystem.metric.rawValue

    @State private var searchText = ""
    @State private var kindFilter: RouteKind?
    @State private var showImporter = false
    @State private var importError: String?

    private var units: UnitSystem { UnitSystem(rawValue: unitsRaw) ?? .metric }

    private var filtered: [Route] {
        routes.filter { route in
            (kindFilter == nil || route.kind == kindFilter)
            && (searchText.isEmpty || route.name.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if routes.isEmpty {
                    ContentUnavailableView {
                        Label("Žiadne trasy", systemImage: "map")
                    } description: {
                        Text("Nahraj trasu na mape, naplánuj ju v Plánovači alebo importuj súbor GPX.")
                    } actions: {
                        Button("Importovať GPX") { showImporter = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(filtered) { route in
                            NavigationLink(value: route) {
                                RouteRow(route: route, units: units)
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { context.delete(filtered[index]) }
                            try? context.save()
                        }
                    }
                    .overlay {
                        if filtered.isEmpty { ContentUnavailableView.search }
                    }
                }
            }
            .navigationTitle("Trasy")
            .navigationDestination(for: Route.self) { RouteDetailView(route: $0) }
            .searchable(text: $searchText, prompt: "Hľadať trasu")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Filter", selection: $kindFilter) {
                            Text("Všetky").tag(RouteKind?.none)
                            ForEach(RouteKind.allCases, id: \.self) { kind in
                                Label(kind.title, systemImage: kind.systemImage).tag(RouteKind?.some(kind))
                            }
                        }
                    } label: {
                        Image(systemName: kindFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showImporter = true } label: { Label("Import GPX", systemImage: "square.and.arrow.down") }
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.gpx, .xml], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
                    var errors: [String] = []
                    for url in urls {
                        do { try GPXImporter.importFile(at: url, into: context) }
                        catch { errors.append("\(url.lastPathComponent): \(error.localizedDescription)") }
                    }
                    if !errors.isEmpty { importError = errors.joined(separator: "\n") }
                case .failure(let error):
                    importError = error.localizedDescription
                }
            }
            .alert("Import zlyhal", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
        }
    }
}

private struct RouteRow: View {
    let route: Route
    let units: UnitSystem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: route.kind.systemImage)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(route.name).font(.headline).lineLimit(1)
                Text("\(route.kind.title) · \(route.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Fmt.distance(route.distance, units))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

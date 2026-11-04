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
            RouteThumbnail(points: route.points)
                .frame(width: 52, height: 52)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: route.kind.systemImage)
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Color.accentColor, in: Circle())
                        .offset(x: 4, y: 4)
                }
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

/// Malý náhľad tvaru trasy pre zoznam.
struct RouteThumbnail: View {
    let points: [TrackPoint]

    var body: some View {
        Canvas { context, size in
            let coords = Self.sampled(points)
            guard coords.count > 1,
                  let minLat = coords.map(\.latitude).min(), let maxLat = coords.map(\.latitude).max(),
                  let minLon = coords.map(\.longitude).min(), let maxLon = coords.map(\.longitude).max()
            else { return }
            let inset: CGFloat = 8
            let w = size.width - inset * 2, h = size.height - inset * 2
            // Zachováme pomer strán (približne korigovaný na zemepisnú šírku).
            let lonScale = cos(((minLat + maxLat) / 2) * .pi / 180)
            let spanX = max((maxLon - minLon) * lonScale, 1e-9)
            let spanY = max(maxLat - minLat, 1e-9)
            let scale = min(w / spanX, h / spanY)
            let offX = inset + (w - spanX * scale) / 2
            let offY = inset + (h - spanY * scale) / 2
            func point(_ c: TrackPoint) -> CGPoint {
                CGPoint(x: offX + (c.longitude - minLon) * lonScale * scale,
                        y: offY + (maxLat - c.latitude) * scale)
            }
            var path = Path()
            path.move(to: point(coords[0]))
            for c in coords.dropFirst() { path.addLine(to: point(c)) }
            context.stroke(path, with: .color(.accentColor), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            let start = point(coords[0]), end = point(coords[coords.count - 1])
            context.fill(Path(ellipseIn: CGRect(x: start.x - 3, y: start.y - 3, width: 6, height: 6)), with: .color(.green))
            context.fill(Path(ellipseIn: CGRect(x: end.x - 3, y: end.y - 3, width: 6, height: 6)), with: .color(.red))
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private static func sampled(_ points: [TrackPoint]) -> [TrackPoint] {
        let step = max(1, points.count / 120)
        var result = stride(from: 0, to: points.count, by: step).map { points[$0] }
        if let last = points.last, result.last != last { result.append(last) }
        return result
    }
}

import SwiftUI
import MapKit
import SwiftData

/// Plánovanie trasy ťukaním na mapu (priamo alebo po cestách).
struct PlannerView: View {
    @Environment(AppState.self) private var appState
    @Environment(RouteSimulator.self) private var simulator
    @Environment(\.modelContext) private var context

    @AppStorage(SettingsKey.units) private var unitsRaw = UnitSystem.metric.rawValue
    @AppStorage(SettingsKey.mapStyle) private var mapStyleRaw = MapStyleOption.standard.rawValue
    @AppStorage(SettingsKey.simSpeedKmh) private var simSpeedKmh = 5.0

    @State private var waypoints: [TrackPoint] = []
    @State private var path: [CLLocationCoordinate2D] = []
    @State private var mode: PlannerMode = .straight
    @State private var isRouting = false
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var visibleRegion: MKCoordinateRegion?

    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []

    @State private var showSaveAlert = false
    @State private var routeName = ""
    @State private var savedMessage: String?

    private var units: UnitSystem { UnitSystem(rawValue: unitsRaw) ?? .metric }
    private var style: MapStyleOption { MapStyleOption(rawValue: mapStyleRaw) ?? .standard }
    private var distance: Double { Geo.totalDistance(path) }

    private struct RebuildKey: Equatable {
        var waypoints: [TrackPoint]
        var mode: PlannerMode
    }

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                Map(position: $position) {
                    UserAnnotation()

                    if path.count > 1 {
                        MapPolyline(coordinates: path)
                            .stroke(.blue, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    }

                    ForEach(Array(waypoints.enumerated()), id: \.offset) { index, point in
                        Annotation("Bod \(index + 1)", coordinate: point.coordinate) {
                            WaypointMarker(number: index + 1, isFirst: index == 0, isLast: index == waypoints.count - 1 && waypoints.count > 1)
                        }
                        .annotationTitles(.hidden)
                    }

                    ForEach(searchResults, id: \.self) { item in
                        Marker(item: item)
                    }
                }
                .mapStyle(style.mapStyle)
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                    MapScaleView()
                }
                .onMapCameraChange { ctx in visibleRegion = ctx.region }
                .onTapGesture { point in
                    if let coordinate = proxy.convert(point, from: .local) {
                        waypoints.append(TrackPoint(coordinate))
                    }
                }
            }
            .floatingPanel { panel.panelStyle() }
            .navigationTitle("Plánovač trasy")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Hľadať miesto alebo adresu")
            .onSubmit(of: .search) { runSearch() }
            .onChange(of: searchText) { if searchText.isEmpty { searchResults = [] } }
            .task(id: RebuildKey(waypoints: waypoints, mode: mode)) { await rebuild() }
            .alert("Uložiť trasu", isPresented: $showSaveAlert) {
                TextField("Názov trasy", text: $routeName)
                Button("Uložiť") { save() }
                Button("Zrušiť", role: .cancel) {}
            }
            .overlay(alignment: .top) {
                if let savedMessage {
                    Text(savedMessage)
                        .font(.subheadline.bold())
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.green, in: Capsule())
                        .foregroundStyle(.white)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: Panel

    private var panel: some View {
        VStack(spacing: 10) {
            if !searchResults.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(searchResults.prefix(6), id: \.self) { item in
                            Button {
                                waypoints.append(TrackPoint(item.placemark.coordinate))
                                position = .item(item)
                            } label: {
                                Label(item.name ?? "Miesto", systemImage: "plus.circle.fill")
                                    .lineLimit(1)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            Picker("Režim", selection: $mode) {
                ForEach(PlannerMode.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
            }
            .pickerStyle(.segmented)

            HStack {
                StatTile(title: "Body", value: "\(waypoints.count)", systemImage: "mappin.and.ellipse")
                StatTile(title: "Dĺžka", value: Fmt.distance(distance, units), systemImage: "ruler")
                StatTile(title: "Čas (\(Fmt.speed(simSpeedKmh / 3.6, units)))",
                         value: Fmt.duration(simSpeedKmh > 0 ? distance / (simSpeedKmh / 3.6) : nil),
                         systemImage: "clock")
                if isRouting { ProgressView() }
            }

            if waypoints.isEmpty {
                Text("Ťukaním na mapu pridávaj body trasy.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                toolButton("arrow.uturn.backward", "Späť", disabled: waypoints.isEmpty) {
                    _ = waypoints.popLast()
                }
                toolButton("arrow.left.arrow.right", "Obrátiť smer", disabled: waypoints.count < 2) {
                    waypoints.reverse()
                }
                toolButton("arrow.triangle.capsulepath", "Uzavrieť okruh", disabled: waypoints.count < 2) {
                    if let first = waypoints.first { waypoints.append(first) }
                }
                toolButton("trash", "Vymazať body", disabled: waypoints.isEmpty, role: .destructive) {
                    waypoints.removeAll()
                }
                toolButton("square.and.arrow.down", "Uložiť", disabled: path.count < 2) {
                    routeName = "Plán " + Date.now.formatted(date: .abbreviated, time: .shortened)
                    showSaveAlert = true
                }
            }

            Button {
                SimulationLauncher.start(points: path.map { TrackPoint($0) }, name: "Naplánovaná trasa",
                                         simulator: simulator, appState: appState)
            } label: {
                Label("Simulovať trasu", systemImage: "play.fill")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(path.count < 2 || isRouting)
        }
    }

    private func toolButton(_ systemImage: String, _ title: String, disabled: Bool,
                            role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .frame(maxWidth: .infinity, minHeight: 22)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .disabled(disabled)
        .accessibilityLabel(title)
    }

    // MARK: Akcie

    private func rebuild() async {
        let coords = waypoints.map(\.coordinate)
        guard mode != .straight, coords.count > 1 else {
            path = coords
            isRouting = false
            return
        }
        isRouting = true
        do {
            let result = try await RoutePlanner.build(waypoints: coords, mode: mode)
            if !Task.isCancelled { path = result }
        } catch {
            if !Task.isCancelled { path = coords }
        }
        if !Task.isCancelled { isRouting = false }
    }

    private func runSearch() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        Task {
            let items = await RoutePlanner.search(query, near: visibleRegion)
            searchResults = items
            if let first = items.first { position = .item(first) }
        }
    }

    private func save() {
        let name = routeName.trimmingCharacters(in: .whitespaces)
        context.insert(Route(name: name.isEmpty ? "Plán" : name, kind: .planned, points: path.map { TrackPoint($0) }))
        try? context.save()
        withAnimation { savedMessage = "Trasa uložená" }
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation { savedMessage = nil }
        }
    }
}

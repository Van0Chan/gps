import SwiftUI
import MapKit
import SwiftData
import Charts

/// Detail trasy: mapa, štatistiky, výškový profil, simulácia a export.
struct RouteDetailView: View {
    @Bindable var route: Route
    @Environment(AppState.self) private var appState
    @Environment(RouteSimulator.self) private var simulator
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @AppStorage(SettingsKey.units) private var unitsRaw = UnitSystem.metric.rawValue
    @AppStorage(SettingsKey.simSpeedKmh) private var simSpeedKmh = 5.0

    @State private var points: [TrackPoint] = []
    @State private var confirmDelete = false
    @State private var reversedCreated = 0
    @State private var showReversedToast = false

    private var units: UnitSystem { UnitSystem(rawValue: unitsRaw) ?? .metric }

    private struct ProfilePoint: Identifiable {
        let id: Int
        let distance: Double
        let altitude: Double
    }

    private var profile: [ProfilePoint] {
        var result: [ProfilePoint] = []
        var dist = 0.0
        for (i, p) in points.enumerated() {
            if i > 0 { dist += points[i - 1].location.distance(from: p.location) }
            if let alt = p.altitude { result.append(ProfilePoint(id: i, distance: dist, altitude: alt)) }
        }
        // Pre plynulé vykresľovanie stačí rozumný počet bodov.
        let step = max(1, result.count / 400)
        return stride(from: 0, to: result.count, by: step).map { result[$0] }
    }

    var body: some View {
        let stats = RouteStats(points: points)
        let coords = points.map(\.coordinate)

        List {
            Section {
                Map(initialPosition: .automatic) {
                    if coords.count > 1 {
                        MapPolyline(coordinates: coords)
                            .stroke(.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    }
                    if let start = coords.first {
                        Marker("Štart", systemImage: "flag", coordinate: start).tint(.green)
                    }
                    if let end = coords.last, coords.count > 1 {
                        Marker("Cieľ", systemImage: "flag.checkered", coordinate: end).tint(.red)
                    }
                }
                .frame(height: 260)
                .listRowInsets(EdgeInsets())
            }

            Section("Názov") {
                TextField("Názov trasy", text: $route.name)
            }

            Section("Štatistiky") {
                LabeledContent("Dĺžka", value: Fmt.distance(stats.distance, units))
                LabeledContent("Trvanie", value: Fmt.duration(stats.duration))
                LabeledContent("Priemerná rýchlosť", value: Fmt.speed(stats.averageSpeed, units))
                LabeledContent("Maximálna rýchlosť", value: Fmt.speed(stats.maxSpeed, units))
                LabeledContent("Stúpanie", value: "↑ " + Fmt.altitude(stats.elevationGain, units))
                LabeledContent("Klesanie", value: "↓ " + Fmt.altitude(stats.elevationLoss, units))
                LabeledContent("Min. / max. výška", value: "\(Fmt.altitude(stats.minAltitude, units)) / \(Fmt.altitude(stats.maxAltitude, units))")
                LabeledContent("Počet bodov", value: "\(stats.pointCount)")
                LabeledContent("Typ", value: route.kind.title)
                LabeledContent("Vytvorená", value: route.createdAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Simulácia pri \(Fmt.speed(simSpeedKmh / 3.6, units))",
                               value: Fmt.duration(simSpeedKmh > 0 ? stats.distance / (simSpeedKmh / 3.6) : nil))
            }

            let profilePoints = profile
            if profilePoints.count > 1 {
                Section("Výškový profil") {
                    Chart(profilePoints) { p in
                        AreaMark(
                            x: .value("Vzdialenosť", units == .metric ? p.distance / 1000 : p.distance / 1609.344),
                            y: .value("Výška", units == .metric ? p.altitude : p.altitude * 3.28084)
                        )
                        .foregroundStyle(.blue.opacity(0.2))
                        LineMark(
                            x: .value("Vzdialenosť", units == .metric ? p.distance / 1000 : p.distance / 1609.344),
                            y: .value("Výška", units == .metric ? p.altitude : p.altitude * 3.28084)
                        )
                        .foregroundStyle(.blue)
                    }
                    .chartXAxisLabel(units == .metric ? "km" : "mi")
                    .chartYAxisLabel(units == .metric ? "m" : "ft")
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 180)
                }
            }

            Section("Akcie") {
                Button {
                    SimulationLauncher.start(points: points, name: route.name, simulator: simulator, appState: appState)
                } label: {
                    Label("Simulovať trasu", systemImage: "play.fill")
                }
                .disabled(points.count < 2)

                Button {
                    let reversed = Route(name: route.name + " (spiatočná)", kind: route.kind, points: Array(points.reversed()))
                    context.insert(reversed)
                    try? context.save()
                    reversedCreated += 1
                    withAnimation { showReversedToast = true }
                    Task {
                        try? await Task.sleep(for: .seconds(1.8))
                        withAnimation { showReversedToast = false }
                    }
                } label: {
                    Label("Vytvoriť spiatočnú trasu", systemImage: "arrow.uturn.left")
                }
                .disabled(points.count < 2)

                ShareLink(
                    item: GPXDocument(name: route.name, points: points, kind: .track),
                    preview: SharePreview(route.name + ".gpx")
                ) {
                    Label("Exportovať GPX", systemImage: "square.and.arrow.up")
                }

                ShareLink(
                    item: GPXDocument(name: route.name, points: points, kind: .xcode(speed: simSpeedKmh / 3.6)),
                    preview: SharePreview(route.name + " (Xcode).gpx")
                ) {
                    Label("Exportovať pre simuláciu v Xcode", systemImage: "hammer")
                }
            }

            Section {
                Button("Zmazať trasu", role: .destructive) { confirmDelete = true }
                    .confirmationDialog("Naozaj zmazať trasu?", isPresented: $confirmDelete, titleVisibility: .visible) {
                        Button("Zmazať", role: .destructive) {
                            context.delete(route)
                            try? context.save()
                            dismiss()
                        }
                        Button("Zrušiť", role: .cancel) {}
                    }
            }
        }
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { points = route.points }
        .sensoryFeedback(.success, trigger: reversedCreated)
        .overlay(alignment: .top) {
            if showReversedToast {
                Label("Spiatočná trasa vytvorená", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .glassBackground(in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

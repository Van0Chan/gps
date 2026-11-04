import SwiftUI
import MapKit
import SwiftData

/// Hlavná mapa: živá poloha, nahrávanie trasy a ovládanie simulácie.
struct LiveMapView: View {
    @Environment(LocationManager.self) private var location
    @Environment(RouteSimulator.self) private var simulator
    @Environment(DeviceLocationController.self) private var device
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL

    @AppStorage(SettingsKey.units) private var unitsRaw = UnitSystem.metric.rawValue
    @AppStorage(SettingsKey.mapStyle) private var mapStyleRaw = MapStyleOption.standard.rawValue

    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var followSimulation = true
    @State private var showSaveAlert = false
    @State private var pendingPoints: [TrackPoint] = []
    @State private var routeName = ""
    @State private var copied = false
    @State private var showDetails = true
    @State private var mapCenter: CLLocationCoordinate2D?

    private var units: UnitSystem { UnitSystem(rawValue: unitsRaw) ?? .metric }
    private var style: MapStyleOption { MapStyleOption(rawValue: mapStyleRaw) ?? .standard }

    var body: some View {
        Map(position: $position) {
            UserAnnotation()

            if location.recordedPoints.count > 1 {
                MapPolyline(coordinates: location.recordedPoints.map(\.coordinate))
                    .stroke(.red, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }

            if simulator.isActive, simulator.coordinates.count > 1 {
                MapPolyline(coordinates: simulator.coordinates)
                    .stroke(.blue.opacity(0.75), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                if let start = simulator.coordinates.first {
                    Marker("Štart", systemImage: "flag", coordinate: start).tint(.green)
                }
                if let end = simulator.coordinates.last {
                    Marker("Cieľ", systemImage: "flag.checkered", coordinate: end).tint(.red)
                }
            }

            if let spoofed = device.spoofedCoordinate, !simulator.isActive {
                Marker("iPhone", systemImage: "iphone", coordinate: spoofed)
                    .tint(.purple)
            }

            if simulator.isActive, let current = simulator.currentCoordinate {
                Annotation("Simulácia", coordinate: current) {
                    SimulatedMarker(heading: simulator.heading)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(style.mapStyle)
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapPitchToggle()
            MapScaleView()
        }
        .onMapCameraChange { ctx in mapCenter = ctx.region.center }
        .overlay {
            if device.isConnected, !simulator.isActive {
                Image(systemName: "plus")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.purple)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .top) { topBar }
        .floatingPanel { bottomPanel }
        .onAppear { location.requestPermission() }
        .sensoryFeedback(.impact(weight: .medium), trigger: location.isRecording)
        .sensoryFeedback(.success, trigger: device.spoofedCoordinate?.latitude) { _, new in new != nil }
        .onChange(of: simulator.traveled) {
            guard followSimulation, simulator.state == .running, let c = simulator.currentCoordinate else { return }
            position = .camera(MapCamera(centerCoordinate: c, distance: 900))
        }
        .alert("Uložiť trasu", isPresented: $showSaveAlert) {
            TextField("Názov trasy", text: $routeName)
            Button("Uložiť") { saveRecording() }
            Button("Zahodiť", role: .destructive) { pendingPoints = [] }
        } message: {
            Text("\(Fmt.distance(RouteStats(points: pendingPoints).distance, units)) · \(pendingPoints.count) bodov")
        }
    }

    // MARK: Horná lišta

    private var topBar: some View {
        VStack(spacing: 8) {
            if location.isDenied {
                HStack {
                    Image(systemName: "location.slash.fill")
                    Text("Prístup k polohe je vypnutý.")
                        .font(.subheadline)
                    Spacer()
                    Button("Nastavenia") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(12)
                .glassBackground(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            HStack {
                Menu {
                    Picker("Typ mapy", selection: $mapStyleRaw) {
                        ForEach(MapStyleOption.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                } label: {
                    Image(systemName: "square.3.layers.3d")
                        .font(.title3)
                        .padding(10)
                        .glassBackground(in: Circle())
                }
                Spacer()
                if device.spoofedCoordinate != nil {
                    Label("iPhone: simulovaná poloha", systemImage: "iphone.gen3.radiowaves.left.and.right")
                        .font(.caption.bold())
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.purple, in: Capsule())
                        .foregroundStyle(.white)
                }
                if location.isRecording {
                    Label(location.isPaused ? "Pauza" : "Nahrávam", systemImage: location.isPaused ? "pause.circle.fill" : "record.circle")
                        .font(.caption.bold())
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(location.isPaused ? Color.orange : Color.red, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    // MARK: Spodný panel

    private var bottomPanel: some View {
        VStack(spacing: 8) {
            if simulator.isActive {
                SimulationPanel(units: units, follow: $followSimulation)
                    .panelStyle()
            } else {
                livePanel.panelStyle()
            }
        }
    }

    private var livePanel: some View {
        VStack(spacing: 12) {
            if showDetails {
                VStack(spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Aktuálna poloha").font(.caption2).foregroundStyle(.secondary)
                        Text(location.lastLocation.map { Fmt.coordinate($0.coordinate) } ?? "Hľadám GPS…")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button {
                        if let c = location.lastLocation?.coordinate {
                            UIPasteboard.general.string = Fmt.coordinate(c)
                            copied = true
                            Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                        }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .disabled(location.lastLocation == nil)
                }

                HStack {
                    StatTile(title: "Rýchlosť", value: Fmt.speed(location.lastLocation?.speed, units), systemImage: "speedometer")
                    StatTile(title: "Výška", value: Fmt.altitude(location.lastLocation.flatMap { $0.verticalAccuracy >= 0 ? $0.altitude : nil }, units), systemImage: "mountain.2")
                    StatTile(title: "Presnosť", value: location.lastLocation.map { String(format: "±%.0f m", $0.horizontalAccuracy) } ?? "–", systemImage: "scope")
                    StatTile(title: "Smer", value: location.heading.map { String(format: "%.0f°", $0) } ?? "–", systemImage: "safari")
                }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            devicePanel

            if location.isRecording {
                HStack {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        StatTile(title: "Čas", value: Fmt.duration(location.elapsed(at: ctx.date)), systemImage: "timer")
                    }
                    StatTile(title: "Vzdialenosť", value: Fmt.distance(location.recordedDistance, units), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    StatTile(title: "Body", value: "\(location.recordedPoints.count)", systemImage: "mappin.and.ellipse")
                }
                HStack {
                    Button {
                        location.isPaused ? location.resumeRecording() : location.pauseRecording()
                    } label: {
                        Label(location.isPaused ? "Pokračovať" : "Pauza", systemImage: location.isPaused ? "play.fill" : "pause.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        stopRecording()
                    } label: {
                        Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                .controlSize(.large)
            } else {
                HStack {
                    Button {
                        location.startRecording()
                    } label: {
                        Label("Nahrávať trasu", systemImage: "record.circle").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(!location.isAuthorized)

                    Button {
                        withAnimation(.snappy(duration: 0.3)) { showDetails.toggle() }
                    } label: {
                        Image(systemName: showDetails ? "chevron.down" : "chevron.up")
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
            }
        }
    }

    /// Ovládanie polohy celého iPhonu.
    @ViewBuilder
    private var devicePanel: some View {
        if device.isConnected {
            HStack {
                Button {
                    if let c = mapCenter { Task { await device.teleport(to: c) } }
                } label: {
                    Label("Presunúť iPhone sem", systemImage: "scope").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(mapCenter == nil)

                Button {
                    Task { await device.restoreRealLocation() }
                } label: {
                    Image(systemName: "location.slash")
                }
                .buttonStyle(.bordered)
                .disabled(device.spoofedCoordinate == nil)
                .accessibilityLabel("Skutočná poloha")
            }
            .controlSize(.large)
        } else if case .working(let text) = device.status {
            HStack {
                ProgressView()
                Text(text).font(.footnote)
                Spacer()
            }
        } else if device.hasPairingFile {
            if device.waitingForWiFi {
                Label("Spojenie sa obnoví, keď sa pripojíš na Wi-Fi", systemImage: "wifi.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Button {
                Task { await device.connect() }
            } label: {
                Label("Pripojiť iPhone na zmenu polohy", systemImage: "antenna.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.purple)
            if case .failed(let message) = device.status {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
        }
    }

    private func stopRecording() {
        pendingPoints = location.stopRecording()
        guard pendingPoints.count >= 2 else { pendingPoints = []; return }
        routeName = "Trasa " + Date.now.formatted(date: .abbreviated, time: .shortened)
        showSaveAlert = true
    }

    private func saveRecording() {
        let name = routeName.trimmingCharacters(in: .whitespaces)
        context.insert(Route(name: name.isEmpty ? "Trasa" : name, kind: .recorded, points: pendingPoints))
        try? context.save()
        pendingPoints = []
    }
}

/// Ovládanie prebiehajúcej simulácie.
struct SimulationPanel: View {
    @Environment(RouteSimulator.self) private var simulator
    let units: UnitSystem
    @Binding var follow: Bool

    var body: some View {
        @Bindable var sim = simulator
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "location.north.line.fill").foregroundStyle(.orange)
                Text(sim.routeName.isEmpty ? "Simulácia" : sim.routeName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button {
                    sim.stop()
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary)
                }
                .accessibilityLabel("Ukončiť simuláciu")
            }

            Slider(value: Binding(get: { sim.progress }, set: { sim.seek(toProgress: $0) }), in: 0...1)

            HStack {
                Text(Fmt.distance(sim.traveled, units))
                Spacer()
                Text(sim.state == .finished ? "V cieli" : "zostáva \(Fmt.duration(sim.remainingTime))")
                Spacer()
                Text(Fmt.distance(sim.totalDistance, units))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            HStack(spacing: 14) {
                Button { sim.restart() } label: { Image(systemName: "backward.end.fill") }
                    .accessibilityLabel("Na začiatok")

                Button { sim.togglePlay() } label: {
                    Image(systemName: sim.state == .running ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                }
                .accessibilityLabel(sim.state == .running ? "Pauza" : "Spustiť")

                Button { sim.loop.toggle() } label: {
                    Image(systemName: sim.pingPong ? "arrow.left.arrow.right" : "repeat")
                        .foregroundStyle(sim.loop ? Color.accentColor : .secondary)
                }
                .accessibilityLabel("Opakovať")

                Button { follow.toggle() } label: {
                    Image(systemName: follow ? "location.fill" : "location")
                }
                .accessibilityLabel("Sledovať simuláciu")

                Spacer()

                Menu {
                    ForEach(RouteSimulator.Preset.allCases) { preset in
                        Button {
                            sim.speed = preset.kmh / 3.6
                        } label: {
                            Label("\(preset.title) – \(Fmt.speed(preset.kmh / 3.6, units))", systemImage: preset.systemImage)
                        }
                    }
                } label: {
                    Label(Fmt.speed(sim.speed, units), systemImage: "speedometer")
                        .font(.subheadline.monospacedDigit())
                }
            }
            .font(.title3)

            HStack {
                Image(systemName: "tortoise.fill").foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { Fmt.fromMetersPerSecond(sim.speed, units) },
                        set: { sim.speed = Fmt.toMetersPerSecond($0, units) }
                    ),
                    in: 1...200,
                    step: 1
                )
                Image(systemName: "hare.fill").foregroundStyle(.secondary)
            }
        }
    }
}

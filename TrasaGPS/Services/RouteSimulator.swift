import Foundation
import CoreLocation
import Observation

/// Prehrávanie trasy: bod sa pohybuje po trase zvolenou rýchlosťou.
@MainActor
@Observable
final class RouteSimulator {
    enum State { case idle, running, paused, finished }

    enum Preset: String, CaseIterable, Identifiable {
        case walk, run, bike, car, highway
        var id: String { rawValue }
        var title: String {
            switch self {
            case .walk: return "Chôdza"
            case .run: return "Beh"
            case .bike: return "Bicykel"
            case .car: return "Auto"
            case .highway: return "Diaľnica"
            }
        }
        var systemImage: String {
            switch self {
            case .walk: return "figure.walk"
            case .run: return "figure.run"
            case .bike: return "bicycle"
            case .car: return "car.fill"
            case .highway: return "road.lanes"
            }
        }
        /// Rýchlosť v km/h.
        var kmh: Double {
            switch self {
            case .walk: return 5
            case .run: return 10
            case .bike: return 20
            case .car: return 50
            case .highway: return 110
            }
        }
    }

    private(set) var state: State = .idle
    private(set) var routeName: String = ""
    private(set) var coordinates: [CLLocationCoordinate2D] = []
    private(set) var traveled: Double = 0
    private(set) var currentCoordinate: CLLocationCoordinate2D?
    private(set) var heading: Double = 0

    /// Rýchlosť v m/s.
    var speed: Double = 5 / 3.6
    var loop = false
    /// Pri slučke ísť tam a späť namiesto skoku na začiatok.
    var pingPong = false
    private(set) var isReversed = false

    @ObservationIgnored private var cumulative: [Double] = []
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var lastTick: Date?

    var totalDistance: Double { cumulative.last ?? 0 }
    var isActive: Bool { state != .idle }
    var progress: Double { totalDistance > 0 ? traveled / totalDistance : 0 }
    var remainingTime: TimeInterval { speed > 0 ? (totalDistance - traveled) / speed : 0 }

    func load(points: [TrackPoint], name: String) {
        stop()
        coordinates = points.map(\.coordinate)
        routeName = name
        cumulative = [0]
        for (a, b) in zip(coordinates, coordinates.dropFirst()) {
            cumulative.append(cumulative.last! + Geo.distance(a, b))
        }
        traveled = 0
        isReversed = false
        updatePosition()
        state = coordinates.count > 1 ? .paused : .idle
    }

    func play() {
        guard coordinates.count > 1 else { return }
        if state == .finished { traveled = 0; isReversed = false }
        state = .running
        lastTick = .now
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, !Task.isCancelled else { return }
                self.tick()
            }
        }
    }

    func pause() {
        guard state == .running else { return }
        task?.cancel()
        task = nil
        state = .paused
    }

    func togglePlay() {
        state == .running ? pause() : play()
    }

    /// Ukončí simuláciu a zabudne trasu.
    func stop() {
        task?.cancel()
        task = nil
        state = .idle
        coordinates = []
        cumulative = []
        traveled = 0
        currentCoordinate = nil
    }

    func seek(toProgress p: Double) {
        traveled = min(max(p, 0), 1) * totalDistance
        if state == .finished { state = .paused }
        updatePosition()
    }

    func restart() {
        if isReversed {
            // Pri režime tam a späť vrátime trasu do pôvodného smeru.
            coordinates.reverse()
            let total = totalDistance
            cumulative = cumulative.reversed().map { total - $0 }
            isReversed = false
        }
        traveled = 0
        updatePosition()
        if state == .finished { state = .paused }
    }

    private func tick() {
        let now = Date.now
        let dt = now.timeIntervalSince(lastTick ?? now)
        lastTick = now
        traveled += speed * dt

        if traveled >= totalDistance {
            if loop {
                if pingPong {
                    // Otočíme trasu a pokračujeme späť.
                    coordinates.reverse()
                    let total = totalDistance
                    cumulative = cumulative.reversed().map { total - $0 }
                    isReversed.toggle()
                }
                traveled = traveled - totalDistance
            } else {
                traveled = totalDistance
                updatePosition()
                task?.cancel()
                task = nil
                state = .finished
                return
            }
        }
        updatePosition()
    }

    private func updatePosition() {
        guard let first = coordinates.first else { currentCoordinate = nil; return }
        guard coordinates.count > 1 else { currentCoordinate = first; return }
        // Nájdeme úsek, na ktorom sa nachádzame (binárne vyhľadávanie).
        var lo = 0, hi = cumulative.count - 1
        while lo < hi - 1 {
            let mid = (lo + hi) / 2
            if cumulative[mid] <= traveled { lo = mid } else { hi = mid }
        }
        let a = coordinates[lo], b = coordinates[hi]
        let segLen = cumulative[hi] - cumulative[lo]
        let t = segLen > 0 ? (traveled - cumulative[lo]) / segLen : 0
        currentCoordinate = Geo.interpolate(a, b, min(max(t, 0), 1))
        if segLen > 0 { heading = Geo.bearing(from: a, to: b) }
    }
}

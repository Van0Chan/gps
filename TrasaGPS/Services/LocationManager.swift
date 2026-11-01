import Foundation
import CoreLocation
import Observation

/// Živá GPS poloha a nahrávanie trás.
@MainActor
@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    @ObservationIgnored private let manager = CLLocationManager()

    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var lastLocation: CLLocation?
    private(set) var heading: CLLocationDirection?

    // Nahrávanie
    private(set) var isRecording = false
    private(set) var isPaused = false
    private(set) var recordedPoints: [TrackPoint] = []
    private(set) var recordingStart: Date?
    private(set) var recordedDistance: Double = 0
    /// Čas strávený v pauze (nezapočítava sa do trvania).
    @ObservationIgnored private var pausedTotal: TimeInterval = 0
    @ObservationIgnored private var pauseStart: Date?

    /// Body s horšou presnosťou (v metroch) sa nenahrávajú (Nastavenia ▸ Nahrávanie).
    var maxAcceptedAccuracy: Double {
        let v = UserDefaults.standard.double(forKey: SettingsKey.maxAccuracy)
        return v > 0 ? v : 50
    }
    /// Minimálna vzdialenosť medzi nahratými bodmi.
    var minPointDistance: Double {
        let v = UserDefaults.standard.double(forKey: SettingsKey.minPointDistance)
        return v > 0 ? v : 3
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .other
        authorization = manager.authorizationStatus
    }

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    var isDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    func requestPermission() {
        if authorization == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if isAuthorized {
            start()
        }
    }

    func start() {
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
    }

    /// Čisté trvanie nahrávania (bez páuz).
    func elapsed(at date: Date = .now) -> TimeInterval {
        guard let start = recordingStart else { return 0 }
        let currentPause = pauseStart.map { date.timeIntervalSince($0) } ?? 0
        return date.timeIntervalSince(start) - pausedTotal - currentPause
    }

    // MARK: Nahrávanie

    func startRecording() {
        recordedPoints = []
        recordedDistance = 0
        pausedTotal = 0
        pauseStart = nil
        recordingStart = .now
        isPaused = false
        isRecording = true
        updateBackgroundMode()
        if let loc = lastLocation, isGood(loc) { append(loc) }
    }

    func pauseRecording() {
        guard isRecording, !isPaused else { return }
        isPaused = true
        pauseStart = .now
    }

    func resumeRecording() {
        guard isRecording, isPaused else { return }
        if let p = pauseStart { pausedTotal += Date.now.timeIntervalSince(p) }
        pauseStart = nil
        isPaused = false
    }

    /// Ukončí nahrávanie a vráti nahraté body.
    @discardableResult
    func stopRecording() -> [TrackPoint] {
        let points = recordedPoints
        isRecording = false
        isPaused = false
        recordingStart = nil
        pauseStart = nil
        recordedPoints = []
        recordedDistance = 0
        updateBackgroundMode()
        return points
    }

    // MARK: Beh na pozadí

    /// Udržiava aplikáciu na pozadí (napr. počas simulácie polohy celého iPhonu).
    @ObservationIgnored private var backgroundKeepAlive = false

    func setBackgroundKeepAlive(_ enabled: Bool) {
        backgroundKeepAlive = enabled
        updateBackgroundMode()
    }

    private func updateBackgroundMode() {
        let needed = isRecording || backgroundKeepAlive
        manager.allowsBackgroundLocationUpdates = needed
        manager.pausesLocationUpdatesAutomatically = !needed
        manager.showsBackgroundLocationIndicator = needed
        if needed { start() }
    }

    private func isGood(_ loc: CLLocation) -> Bool {
        loc.horizontalAccuracy >= 0 && loc.horizontalAccuracy <= maxAcceptedAccuracy
    }

    private func append(_ loc: CLLocation) {
        if let last = recordedPoints.last {
            let d = last.location.distance(from: loc)
            guard d >= minPointDistance else { return }
            recordedDistance += d
        }
        recordedPoints.append(TrackPoint(loc))
    }

    private func handle(_ locations: [CLLocation]) {
        for loc in locations {
            lastLocation = loc
            if isRecording, !isPaused, isGood(loc) { append(loc) }
        }
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in self.handle(locations) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in self.heading = value }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if self.isAuthorized { self.start() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Dočasné chyby (napr. kCLErrorLocationUnknown) ignorujeme, manager to skúša ďalej.
    }
}

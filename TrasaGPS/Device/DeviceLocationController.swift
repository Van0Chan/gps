import Foundation
import CoreLocation
import Observation

/// Riadi simuláciu polohy celého iPhonu (všetky aplikácie vidia nastavenú polohu).
@MainActor
@Observable
final class DeviceLocationController {
    enum Status: Equatable {
        case idle
        case working(String)
        case connected
        case failed(String)
    }

    static let ipKey = "deviceIP"
    static let followKey = "deviceFollowSimulation"
    static let automaticIP = "auto"

    private(set) var status: Status = .idle
    private(set) var hasPairingFile = false
    private(set) var activeIP: String?
    /// Posledná poloha poslaná do zariadenia (nil = skutočná poloha).
    private(set) var spoofedCoordinate: CLLocationCoordinate2D?

    @ObservationIgnored private let link = DeviceLink()
    @ObservationIgnored private var inFlight = false
    @ObservationIgnored private var queued: CLLocationCoordinate2D?
    @ObservationIgnored private var lastPush = Date.distantPast
    @ObservationIgnored private var keepAliveTask: Task<Void, Never>?
    /// Zavolá sa pri zmene, či má aplikácia bežať na pozadí (kvôli udržaniu spojenia).
    @ObservationIgnored var onKeepAliveChange: ((Bool) -> Void)?

    var isConnected: Bool { status == .connected }
    var isWorking: Bool { if case .working = status { return true } else { return false } }

    var followSimulation: Bool {
        get { UserDefaults.standard.object(forKey: Self.followKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.followKey) }
    }

    init() {
        hasPairingFile = FileManager.default.fileExists(atPath: Self.pairingURL.path)
    }

    // MARK: Pairing file

    static var pairingURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("pairing.plist")
    }

    func importPairingFile(from url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        // Rýchla kontrola, že ide o pairing file (plist s certifikátmi).
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              plist["HostCertificate"] != nil || plist["DeviceCertificate"] != nil else {
            throw DeviceLinkError(message: "Súbor nevyzerá ako pairing file (chýba HostCertificate).")
        }
        try FileManager.default.createDirectory(at: Self.pairingURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: Self.pairingURL, options: [.atomic, .completeFileProtection])
        hasPairingFile = true
    }

    func deletePairingFile() {
        Task { await disconnect() }
        try? FileManager.default.removeItem(at: Self.pairingURL)
        hasPairingFile = false
    }

    // MARK: Pripojenie

    func connect() async {
        guard !isWorking else { return }
        guard let pairing = try? Data(contentsOf: Self.pairingURL) else {
            status = .failed("Najprv importuj pairing file.")
            return
        }

        let setting = UserDefaults.standard.string(forKey: Self.ipKey) ?? Self.automaticIP
        let candidates = setting == Self.automaticIP ? ["10.7.0.2", "10.7.0.1"] : [setting]

        do {
            status = .working("Hľadám zariadenie cez LocalDevVPN…")
            var found: (ip: String, mounted: Bool, chipID: UInt64)?
            var lastError: Error?
            for ip in candidates {
                do {
                    let s = try await link.ddiStatus(ip: ip, pairing: pairing)
                    found = (ip, s.mounted, s.chipID)
                    break
                } catch {
                    lastError = error
                }
            }
            guard let found else {
                throw lastError ?? DeviceLinkError(message: "Zariadenie sa nenašlo.")
            }
            activeIP = found.ip

            if !found.mounted {
                let files = try await DDIStore.load { [weak self] text in self?.status = .working(text) }
                status = .working("Pripájam Developer Disk Image…")
                try await link.mountDDI(ip: found.ip, pairing: pairing, files: files, chipID: found.chipID) { [weak self] value in
                    Task { @MainActor in
                        self?.status = .working(String(format: "Pripájam Developer Disk Image… %.0f %%", value * 100))
                    }
                }
            }

            status = .working("Pripájam službu simulácie polohy…")
            try await link.connect(ip: found.ip, pairing: pairing)
            status = .connected
            startKeepAlive()
            if let c = spoofedCoordinate { push(c, force: true) }
        } catch {
            status = .failed(error.localizedDescription)
            await link.disconnect()
            stopKeepAlive()
        }
    }

    func disconnect() async {
        stopKeepAlive()
        if isConnected { try? await link.clearLocation() }
        await link.disconnect()
        spoofedCoordinate = nil
        status = .idle
    }

    // MARK: Poloha

    /// Okamžite presunie iPhone na danú polohu (pripojí sa, ak treba).
    func teleport(to coordinate: CLLocationCoordinate2D) async {
        if !isConnected { await connect() }
        guard isConnected else { return }
        push(coordinate, force: true)
    }

    /// Vráti skutočnú GPS polohu.
    func restoreRealLocation() async {
        guard isConnected else { spoofedCoordinate = nil; return }
        do {
            try await link.clearLocation()
            spoofedCoordinate = nil
        } catch {
            fail(error)
        }
    }

    /// Posiela polohu zo simulácie trasy (obmedzené na 2× za sekundu).
    func followSimulation(_ coordinate: CLLocationCoordinate2D?) {
        guard followSimulation, isConnected, let coordinate else { return }
        guard Date.now.timeIntervalSince(lastPush) >= 0.5 else { return }
        push(coordinate)
    }

    private func push(_ coordinate: CLLocationCoordinate2D, force: Bool = false) {
        guard isConnected else { return }
        lastPush = .now
        if inFlight { queued = coordinate; return }
        inFlight = true
        Task {
            do {
                try await link.setLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                spoofedCoordinate = coordinate
            } catch {
                fail(error)
            }
            inFlight = false
            if let next = queued {
                queued = nil
                push(next)
            }
        }
    }

    private func fail(_ error: Error) {
        status = .failed("Spojenie sa prerušilo: \(error.localizedDescription)")
        stopKeepAlive()
        Task { await link.disconnect() }
    }

    /// Spojenie udržiavame živé opakovaným posielaním polohy
    /// a aplikácia beží na pozadí cez režim polohy na pozadí.
    private func startKeepAlive() {
        keepAliveTask?.cancel()
        onKeepAliveChange?(true)
        keepAliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, !Task.isCancelled else { return }
                if self.isConnected, !self.inFlight, let c = self.spoofedCoordinate,
                   Date.now.timeIntervalSince(self.lastPush) > 4 {
                    self.push(c)
                }
            }
        }
    }

    private func stopKeepAlive() {
        keepAliveTask?.cancel()
        keepAliveTask = nil
        onKeepAliveChange?(false)
    }
}

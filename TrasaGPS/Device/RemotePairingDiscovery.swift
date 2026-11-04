import Foundation
import Network

/// Nájde port služby `_remotepairing._tcp`, ktorú iPhone ohlasuje cez Bonjour.
/// Uprednostňuje rozhranie loopback (vlastné zariadenie).
enum RemotePairingDiscovery {
    static let defaultPort: UInt16 = 49152

    static func findPort(timeout: TimeInterval = 5) async -> UInt16? {
        await withCheckedContinuation { continuation in
            let search = Search(continuation: continuation)
            search.start(timeout: timeout)
        }
    }

    private final class Search: @unchecked Sendable {
        private let queue = DispatchQueue(label: "sk.trasagps.bonjour")
        private var continuation: CheckedContinuation<UInt16?, Never>?
        private var browser: NWBrowser?
        private var connection: NWConnection?
        private var usingLoopback = false

        init(continuation: CheckedContinuation<UInt16?, Never>) {
            self.continuation = continuation
        }

        func start(timeout: TimeInterval) {
            queue.async {
                let parameters = NWParameters.tcp
                parameters.includePeerToPeer = true
                let browser = NWBrowser(for: .bonjour(type: "_remotepairing._tcp", domain: "local."), using: parameters)
                self.browser = browser
                browser.browseResultsChangedHandler = { [weak self] results, _ in
                    self?.handle(results: results)
                }
                browser.stateUpdateHandler = { [weak self] state in
                    if case .failed = state { self?.finish(nil) }
                }
                browser.start(queue: self.queue)
                // Silná referencia drží vyhľadávanie nažive až do timeoutu.
                self.queue.asyncAfter(deadline: .now() + timeout) { self.finish(nil) }
            }
        }

        private func handle(results: Set<NWBrowser.Result>) {
            let services = results.filter { if case .service = $0.endpoint { return true } else { return false } }
            let loopback = services.first { $0.interfaces.contains { $0.type == .loopback || $0.name.hasPrefix("lo") } }
            guard let chosen = loopback ?? services.first else { return }
            let isLoopback = loopback != nil
            // Ak už riešime loopback, iné rozhrania ignorujeme.
            if connection != nil, usingLoopback || !isLoopback { return }
            usingLoopback = isLoopback
            connection?.cancel()

            let connection = NWConnection(to: chosen.endpoint, using: .tcp)
            self.connection = connection
            connection.stateUpdateHandler = { [weak self, weak connection] state in
                guard let self, let connection else { return }
                switch state {
                case .ready, .waiting, .preparing:
                    if case .hostPort(_, let port)? = connection.currentPath?.remoteEndpoint, port.rawValue != 0 {
                        self.finish(port.rawValue)
                    }
                case .failed:
                    break
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }

        private func finish(_ port: UInt16?) {
            guard let continuation else { return }
            self.continuation = nil
            browser?.cancel()
            connection?.cancel()
            continuation.resume(returning: port)
        }
    }
}

import Foundation

struct DeviceLinkError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Vlákno, na ktorom bežia všetky volania knižnice idevice.
/// Jej handle nie sú thread-safe, preto ich používame vždy z jedného vlákna.
final class FFIThread: Thread {
    private let condition = NSCondition()
    private var tasks: [() -> Void] = []

    override init() {
        super.init()
        name = "sk.trasagps.idevice"
        qualityOfService = .userInitiated
        start()
    }

    override func main() {
        while true {
            condition.lock()
            while tasks.isEmpty { condition.wait() }
            let task = tasks.removeFirst()
            condition.unlock()
            task()
        }
    }

    func perform<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            condition.lock()
            tasks.append {
                do { continuation.resume(returning: try work()) }
                catch { continuation.resume(throwing: error) }
            }
            condition.signal()
            condition.unlock()
        }
    }
}

private final class ProgressBox {
    let handler: (Double) -> Void
    init(_ handler: @escaping (Double) -> Void) { self.handler = handler }
}

/// Spojenie so službou simulácie polohy vlastného iPhonu (cez LocalDevVPN).
final class DeviceLink: @unchecked Sendable {
    private let worker = FFIThread()
    /// Prístup iba z `worker` vlákna.
    private var device: OpaquePointer?

    init() {
        trasa_init(6)
    }

    private static func check(_ result: UnsafeMutablePointer<CChar>?) throws {
        guard let result else { return }
        let message = String(cString: result)
        trasa_string_free(result)
        throw DeviceLinkError(message: message)
    }

    var isConnectedUnsafe: Bool { device != nil }

    func ddiStatus(ip: String, pairing: Data) async throws -> (mounted: Bool, chipID: UInt64) {
        try await worker.perform {
            var mounted: Int32 = 0
            var chipID: UInt64 = 0
            try pairing.withUnsafeBytes { raw in
                try Self.check(trasa_ddi_status(ip, raw.bindMemory(to: UInt8.self).baseAddress, raw.count, &mounted, &chipID))
            }
            return (mounted != 0, chipID)
        }
    }

    func mountDDI(ip: String, pairing: Data, files: DDIStore.Files, chipID: UInt64,
                  progress: @escaping (Double) -> Void) async throws {
        try await worker.perform {
            let box = Unmanaged.passRetained(ProgressBox(progress))
            defer { box.release() }
            let callback: @convention(c) (Int, Int, UnsafeMutableRawPointer?) -> Void = { done, total, context in
                guard let context else { return }
                let box = Unmanaged<ProgressBox>.fromOpaque(context).takeUnretainedValue()
                box.handler(total > 0 ? Double(done) / Double(total) : 0)
            }
            try pairing.withUnsafeBytes { p in
                try files.image.withUnsafeBytes { img in
                    try files.trustcache.withUnsafeBytes { tc in
                        try files.manifest.withUnsafeBytes { bm in
                            try Self.check(trasa_mount_ddi(
                                ip,
                                p.bindMemory(to: UInt8.self).baseAddress, p.count,
                                img.bindMemory(to: UInt8.self).baseAddress, img.count,
                                tc.bindMemory(to: UInt8.self).baseAddress, tc.count,
                                bm.bindMemory(to: UInt8.self).baseAddress, bm.count,
                                chipID, callback, box.toOpaque()
                            ))
                        }
                    }
                }
            }
        }
    }

    func connect(ip: String, pairing: Data) async throws {
        try await worker.perform {
            if let old = self.device {
                trasa_free(old)
                self.device = nil
            }
            var handle: OpaquePointer?
            try pairing.withUnsafeBytes { raw in
                try Self.check(trasa_connect(ip, raw.bindMemory(to: UInt8.self).baseAddress, raw.count, &handle))
            }
            self.device = handle
        }
    }

    func setLocation(latitude: Double, longitude: Double) async throws {
        try await worker.perform {
            try Self.check(trasa_set_location(self.device, latitude, longitude))
        }
    }

    func clearLocation() async throws {
        try await worker.perform {
            try Self.check(trasa_clear_location(self.device))
        }
    }

    func disconnect() async {
        _ = try? await worker.perform {
            if let device = self.device {
                trasa_free(device)
                self.device = nil
            }
        }
    }
}

import Foundation
import Darwin

/// Diagnostika: IPv4 adresy sieťových rozhraní iPhonu (napr. pdp_ip0 = mobilné dáta).
enum NetworkInfo {
    static func ipv4Summary() -> String {
        var result: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return "?" }
        defer { freeifaddrs(ifaddr) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            let iface = current.pointee
            if let addr = iface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: iface.ifa_name)
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(cString: host)
                    if name != "lo0" { result.append("\(name) \(ip)") }
                }
            }
            ptr = iface.ifa_next
        }
        return result.isEmpty ? "žiadne" : result.joined(separator: ", ")
    }
}

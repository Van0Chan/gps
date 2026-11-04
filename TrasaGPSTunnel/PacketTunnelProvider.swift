import NetworkExtension

/// Lokálna VPN: pakety pre 10.7.0.1 „odrazí“ späť do vlastného iPhonu
/// (prehodí zdrojovú a cieľovú IP adresu). Vďaka tomu sa aplikácia môže
/// pripojiť k vývojárskym službám vlastného zariadenia. Žiadne dáta neopúšťajú iPhone.
final class PacketTunnelProvider: NEPacketTunnelProvider {
    static let deviceAddress = "10.7.0.2"
    static let targetAddress = "10.7.0.1"
    /// Adresa „servera“ VPN. iOS smeruje premávku na ňu mimo tunela,
    /// preto to nesmie byť cieľová adresa 10.7.0.1 – použijeme nepoužívanú adresu.
    static let dummyServerAddress = "10.7.0.254"

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: Self.dummyServerAddress)
        let ipv4 = NEIPv4Settings(addresses: [Self.deviceAddress], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [NEIPv4Route(destinationAddress: Self.targetAddress, subnetMask: "255.255.255.255")]
        settings.ipv4Settings = ipv4
        settings.mtu = 1500

        setTunnelNetworkSettings(settings) { [weak self] error in
            completionHandler(error)
            if error == nil { self?.readPackets() }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    private func readPackets() {
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self else { return }
            self.packetFlow.writePackets(packets.map(Self.reflect), withProtocols: protocols)
            self.readPackets()
        }
    }

    /// Prehodí zdrojovú a cieľovú IPv4 adresu. Kontrolné súčty IP aj TCP/UDP
    /// sa tým nemenia (súčet je komutatívny), takže netreba nič prepočítavať.
    static func reflect(_ packet: Data) -> Data {
        guard packet.count >= 20, packet[packet.startIndex] >> 4 == 4 else { return packet }
        var copy = packet
        copy.withUnsafeMutableBytes { bytes in
            for i in 0..<4 { bytes.swapAt(12 + i, 16 + i) }
        }
        return copy
    }
}

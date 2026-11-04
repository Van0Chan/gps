import NetworkExtension

/// Lokálna VPN: pakety pre 192.0.2.1 „odrazí“ späť do vlastného iPhonu
/// (prehodí zdrojovú a cieľovú IP adresu). Vďaka tomu sa aplikácia môže
/// pripojiť k vývojárskym službám vlastného zariadenia. Žiadne dáta neopúšťajú iPhone.
final class PacketTunnelProvider: NEPacketTunnelProvider {
    // Rozsah 192.0.2.0/24 (TEST-NET-1) sa v skutočných sieťach nepoužíva.
    // Mobilní operátori často dávajú telefónu adresu z 10.x.x.x, s ktorou by sa
    // pôvodné 10.7.0.x pobilo – vtedy by spojenie na mobilných dátach nefungovalo.
    // Musí sedieť s BuiltInVPN.targetAddress v aplikácii.
    static let deviceAddress = "192.0.2.2"
    static let targetAddress = "192.0.2.1"
    /// Adresa „servera“ VPN. iOS smeruje premávku na ňu mimo tunela,
    /// preto to nesmie byť cieľová adresa – použijeme nepoužívanú adresu.
    static let dummyServerAddress = "192.0.2.254"

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

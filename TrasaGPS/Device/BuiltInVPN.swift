import Foundation
import NetworkExtension

/// Vstavaná lokálna VPN (náhrada aplikácie LocalDevVPN).
@MainActor
enum BuiltInVPN {
    static let settingKey = "useBuiltInVPN"

    static var isEnabledInSettings: Bool {
        UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true
    }

    /// Bundle ID rozšírenia (podpisovacie nástroje ho môžu zmeniť, preto ho čítame z balíka).
    static var tunnelBundleID: String? {
        guard let plugins = Bundle.main.builtInPlugInsURL,
              let items = try? FileManager.default.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil)
        else { return nil }
        for url in items where url.pathExtension == "appex" {
            if let bundle = Bundle(url: url),
               let point = (bundle.infoDictionary?["NSExtension"] as? [String: Any])?["NSExtensionPointIdentifier"] as? String,
               point == "com.apple.networkextension.packet-tunnel" {
                return bundle.bundleIdentifier
            }
        }
        return nil
    }

    private static func manager() async throws -> NETunnelProviderManager {
        guard let bundleID = tunnelBundleID else {
            throw DeviceLinkError(message: "V aplikácii chýba VPN rozšírenie.")
        }
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        let manager = managers.first {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == bundleID
        } ?? NETunnelProviderManager()

        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = bundleID
        proto.serverAddress = "Lokálne (iPhone)"
        manager.protocolConfiguration = proto
        manager.localizedDescription = "GeoPilot"
        manager.isEnabled = true
        do {
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
        } catch {
            throw DeviceLinkError(message: """
                Vstavanú VPN sa nepodarilo nastaviť: \(error.localizedDescription)
                Tvoj podpisový certifikát asi nepovoľuje Network Extension. V nastaveniach vypni „Vstavaná VPN“ a použi LocalDevVPN.
                """)
        }
        return manager
    }

    /// Spustí VPN a počká, kým je pripojená.
    static func start() async throws {
        let manager = try await manager()
        let connection = manager.connection
        // Ak VPN beží (napr. zo staršej verzie), reštartujeme ju, aby mala aktuálne nastavenia.
        if connection.status == .connected || connection.status == .connecting {
            connection.stopVPNTunnel()
            for _ in 0..<20 where connection.status != .disconnected {
                try await Task.sleep(for: .milliseconds(150))
            }
        }
        do {
            try connection.startVPNTunnel()
        } catch {
            throw DeviceLinkError(message: "VPN sa nedá spustiť: \(error.localizedDescription)")
        }
        for _ in 0..<60 {
            if connection.status == .connected { return }
            if connection.status == .disconnected || connection.status == .invalid {
                try await Task.sleep(for: .milliseconds(250))
                if connection.status == .disconnected || connection.status == .invalid { break }
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        guard connection.status == .connected else {
            throw DeviceLinkError(message: "Vstavaná VPN sa nepripojila. Skontroluj Nastavenia ▸ VPN, alebo použi LocalDevVPN.")
        }
    }

    static func stop() async {
        guard let managers = try? await NETunnelProviderManager.loadAllFromPreferences() else { return }
        for manager in managers { manager.connection.stopVPNTunnel() }
    }
}

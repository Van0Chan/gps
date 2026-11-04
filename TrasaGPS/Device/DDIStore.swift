import Foundation

/// Stiahnutie Developer Disk Image (potrebný pre vývojárske služby na iOS 17+).
/// Súbory pochádzajú z verejného repozitára doronz88/DeveloperDiskImage.
enum DDIStore {
    struct Files {
        let image: Data
        let trustcache: Data
        let manifest: Data
    }

    private static let baseURL = URL(string: "https://raw.githubusercontent.com/doronz88/DeveloperDiskImage/main/PersonalizedImages/Xcode_iOS_DDI_Personalized/")!
    private static let names = ["Image.dmg", "Image.dmg.trustcache", "BuildManifest.plist"]

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("DDI", isDirectory: true)
    }

    static var isDownloaded: Bool {
        names.allSatisfy { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }
    }

    static func load(status: @escaping (String) -> Void) async throws -> Files {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (index, name) in names.enumerated() {
            let target = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: target.path) { continue }
            await MainActor.run { status("Sťahujem Developer Disk Image (\(index + 1)/\(names.count))…") }
            let (tmp, response) = try await URLSession.shared.download(from: baseURL.appendingPathComponent(name))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw DeviceLinkError(message: "Stiahnutie \(name) zlyhalo (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)).")
            }
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: tmp, to: target)
        }
        return Files(
            image: try Data(contentsOf: directory.appendingPathComponent("Image.dmg")),
            trustcache: try Data(contentsOf: directory.appendingPathComponent("Image.dmg.trustcache")),
            manifest: try Data(contentsOf: directory.appendingPathComponent("BuildManifest.plist"))
        )
    }

    // MARK: Cryptex (iOS 17.4+ cez RemotePairing tunel)

    private static let cryptexURL = URL(string: "https://raw.githubusercontent.com/doronz88/DeveloperDiskImage/main/PersonalizedImages/Xcode_iOS_DDI_Cryptex/")!
    private static let cryptexNames = ["BuildManifest.plist", "Image.dmg", "Image.dmg.trustcache",
                                       "Image.dmg.cryptex_info", "Image.dmg.root_hash"]

    static var cryptexDirectory: URL {
        directory.appendingPathComponent("Cryptex", isDirectory: true)
    }

    static var isCryptexDownloaded: Bool {
        cryptexNames.allSatisfy { FileManager.default.fileExists(atPath: cryptexDirectory.appendingPathComponent($0).path) }
    }

    /// Stiahne cryptex DDI a vráti zložku so súbormi.
    static func loadCryptex(status: @escaping (String) -> Void) async throws -> URL {
        let dir = cryptexDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (index, name) in cryptexNames.enumerated() {
            let target = dir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: target.path) { continue }
            await MainActor.run { status("Sťahujem Developer Disk Image (\(index + 1)/\(cryptexNames.count))…") }
            let (tmp, response) = try await URLSession.shared.download(from: cryptexURL.appendingPathComponent(name))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw DeviceLinkError(message: "Stiahnutie \(name) zlyhalo (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)).")
            }
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: tmp, to: target)
        }
        return dir
    }

    static var anyDownloaded: Bool { isDownloaded || isCryptexDownloaded }

    static func delete() {
        try? FileManager.default.removeItem(at: directory)
    }
}

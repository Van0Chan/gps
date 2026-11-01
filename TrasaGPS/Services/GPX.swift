import Foundation
import CoreLocation
import UniformTypeIdentifiers
import CoreTransferable

extension UTType {
    static let gpx = UTType(importedAs: "com.topografix.gpx", conformingTo: .xml)
}

enum GPXError: LocalizedError {
    case noPoints
    var errorDescription: String? { "Súbor neobsahuje žiadne body trasy (trkpt, rtept ani wpt)." }
}

/// Načítanie a zápis súborov GPX 1.1.
enum GPX {
    struct Parsed {
        var name: String?
        var points: [TrackPoint]
    }

    static func parse(data: Data) throws -> Parsed {
        let delegate = GPXParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw parser.parserError ?? GPXError.noPoints
        }
        // Priorita: track > route > waypointy
        let points = !delegate.trackPoints.isEmpty ? delegate.trackPoints
            : !delegate.routePoints.isEmpty ? delegate.routePoints
            : delegate.wayPoints
        guard !points.isEmpty else { throw GPXError.noPoints }
        return Parsed(name: delegate.name, points: points)
    }

    /// Klasický GPX track (pre iné aplikácie, Strava, mapy...).
    static func track(name: String, points: [TrackPoint]) -> String {
        var s = header()
        s += "  <metadata><name>\(escape(name))</name><time>\(iso.string(from: .now))</time></metadata>\n"
        s += "  <trk>\n    <name>\(escape(name))</name>\n    <trkseg>\n"
        for p in points {
            s += "      <trkpt lat=\"\(fmt(p.latitude))\" lon=\"\(fmt(p.longitude))\">"
            if let alt = p.altitude { s += "<ele>\(String(format: "%.1f", alt))</ele>" }
            if let t = p.timestamp { s += "<time>\(iso.string(from: t))</time>" }
            s += "</trkpt>\n"
        }
        s += "    </trkseg>\n  </trk>\n</gpx>\n"
        return s
    }

    /// GPX pre simuláciu polohy v Xcode (Debug ▸ Simulate Location).
    /// Xcode prehráva waypointy podľa ich časov, preto časy prepočítame
    /// tak, aby sa trasa prešla zvolenou konštantnou rýchlosťou.
    static func xcodeSimulation(name: String, points: [TrackPoint], speed metersPerSecond: Double) -> String {
        let coords = densify(points.map(\.coordinate), maxStep: 25)
        let speed = max(metersPerSecond, 0.1)
        var time = Date.now
        var s = header()
        for (i, c) in coords.enumerated() {
            if i > 0 { time = time.addingTimeInterval(Geo.distance(coords[i - 1], c) / speed) }
            s += "  <wpt lat=\"\(fmt(c.latitude))\" lon=\"\(fmt(c.longitude))\">"
            if i == 0 { s += "<name>\(escape(name))</name>" }
            s += "<time>\(iso.string(from: time))</time></wpt>\n"
        }
        s += "</gpx>\n"
        return s
    }

    /// Doplní medzibody, aby simulácia v Xcode nerobila veľké skoky.
    static func densify(_ coords: [CLLocationCoordinate2D], maxStep: Double) -> [CLLocationCoordinate2D] {
        guard coords.count > 1 else { return coords }
        var out: [CLLocationCoordinate2D] = [coords[0]]
        for (a, b) in zip(coords, coords.dropFirst()) {
            let d = Geo.distance(a, b)
            let steps = max(1, Int(ceil(d / maxStep)))
            for k in 1...steps { out.append(Geo.interpolate(a, b, Double(k) / Double(steps))) }
        }
        return out
    }

    static func fileName(for name: String, suffix: String = "") -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let cleaned = String(name.unicodeScalars.filter { allowed.contains($0) }).trimmingCharacters(in: .whitespaces)
        return (cleaned.isEmpty ? "trasa" : cleaned) + suffix + ".gpx"
    }

    private static func header() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="TrasaGPS" xmlns="http://www.topografix.com/GPX/1/1">

        """
    }

    private static func fmt(_ v: Double) -> String { String(format: "%.7f", v) }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

private final class GPXParserDelegate: NSObject, XMLParserDelegate {
    var name: String?
    var trackPoints: [TrackPoint] = []
    var routePoints: [TrackPoint] = []
    var wayPoints: [TrackPoint] = []

    private var current: TrackPoint?
    private var currentElement = ""
    private var text = ""
    private var depthInPoint = false

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        let el = local(elementName)
        currentElement = el
        text = ""
        if el == "trkpt" || el == "rtept" || el == "wpt",
           let lat = attributes["lat"].flatMap(Double.init),
           let lon = attributes["lon"].flatMap(Double.init) {
            current = TrackPoint(latitude: lat, longitude: lon)
            depthInPoint = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let el = local(elementName)
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch el {
        case "ele":
            current?.altitude = Double(value)
        case "time":
            if depthInPoint {
                current?.timestamp = GPX.isoFractional.date(from: value) ?? GPX.iso.date(from: value)
            }
        case "speed":
            current?.speed = Double(value)
        case "name":
            if !depthInPoint, name == nil, !value.isEmpty { name = value }
        case "trkpt", "rtept", "wpt":
            if let p = current {
                switch el {
                case "trkpt": trackPoints.append(p)
                case "rtept": routePoints.append(p)
                default: wayPoints.append(p)
                }
            }
            current = nil
            depthInPoint = false
        default:
            break
        }
        text = ""
    }

    private func local(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init) ?? name
    }
}

/// Súbor GPX na zdieľanie cez ShareLink.
struct GPXDocument: Transferable {
    let fileName: String
    let content: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .gpx) { doc in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(doc.fileName)
            try doc.content.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}

import Foundation

struct GeoPoint: Equatable {
    var latitude: Double
    var longitude: Double
    var name: String
}

/// Time zone coordinates from the system's tz database, so the World and Solar
/// faces know roughly where you are without asking for location access.
enum ZoneInfo {
    static let coordinates: [String: (Double, Double)] = {
        guard let text = try? String(contentsOfFile: "/usr/share/zoneinfo/zone.tab", encoding: .utf8) else { return [:] }
        var out: [String: (Double, Double)] = [:]
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let fields = line.split(separator: "\t")
            guard fields.count >= 3, let coord = parse(String(fields[1])) else { continue }
            out[String(fields[2])] = coord
        }
        return out
    }()

    /// Parses ISO 6709 "+DDMM+DDDMM" or "+DDMMSS+DDDMMSS".
    private static func parse(_ s: String) -> (Double, Double)? {
        let chars = Array(s)
        guard let split = chars.indices.dropFirst().first(where: { chars[$0] == "+" || chars[$0] == "-" }) else { return nil }
        func value(_ part: [Character], degreeDigits: Int) -> Double? {
            guard let sign = part.first else { return nil }
            let digits = String(part.dropFirst())
            guard digits.count >= degreeDigits + 2,
                  let deg = Double(digits.prefix(degreeDigits)),
                  let min = Double(digits.dropFirst(degreeDigits).prefix(2)) else { return nil }
            let sec = Double(digits.dropFirst(degreeDigits + 2).prefix(2)) ?? 0
            let v = deg + min / 60 + sec / 3600
            return sign == "-" ? -v : v
        }
        guard let lat = value(Array(chars[..<split]), degreeDigits: 2),
              let lon = value(Array(chars[split...]), degreeDigits: 3) else { return nil }
        return (lat, lon)
    }

    static func cityName(for identifier: String) -> String {
        let last = identifier.split(separator: "/").last.map(String.init) ?? identifier
        return last.replacingOccurrences(of: "_", with: " ")
    }

    /// Short city code like the Clock widget's "CUP": initials for multi-word
    /// names ("Los Angeles" → "LA"), otherwise the first three letters.
    static func abbreviation(for identifier: String) -> String {
        let words = cityName(for: identifier).split(separator: " ")
        if words.count > 1 {
            return String(words.compactMap(\.first).prefix(3)).uppercased()
        }
        return String(cityName(for: identifier).filter(\.isLetter).prefix(3)).uppercased()
    }

    static func current(for config: StandbyConfig) -> GeoPoint {
        if let place = config.weatherPlace {
            return GeoPoint(latitude: place.latitude, longitude: place.longitude, name: place.name)
        }
        let id = TimeZone.current.identifier
        if let c = coordinates[id] {
            return GeoPoint(latitude: c.0, longitude: c.1, name: cityName(for: id))
        }
        return GeoPoint(latitude: 37.33, longitude: -122.03, name: "Cupertino")
    }
}

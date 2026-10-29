import Foundation

struct WeatherSnapshot: Equatable {
    var temperature: Double
    var high: Double
    var low: Double
    var code: Int
    var isDay: Bool
    var placeName: String
    var fetched: Date

    var symbol: String { WeatherCode.symbol(code, isDay: isDay) }
    var condition: String { WeatherCode.text(code) }
    var temperatureText: String { "\(Int(temperature.rounded()))°" }
    var rangeText: String { "H:\(Int(high.rounded()))° L:\(Int(low.rounded()))°" }
}

/// Weather from Open-Meteo (free, no API key). Only contacted once the user
/// picks a city in Settings.
@MainActor
final class WeatherService: ObservableObject {
    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var errorText: String?

    private var loadedKey = ""
    private var inFlight = false

    func refresh(config: StandbyConfig, force: Bool = false) {
        guard let place = config.weatherPlace else {
            snapshot = nil
            loadedKey = ""
            return
        }
        let fahrenheit = config.temperatureUnit.usesFahrenheit
        let key = "\(place.id)|\(fahrenheit)"
        if !force, key == loadedKey, let s = snapshot, Date().timeIntervalSince(s.fetched) < 15 * 60 { return }
        guard !inFlight else { return }
        inFlight = true
        Task {
            do {
                let result = try await Self.fetch(place: place, fahrenheit: fahrenheit)
                snapshot = result
                loadedKey = key
                errorText = nil
            } catch {
                errorText = "Couldn't load weather."
                if key != loadedKey { snapshot = nil }
            }
            inFlight = false
        }
    }

    func setPreview(_ s: WeatherSnapshot?) { snapshot = s }

    nonisolated static func fetch(place: WeatherPlace, fahrenheit: Bool) async throws -> WeatherSnapshot {
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            URLQueryItem(name: "latitude", value: String(place.latitude)),
            URLQueryItem(name: "longitude", value: String(place.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "temperature_unit", value: fahrenheit ? "fahrenheit" : "celsius"),
        ]
        struct Response: Decodable {
            struct Current: Decodable {
                let temperature_2m: Double
                let weather_code: Int
                let is_day: Int
            }
            struct Daily: Decodable {
                let temperature_2m_max: [Double]
                let temperature_2m_min: [Double]
            }
            let current: Current
            let daily: Daily
        }
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        let r = try JSONDecoder().decode(Response.self, from: data)
        return WeatherSnapshot(temperature: r.current.temperature_2m,
                               high: r.daily.temperature_2m_max.first ?? r.current.temperature_2m,
                               low: r.daily.temperature_2m_min.first ?? r.current.temperature_2m,
                               code: r.current.weather_code,
                               isDay: r.current.is_day == 1,
                               placeName: place.name,
                               fetched: Date())
    }

    nonisolated static func search(_ query: String) async throws -> [WeatherPlace] {
        var comps = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        comps.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "8"),
            URLQueryItem(name: "language", value: Locale.current.language.languageCode?.identifier ?? "en"),
            URLQueryItem(name: "format", value: "json"),
        ]
        struct Response: Decodable {
            struct Item: Decodable {
                let name: String
                let latitude: Double
                let longitude: Double
                let country: String?
                let admin1: String?
            }
            let results: [Item]?
        }
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        let r = try JSONDecoder().decode(Response.self, from: data)
        return (r.results ?? []).map { item in
            let region = [item.admin1, item.country].compactMap { $0 }.joined(separator: ", ")
            return WeatherPlace(name: item.name, region: region, latitude: item.latitude, longitude: item.longitude)
        }
    }
}

enum WeatherCode {
    static func symbol(_ code: Int, isDay: Bool) -> String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...57: "cloud.drizzle.fill"
        case 61, 63, 66: "cloud.rain.fill"
        case 65, 67: "cloud.heavyrain.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 80...82: isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    static func text(_ code: Int) -> String {
        switch code {
        case 0: "Clear"
        case 1: "Mostly Clear"
        case 2: "Partly Cloudy"
        case 3: "Cloudy"
        case 45, 48: "Foggy"
        case 51...57: "Drizzle"
        case 61, 63, 66: "Rain"
        case 65, 67: "Heavy Rain"
        case 71...77: "Snow"
        case 80...82: "Showers"
        case 85, 86: "Snow Showers"
        case 95...99: "Thunderstorms"
        default: "Cloudy"
        }
    }
}

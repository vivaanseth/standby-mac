import Foundation

/// Low-precision solar ephemeris (USNO approximation, good to ~1 arc minute),
/// used for the World map's daylight and the Solar face's sun position.
enum SolarMath {
    struct SunPosition: Sendable {
        /// Latitude of the point where the sun is directly overhead.
        var declination: Double
        /// Longitude of the point where it is solar noon.
        var subsolarLongitude: Double
    }

    static func position(at date: Date) -> SunPosition {
        let d = date.timeIntervalSince1970 / 86400 + 2440587.5 - 2451545.0
        let meanLongitude = normalize(280.460 + 0.9856474 * d)
        let anomaly = radians(normalize(357.528 + 0.9856003 * d))
        let eclipticLongitude = radians(meanLongitude + 1.915 * sin(anomaly) + 0.020 * sin(2 * anomaly))
        let obliquity = radians(23.439 - 0.0000004 * d)
        let declination = degrees(asin(sin(obliquity) * sin(eclipticLongitude)))
        let rightAscension = normalize(degrees(atan2(cos(obliquity) * sin(eclipticLongitude), cos(eclipticLongitude))))
        let equationOfTime = signed(meanLongitude - rightAscension)
        let utHours = date.timeIntervalSince1970.truncatingRemainder(dividingBy: 86400) / 3600
        let longitude = signed((12 - utHours) * 15 - equationOfTime)
        return SunPosition(declination: declination, subsolarLongitude: longitude)
    }

    /// Sun elevation above the horizon in degrees.
    static func elevation(_ sun: SunPosition, latitude: Double, longitude: Double) -> Double {
        let h = radians(longitude - sun.subsolarLongitude)
        let phi = radians(latitude)
        let dec = radians(sun.declination)
        return degrees(asin(sin(phi) * sin(dec) + cos(phi) * cos(dec) * cos(h)))
    }

    static func elevation(at date: Date, latitude: Double, longitude: Double) -> Double {
        elevation(position(at: date), latitude: latitude, longitude: longitude)
    }

    /// Degrees from local solar noon: negative in the morning, positive after noon.
    static func hourAngle(at date: Date, longitude: Double) -> Double {
        signed(longitude - position(at: date).subsolarLongitude)
    }

    /// Today's sunrise and sunset (local calendar day), found by scanning the
    /// day in five-minute steps. nil during polar day or night.
    static func sunTimes(on date: Date, latitude: Double, longitude: Double) -> (rise: Date?, set: Date?) {
        let start = Calendar.current.startOfDay(for: date)
        let horizon = -0.833 // refraction plus the sun's radius
        var rise: Date?, set: Date?
        var previous = elevation(at: start, latitude: latitude, longitude: longitude) - horizon
        for step in 1...288 {
            let t = start.addingTimeInterval(Double(step) * 300)
            let value = elevation(at: t, latitude: latitude, longitude: longitude) - horizon
            if (previous < 0) != (value < 0) {
                let crossing = t.addingTimeInterval(-300 * value / (value - previous))
                if value >= 0 { rise = rise ?? crossing } else { set = crossing }
            }
            previous = value
        }
        return (rise, set)
    }

    private static func radians(_ d: Double) -> Double { d * .pi / 180 }
    private static func degrees(_ r: Double) -> Double { r * 180 / .pi }
    private static func normalize(_ d: Double) -> Double {
        let v = d.truncatingRemainder(dividingBy: 360)
        return v < 0 ? v + 360 : v
    }
    private static func signed(_ d: Double) -> Double {
        let v = normalize(d)
        return v > 180 ? v - 360 : v
    }
}

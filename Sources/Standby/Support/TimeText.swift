import Foundation

enum TimeText {
    nonisolated(unsafe) private static var formatters: [String: DateFormatter] = [:]
    nonisolated(unsafe) private static var systemUses24Hour: Bool?

    static func format(_ date: Date, _ template: String, timeZone: TimeZone = .current) -> String {
        let key = template + "|" + timeZone.identifier
        if let f = formatters[key] { return f.string(from: date) }
        let f = DateFormatter()
        f.locale = .current
        f.timeZone = timeZone
        f.setLocalizedDateFormatFromTemplate(template)
        formatters[key] = f
        return f.string(from: date)
    }

    static func uses24Hour(_ format: TimeFormat) -> Bool {
        switch format {
        case .twelveHour: return false
        case .twentyFourHour: return true
        case .system:
            if let cached = systemUses24Hour { return cached }
            let pattern = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? ""
            let value = !pattern.contains("a")
            systemUses24Hour = value
            return value
        }
    }

    /// Hour and minute digits the way StandBy shows them: no AM/PM, no leading
    /// zero in 12-hour time.
    static func hourMinute(_ date: Date, format: TimeFormat, timeZone: TimeZone = .current) -> (hour: String, minute: String) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.hour, .minute], from: date)
        let minute = String(format: "%02d", c.minute ?? 0)
        var hour = c.hour ?? 0
        if uses24Hour(format) {
            return (String(format: "%02d", hour), minute)
        }
        hour %= 12
        if hour == 0 { hour = 12 }
        return ("\(hour)", minute)
    }

    static func clock(_ date: Date, format: TimeFormat, timeZone: TimeZone = .current) -> String {
        let t = hourMinute(date, format: format, timeZone: timeZone)
        return "\(t.hour):\(t.minute)"
    }

    static func eventTime(_ event: UpcomingEvent) -> String {
        if event.isAllDay { return "All Day" }
        let start = format(event.start, "jmm")
        let end = format(event.end, "jmm")
        let day = Calendar.current.isDateInToday(event.start) ? "" : format(event.start, "EEE") + " "
        return "\(day)\(start) – \(end)"
    }

    /// "Today, +3HRS" style caption used by the World Clock widget.
    static func relativeOffset(for zone: TimeZone, at date: Date) -> String {
        let seconds = zone.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date)
        var remote = Calendar(identifier: .gregorian)
        remote.timeZone = zone
        let rc = remote.dateComponents([.year, .month, .day], from: date)
        let lc = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let rd = Calendar.current.date(from: rc) ?? date
        let ld = Calendar.current.date(from: lc) ?? date
        let days = Calendar.current.dateComponents([.day], from: ld, to: rd).day ?? 0
        let word = days > 0 ? "Tomorrow" : (days < 0 ? "Yesterday" : "Today")
        if seconds == 0 { return word }
        let hours = Double(seconds) / 3600
        let number = hours == hours.rounded() ? String(Int(hours)) : String(format: "%.1f", hours)
        return "\(word), \(hours > 0 ? "+" : "")\(number)HRS"
    }
}

import Foundation

/// UTC, Eastern, and MET. Times are formatted from the given instant.
/// Nothing is shifted to match a photograph.
struct Clocks: Equatable {
    let utc: String
    let eastern: String
    let met: String
}

enum ClockMath {
    static let missionEpochUTC = "2026-04-01T22:35:12Z"

    static func format(date: Date, epoch: Date) -> Clocks {
        Clocks(
            utc: utcText(date),
            eastern: easternText(date),
            met: metText(date, epoch: epoch)
        )
    }

    static func utcText(_ date: Date) -> String {
        let zone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let parts = gregorian(date, timeZone: zone)
        return String(format: "%02d:%02d:%02d UTC", parts.hour, parts.minute, parts.second)
    }

    static func easternText(_ date: Date) -> String {
        guard let zone = TimeZone(identifier: "America/New_York") else {
            return utcText(date)
        }
        let parts = gregorian(date, timeZone: zone)
        let name = zone.isDaylightSavingTime(for: date) ? "EDT" : "EST"
        return String(format: "%02d:%02d:%02d %@", parts.hour, parts.minute, parts.second, name)
    }

    /// Hours are not limited to 24. The guide's mission start is the epoch.
    static func metText(_ date: Date, epoch: Date) -> String {
        let seconds = Int((date.timeIntervalSince(epoch)).rounded())
        let sign = seconds < 0 ? "-" : ""
        let absolute = abs(seconds)
        let hours = absolute / 3600
        let minutes = (absolute % 3600) / 60
        let secs = absolute % 60
        return String(format: "%@%d:%02d:%02d MET", sign, hours, minutes, secs)
    }

    private static func gregorian(_ date: Date, timeZone: TimeZone) -> (hour: Int, minute: Int, second: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return (parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }
}

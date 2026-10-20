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

    /// Days, hours, minutes, seconds, and milliseconds from the guide's mission start.
    static func metText(_ date: Date, epoch: Date) -> String {
        let interval = date.timeIntervalSince(epoch)
        let sign = interval < 0 ? "-" : ""
        let millisTotal = Int((abs(interval) * 1000).rounded())
        let days = millisTotal / 86_400_000
        let dayRemainder = millisTotal % 86_400_000
        let hours = dayRemainder / 3_600_000
        let minutes = (dayRemainder % 3_600_000) / 60_000
        let seconds = (dayRemainder % 60_000) / 1000
        let millis = dayRemainder % 1000
        return String(format: "%@%02d:%02d:%02d:%02d.%03d MET", sign, days, hours, minutes, seconds, millis)
    }

    private static func gregorian(_ date: Date, timeZone: TimeZone) -> (hour: Int, minute: Int, second: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return (parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }
}

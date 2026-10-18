import Foundation

enum Stamp {
    /// `HH:MM:SS` from a timeline UTC string. The date is left unchanged.
    static func clock(_ utc: String) -> String {
        guard let separator = utc.firstIndex(of: "T") else { return utc }
        let time = utc[utc.index(after: separator)...]
        return String(time.prefix(8))
    }
}

import Foundation

/// The desktop's `formatHistoryTime`: `now`, `N min`, `N hr(s)`, `N day(s)`,
/// `N mo(s)`, `N yr(s)`.
enum HistoryTime {
    static func format(_ date: Date, now: Date = .now) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        if hours < 24 { return plural(hours, "hr") }
        let days = hours / 24
        if days < 30 { return plural(days, "day") }
        let months = days / 30
        if months < 12 { return plural(months, "mo") }
        return plural(months / 12, "yr")
    }

    private static func plural(_ n: Int, _ unit: String) -> String {
        "\(n) \(unit)\(n == 1 ? "" : "s")"
    }
}

import Foundation

/// Formats a duration the Chinese way, for notification bodies.
///
/// At most two units are shown, largest first: `48 秒`, `1 分 25 秒`,
/// `2 小时 3 分`, `1 天 2 小时`. A zero remainder is dropped, and a value below
/// one second becomes `0 秒`.
public enum ChineseDuration {
    /// Chinese text for a whole number of seconds.
    public static func text(seconds: Int) -> String {
        let total = max(0, seconds)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        let remainingSeconds = total % 60

        var parts: [String] = []
        if days > 0 {
            parts.append("\(days) 天")
            if hours > 0 { parts.append("\(hours) 小时") }
        } else if hours > 0 {
            parts.append("\(hours) 小时")
            if minutes > 0 { parts.append("\(minutes) 分") }
        } else if minutes > 0 {
            parts.append("\(minutes) 分")
            if remainingSeconds > 0 { parts.append("\(remainingSeconds) 秒") }
        } else {
            parts.append("\(remainingSeconds) 秒")
        }

        return parts.joined(separator: " ")
    }

    /// Chinese text for an interval; the value is rounded to whole seconds.
    public static func text(_ interval: TimeInterval) -> String {
        text(seconds: Int(max(0, interval).rounded()))
    }
}

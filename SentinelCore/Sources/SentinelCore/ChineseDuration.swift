import Foundation

/// Formats a duration for notification bodies and the 概览 cards.
///
/// At most two units are shown, largest first. Chinese: `48 秒`, `1 分 25 秒`,
/// `2 小时 3 分`, `1 天 2 小时`. English: `48 s`, `1 min 25 s`, `2 h 3 min`,
/// `1 d 2 h`. A zero remainder is dropped, and a value below one second becomes
/// `0 秒` / `0 s`. The language is read when the text is built, so a changed
/// setting shows at once.
public enum DurationText {
    /// Text of a whole number of seconds, in the current language.
    public static func text(seconds: Int) -> String {
        let total = max(0, seconds)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        let remainingSeconds = total % 60

        var parts: [String] = []
        if days > 0 {
            parts.append(T(.durationDays, days))
            if hours > 0 { parts.append(T(.durationHours, hours)) }
        } else if hours > 0 {
            parts.append(T(.durationHours, hours))
            if minutes > 0 { parts.append(T(.durationMinutes, minutes)) }
        } else if minutes > 0 {
            parts.append(T(.durationMinutes, minutes))
            if remainingSeconds > 0 { parts.append(T(.durationSeconds, remainingSeconds)) }
        } else {
            parts.append(T(.durationSeconds, remainingSeconds))
        }

        return parts.joined(separator: " ")
    }

    /// Text of an interval; the value is rounded to whole seconds.
    public static func text(_ interval: TimeInterval) -> String {
        text(seconds: Int(max(0, interval).rounded()))
    }
}

/// The name the duration formatter had while the app was Chinese only.
///
/// Kept so the older call sites and tests keep reading; the text itself follows
/// `AppText.language` now.
public typealias ChineseDuration = DurationText

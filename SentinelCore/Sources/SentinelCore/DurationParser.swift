import Foundation

/// Parses the duration strings the gateway puts into log parameters.
///
/// Observed formats: `48s`, `1m 25s`, `22m 42s`, `2h 3m`, `6h 36m`, and
/// `1d 2h`. Units may be combined in any order and separated by spaces or commas.
public enum DurationParser {
    private static let secondsPerUnit: [String: Int] = [
        "s": 1, "sec": 1, "secs": 1, "second": 1, "seconds": 1,
        "m": 60, "min": 60, "mins": 60, "minute": 60, "minutes": 60,
        "h": 3_600, "hr": 3_600, "hrs": 3_600, "hour": 3_600, "hours": 3_600,
        "d": 86_400, "day": 86_400, "days": 86_400,
    ]

    /// Converts a duration string to whole seconds, or returns `nil` when the
    /// text is empty or does not look like a duration.
    public static func seconds(from text: String) -> Int? {
        let trimmed = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !trimmed.isEmpty else { return nil }

        var total = 0
        var parsedAny = false
        var index = trimmed.startIndex

        while index < trimmed.endIndex {
            let character = trimmed[index]

            if character == " " || character == "," {
                index = trimmed.index(after: index)
                continue
            }

            guard character.isNumber else { return nil }

            var digits = ""
            while index < trimmed.endIndex, trimmed[index].isNumber {
                digits.append(trimmed[index])
                index = trimmed.index(after: index)
            }

            var unit = ""
            while index < trimmed.endIndex, trimmed[index].isLetter {
                unit.append(trimmed[index])
                index = trimmed.index(after: index)
            }

            guard let value = Int(digits), let multiplier = secondsPerUnit[unit] else { return nil }
            total += value * multiplier
            parsedAny = true
        }

        return parsedAny ? total : nil
    }
}

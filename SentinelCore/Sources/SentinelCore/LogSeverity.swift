import Foundation

/// Severity of a UniFi system log entry.
///
/// The gateway sends `LOW`, `MEDIUM`, `HIGH` or `VERY_HIGH`. The case order
/// follows the gateway order (low to very high), so severities compare with `<`.
///
/// An unknown severity string is not an error: log entry decoding uses
/// `init?(rawValueString:)` and stores `nil` instead of failing the whole page.
public enum LogSeverity: String, CaseIterable, Codable {
    case low = "LOW"
    case medium = "MEDIUM"
    case high = "HIGH"
    case veryHigh = "VERY_HIGH"

    /// Rank from 1 (low) to 4 (very high). Used to sort and to compare.
    public var rank: Int {
        switch self {
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        case .veryHigh: return 4
        }
    }

    /// Display name for the app, per the project glossary, in the current language.
    public var displayName: String {
        switch self {
        case .low: return T(.severityLow)
        case .medium: return T(.severityMedium)
        case .high: return T(.severityHigh)
        case .veryHigh: return T(.severityVeryHigh)
        }
    }

    /// Parses a gateway severity string. Case and surrounding whitespace are ignored.
    /// Returns `nil` for a severity this version does not know.
    public init?(rawValueString: String) {
        let normalized = rawValueString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        self.init(rawValue: normalized)
    }
}

extension LogSeverity: Comparable {
    public static func < (lhs: LogSeverity, rhs: LogSeverity) -> Bool {
        lhs.rank < rhs.rank
    }
}

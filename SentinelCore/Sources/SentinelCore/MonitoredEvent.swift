import Foundation

/// The monitored UniFi log events, named as on the UniFi log page.
///
/// Detection is by `key` (and by `category` for threats) instead of by `type`:
/// the gateway marks WAN outages as `BACKUP_CONNECTION_IN_USE`, which is also
/// used for log entries that are not monitored.
public enum MonitoredEvent: String, CaseIterable, Codable {
    case internetDown
    case internetRestored
    case internetDownMultipleTimes
    case internetDownTemporary
    case packetLoss
    case highLatency
    case threatDetected

    /// Display name for the app, matching the UniFi log page wording, in the
    /// current language. The English names are the ones of the UniFi interface.
    public var displayName: String {
        switch self {
        case .internetDown: return T(.eventInternetDown)
        case .internetRestored: return T(.eventInternetRestored)
        case .internetDownMultipleTimes: return T(.eventInternetDownMultipleTimes)
        case .internetDownTemporary: return T(.eventInternetDownTemporary)
        case .packetLoss: return T(.eventPacketLoss)
        case .highLatency: return T(.eventHighLatency)
        case .threatDetected: return T(.eventThreatDetected)
        }
    }

    /// Log keys that map to an event, without the version suffix.
    ///
    /// Order does not matter: matching happens on the normalized key, so
    /// `NETWORK_WAN_FAILED` can never match `NETWORK_WAN_FAILED_TEMPORARY`.
    private static let keyTable: [(key: String, event: MonitoredEvent)] = [
        ("NETWORK_WAN_FAILED", .internetDown),
        ("NETWORK_WAN_RESTORED", .internetRestored),
        ("NETWORK_WAN_FAILED_MULTIPLE_TIMES", .internetDownMultipleTimes),
        ("NETWORK_WAN_FAILED_TEMPORARY", .internetDownTemporary),
        ("ISP_PACKET_LOSS", .packetLoss),
        ("ISP_HIGH_LATENCY", .highLatency),
    ]

    /// Identifies the monitored event of a log entry, or `nil` when the entry
    /// is not monitored (client connect/disconnect, AUDIT, firmware update, ...).
    ///
    /// Threats are recognized by `category == "SECURITY"` alone, so new
    /// `THREAT_DETECTED_*` keys are picked up without a code change.
    public static func detect(category: String, key: String) -> MonitoredEvent? {
        if category.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "SECURITY" {
            return .threatDetected
        }
        let normalized = normalizedKey(key)
        return keyTable.first { $0.key == normalized }?.event
    }

    /// Removes a trailing version suffix such as `_2` or `_V3`.
    ///
    /// `NETWORK_WAN_FAILED_2` becomes `NETWORK_WAN_FAILED`, so a future `_3`
    /// release keeps working. Repeated suffixes are removed as well.
    public static func normalizedKey(_ key: String) -> String {
        var result = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        while let range = result.range(of: "_V?[0-9]+$", options: .regularExpression) {
            result.removeSubrange(range)
        }
        return result
    }
}

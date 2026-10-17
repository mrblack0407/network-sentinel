import Foundation

/// Key of a WAN line: entries and outages without a `WAN_ID` share one bucket,
/// exactly like the outage pairing does.
enum WANLineKey {
    static func of(_ wanID: String?) -> String { wanID ?? "" }
}

/// What one 概览 线路卡片 counts for the last 24 hours.
///
/// The window ends at the injected `now` and is 24 hours long. An outage that
/// started before the window, or that is still open, counts with the part that
/// falls inside the window, so the three numbers describe the same window the
/// 过去 24 小时 色条 draws.
public struct WANLineStatistics: Equatable {
    /// Outages of the line that overlap the window.
    public let outageCount: Int
    /// Seconds of outage inside the window.
    public let totalOutageSeconds: Int
    /// Longest single outage inside the window, `nil` when there was none.
    public let longestOutageSeconds: Int?

    public init(outageCount: Int, totalOutageSeconds: Int, longestOutageSeconds: Int?) {
        self.outageCount = max(0, outageCount)
        self.totalOutageSeconds = max(0, totalOutageSeconds)
        self.longestOutageSeconds = longestOutageSeconds.map { max(0, $0) }
    }

    /// The empty window.
    public static let none = WANLineStatistics(
        outageCount: 0,
        totalOutageSeconds: 0,
        longestOutageSeconds: nil
    )

    /// `25 秒`, for the 累计断网 column.
    public var totalText: String { DurationText.text(seconds: totalOutageSeconds) }

    /// `24 秒`, or `—` when the window holds no outage.
    public var longestText: String {
        longestOutageSeconds.map(DurationText.text(seconds:)) ?? "—"
    }

    /// The three columns in one sentence, for a screen reader.
    public var accessibilityText: String {
        T(.statsLineReadOut, outageCount, totalText, longestText)
    }
}

/// Counts the 24-hour statistics of one 概览 线路卡片.
public enum WANLineStatisticsBuilder {
    /// Length of the window of the card and of the 过去 24 小时 色条.
    public static let window: TimeInterval = 24 * 60 * 60

    /// The outages of one line that overlap the window ending at `now`, oldest first.
    ///
    /// - Parameters:
    ///   - outages: all outages of the local log.
    ///   - wanID: the line to look at; `nil` matches the outages that carried no line.
    ///   - now: the end of the window.
    public static func overlappingOutages(_ outages: [Outage], wanID: String?, now: Date) -> [Outage] {
        let windowStart = now.addingTimeInterval(-window)
        let key = WANLineKey.of(wanID)

        return outages
            .filter { WANLineKey.of($0.wanID) == key }
            .filter { outage in
                let end = outage.end ?? now
                return outage.start < now && end > windowStart
            }
            .sorted { $0.start < $1.start }
    }

    /// The three columns of the card.
    public static func statistics(outages: [Outage], wanID: String?, now: Date) -> WANLineStatistics {
        let windowStart = now.addingTimeInterval(-window)
        let lineOutages = overlappingOutages(outages, wanID: wanID, now: now)

        var total = 0
        var longest: Int?
        for outage in lineOutages {
            let seconds = secondsInWindow(of: outage, windowStart: windowStart, now: now)
            total += seconds
            longest = max(longest ?? 0, seconds)
        }

        return WANLineStatistics(
            outageCount: lineOutages.count,
            totalOutageSeconds: total,
            longestOutageSeconds: longest
        )
    }

    /// Seconds of one outage that fall inside the window.
    ///
    /// An outage that lies completely inside the window keeps the `DURATION` the
    /// gateway reported, so the card and the 菜单栏弹出面板 tell the same length.
    /// A clipped outage is measured from its timestamps.
    private static func secondsInWindow(of outage: Outage, windowStart: Date, now: Date) -> Int {
        let end = outage.end ?? now
        let clippedStart = max(outage.start, windowStart)
        let clippedEnd = min(end, now)
        guard clippedEnd > clippedStart else { return 0 }

        let isWhole = clippedStart == outage.start && clippedEnd == end
        if isWhole, let reported = outage.durationWholeSeconds {
            return reported
        }
        return Int(clippedEnd.timeIntervalSince(clippedStart).rounded())
    }
}

/// 检测到威胁 entries of the last 24 hours, split by severity.
public struct ThreatStatistics: Equatable {
    /// 非常高 threats of the window.
    public let veryHigh: Int
    /// 高 threats of the window.
    public let high: Int
    /// 中 and 低 threats, and threats whose severity the gateway did not send.
    public let mediumAndBelow: Int

    public init(veryHigh: Int, high: Int, mediumAndBelow: Int) {
        self.veryHigh = max(0, veryHigh)
        self.high = max(0, high)
        self.mediumAndBelow = max(0, mediumAndBelow)
    }

    /// All threats of the window.
    public var total: Int { veryHigh + high + mediumAndBelow }

    /// The empty window.
    public static let none = ThreatStatistics(veryHigh: 0, high: 0, mediumAndBelow: 0)

    /// The three columns in one sentence, for a screen reader.
    public var accessibilityText: String {
        T(.statsThreatReadOut, total, veryHigh, high, mediumAndBelow)
    }
}

/// Counts the 检测到威胁 card of 概览.
public enum ThreatStatisticsBuilder {
    /// The card counts the same window as `MonitorLogSpec.summary`.
    public static func statistics(events: [MonitoredLogEvent], now: Date) -> ThreatStatistics {
        let windowStart = now.addingTimeInterval(-WANLineStatisticsBuilder.window)
        let threats = events.filter {
            $0.event == .threatDetected && $0.timestamp >= windowStart && $0.timestamp <= now
        }

        return ThreatStatistics(
            veryHigh: threats.filter { $0.severity == .veryHigh }.count,
            high: threats.filter { $0.severity == .high }.count,
            // An unknown severity counts as 低, like the notification threshold.
            mediumAndBelow: threats.filter {
                NotificationSettings.effectiveSeverity($0.severity) < .high
            }.count
        )
    }
}

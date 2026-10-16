import Foundation

/// Writes the current filter of the 日志 page as a CSV file.
///
/// The columns are 时间, 事件, 严重性, 线路 and 描述. The 描述 is the Chinese text
/// the notification body uses, so the file never carries the English
/// `message_raw` of the gateway. The output starts with a UTF-8 byte order mark
/// and quotes every field that holds a comma, a quote or a line break, so Excel
/// opens the file with the Chinese text intact.
public enum LogCSVExporter {
    /// Column titles, in order.
    public static let header = ["时间", "事件", "严重性", "线路", "描述"]

    /// Byte order mark of the file; Excel needs it to read UTF-8.
    public static let byteOrderMark = "\u{FEFF}"

    /// Line ending of the file, as RFC 4180 asks for.
    public static let lineEnding = "\r\n"

    /// Format of the 时间 column.
    public static let dateFormat = "yyyy-MM-dd HH:mm:ss"

    /// The whole file as text, without the byte order mark.
    ///
    /// - Parameters:
    ///   - events: the entries of the current filter, in the order to write them.
    ///   - timeZone: zone of the 时间 column; the local zone by default.
    public static func csv(
        events: [MonitoredLogEvent],
        timeZone: TimeZone = .current
    ) -> String {
        let rows = [header] + events.map { row(for: $0, timeZone: timeZone) }
        return rows
            .map { $0.map(escaped).joined(separator: ",") }
            .joined(separator: lineEnding)
            + lineEnding
    }

    /// The whole file as UTF-8 data, byte order mark included.
    public static func data(
        events: [MonitoredLogEvent],
        timeZone: TimeZone = .current
    ) -> Data {
        let text = byteOrderMark + csv(events: events, timeZone: timeZone)
        return Data(text.utf8)
    }

    /// The fields of one entry, in the column order.
    public static func row(for event: MonitoredLogEvent, timeZone: TimeZone = .current) -> [String] {
        [
            timestampText(event.timestamp, timeZone: timeZone),
            event.event.displayName,
            event.severity?.displayName ?? "未知",
            event.wanID ?? "",
            description(of: event),
        ]
    }

    /// The Chinese description of one entry.
    ///
    /// Reuses the notification body, so the table, the notification and the file
    /// never tell different stories.
    public static func description(of event: MonitoredLogEvent) -> String {
        planner.notificationBody(for: event)
    }

    /// `2026-10-13 12:00:00` in the given zone.
    public static func timestampText(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        // A fixed, numeric format: the locale must not change the digits.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = dateFormat
        return formatter.string(from: date)
    }

    /// `NetworkSentinel-日志-20261013.csv`, named after the day of the export.
    public static func defaultFileName(date: Date = Date(), timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd"
        return "NetworkSentinel-日志-\(formatter.string(from: date)).csv"
    }

    /// One CSV field: quoted and doubled when it holds a comma, a quote or a
    /// line break.
    public static func escaped(_ field: String) -> String {
        // The line break test runs on the scalars: Swift counts a `\r\n` pair as
        // a single `Character`, so `contains("\n")` alone would miss it.
        let hasLineBreak = field.unicodeScalars.contains { $0 == "\n" || $0 == "\r" }
        let needsQuotes = field.contains(",")
            || field.contains("\"")
            || hasLineBreak
        guard needsQuotes else { return field }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    /// The planner only formats text, so one shared value is enough.
    private static let planner = NotificationPlanner()
}

import XCTest
@testable import SentinelCore

/// The CSV export of the 全部日志 page.
final class LogCSVExportTests: XCTestCase {
    private let now = LogicFixture.now
    private let utc = TimeZone(identifier: "UTC")!
    private let shanghai = TimeZone(identifier: "Asia/Shanghai")!

    /// 2023-11-14 22:13:20 UTC.
    private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func event(
        id: String,
        _ kind: MonitoredEvent = .internetDown,
        at date: Date,
        severity: LogSeverity? = .veryHigh,
        wanID: String? = "WAN1",
        ispName: String? = "China Telecom",
        source: String? = nil
    ) throws -> MonitoredLogEvent {
        try LogicFixture.monitoredEvent(
            id: id,
            event: kind,
            at: date,
            wanID: wanID,
            ispName: ispName,
            severity: severity,
            source: source.map { ThreatEndpoint(value: $0, isClient: true) }
        )
    }

    // MARK: - Columns

    func testTheHeaderHasTheFiveColumns() {
        let csv = LogCSVExporter.csv(events: [], timeZone: utc)

        XCTAssertEqual(csv, "时间,事件,严重性,线路,描述\r\n")
    }

    func testTheRowOfOneEvent() throws {
        let entry = try event(id: "down", at: fixedDate)

        let rows = LogCSVExporter.csv(events: [entry], timeZone: utc)
            .split(separator: "\r\n", omittingEmptySubsequences: true)

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(
            rows[1],
            "2023-11-14 22:13:20,互联网中断,非常高,WAN1,WAN1 (China Telecom) 已断开。"
        )
    }

    func testTheTimestampUsesTheGivenTimeZone() throws {
        let entry = try event(id: "down", at: fixedDate)

        XCTAssertTrue(
            LogCSVExporter.csv(events: [entry], timeZone: shanghai).contains("2023-11-15 06:13:20"),
            "the 时间 column must follow the time zone of the export"
        )
    }

    func testAnUnknownSeverityIsWrittenAsUnknown() throws {
        let entry = try event(id: "down", at: fixedDate, severity: nil)

        XCTAssertEqual(LogCSVExporter.row(for: entry, timeZone: utc)[2], "未知")
    }

    func testAnEntryWithoutALineLeavesTheColumnEmpty() throws {
        let entry = try event(id: "threat", .threatDetected, at: fixedDate, wanID: nil, ispName: nil, source: "203.0.113.45")

        let row = LogCSVExporter.row(for: entry, timeZone: utc)

        XCTAssertEqual(row[3], "")
        XCTAssertEqual(row[4], "来自 203.0.113.45 到 未知 的入侵尝试。")
    }

    func testTheDescriptionIsTheChineseNotificationText() throws {
        let entry = try event(id: "restored", .internetRestored, at: fixedDate, severity: .low)

        XCTAssertEqual(
            LogCSVExporter.description(of: entry),
            NotificationPlanner().notificationBody(for: entry)
        )
        XCTAssertEqual(LogCSVExporter.row(for: entry, timeZone: utc)[4], "WAN1 (China Telecom) 已恢复，断网 未知。")
    }

    // MARK: - Escaping

    func testAFieldWithoutSpecialCharactersIsNotQuoted() {
        XCTAssertEqual(LogCSVExporter.escaped("WAN1"), "WAN1")
        XCTAssertEqual(LogCSVExporter.escaped("检测到威胁"), "检测到威胁")
    }

    func testACommaIsQuoted() {
        XCTAssertEqual(LogCSVExporter.escaped("WAN1, WAN2"), "\"WAN1, WAN2\"")
    }

    func testAQuoteIsDoubled() {
        XCTAssertEqual(LogCSVExporter.escaped("a \"quoted\" name"), "\"a \"\"quoted\"\" name\"")
    }

    func testALineBreakIsQuoted() {
        XCTAssertEqual(LogCSVExporter.escaped("first\nsecond"), "\"first\nsecond\"")
        XCTAssertEqual(LogCSVExporter.escaped("first\r\nsecond"), "\"first\r\nsecond\"")
    }

    func testADescriptionWithACommaSurvivesTheRoundTrip() throws {
        // The source of a threat can carry a comma; the column must not split.
        let entry = try event(
            id: "threat",
            .threatDetected,
            at: fixedDate,
            wanID: nil,
            ispName: nil,
            source: "10.0.0.5, 10.0.0.6"
        )

        let line = LogCSVExporter.csv(events: [entry], timeZone: utc)
            .split(separator: "\r\n", omittingEmptySubsequences: true)[1]

        XCTAssertTrue(line.hasSuffix("\"来自 10.0.0.5, 10.0.0.6 到 未知 的入侵尝试。\""))
        // Four commas separate five columns; the one inside the quotes is not a
        // separator.
        XCTAssertEqual(line.filter { $0 == "," }.count, 5)
    }

    // MARK: - File

    func testTheFileStartsWithAByteOrderMark() throws {
        let entry = try event(id: "down", at: fixedDate)

        let data = LogCSVExporter.data(events: [entry], timeZone: utc)

        XCTAssertEqual(Array(data.prefix(3)), [0xEF, 0xBB, 0xBF])
        XCTAssertEqual(String(decoding: data.dropFirst(3), as: UTF8.self), LogCSVExporter.csv(events: [entry], timeZone: utc))
    }

    func testTheFileEndsWithALineBreak() {
        XCTAssertTrue(LogCSVExporter.csv(events: [], timeZone: utc).hasSuffix("\r\n"))
    }

    func testTheDefaultFileNameCarriesTheDay() {
        XCTAssertEqual(
            LogCSVExporter.defaultFileName(date: fixedDate, timeZone: utc),
            "NetworkSentinel-日志-20231114.csv"
        )
        // Shanghai is eight hours ahead: the same instant is the next day there.
        XCTAssertEqual(
            LogCSVExporter.defaultFileName(date: fixedDate, timeZone: shanghai),
            "NetworkSentinel-日志-20231115.csv"
        )
    }

    func testTheExportKeepsTheOrderItWasGiven() throws {
        let newer = try event(id: "newer", at: now)
        let older = try event(id: "older", .internetRestored, at: now.addingTimeInterval(-600))

        let rows = LogCSVExporter.csv(events: [newer, older], timeZone: utc)
            .split(separator: "\r\n", omittingEmptySubsequences: true)

        XCTAssertEqual(rows.count, 3)
        XCTAssertTrue(rows[1].contains("互联网中断"))
        XCTAssertTrue(rows[2].contains("互联网已恢复"))
    }
}

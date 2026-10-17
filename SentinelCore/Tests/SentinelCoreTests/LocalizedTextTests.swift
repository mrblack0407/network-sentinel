import XCTest
@testable import SentinelCore

/// The one text table of the app: every text has a Chinese and an English
/// version, and every part of `SentinelCore` reads the language of the moment.
final class LocalizedTextTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AppText.language = .chinese
    }

    override func tearDown() {
        // A check that switches the language never leaks it into the next one.
        AppText.language = .chinese
        super.tearDown()
    }

    // MARK: - The table

    func testEveryKeyHasBothLanguages() {
        for key in TextKey.allCases {
            let translation = TextTable.all[key]
            XCTAssertNotNil(translation, "no text for \(key.rawValue)")
            let chinese = translation?.chinese.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let english = translation?.english.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            XCTAssertFalse(chinese.isEmpty, "empty Chinese text for \(key.rawValue)")
            // English leaves these counting units out on purpose.
            if ![TextKey.commonUnitTimes, .commonUnitItems].contains(key) {
                XCTAssertFalse(english.isEmpty, "empty English text for \(key.rawValue)")
            }
        }
    }

    func testTheTableHoldsNoTextWithoutAKey() {
        XCTAssertEqual(TextTable.all.count, TextKey.allCases.count)
    }

    func testTheRawValuesOfTheKeysAreUnique() {
        let rawValues = TextKey.allCases.map(\.rawValue)
        XCTAssertEqual(Set(rawValues).count, rawValues.count)
    }

    /// A text that takes arguments takes the same ones in both languages, so a
    /// `String(format:)` call can never print a raw placeholder.
    func testBothLanguagesUseTheSamePlaceholders() {
        for key in TextKey.allCases {
            guard let translation = TextTable.all[key] else { continue }
            XCTAssertEqual(
                placeholders(in: translation.chinese),
                placeholders(in: translation.english),
                "placeholders of \(key.rawValue) differ"
            )
        }
    }

    // MARK: - The language source

    func testTheChineseTextsComeFirst() {
        XCTAssertEqual(AppText.language, .chinese)
        XCTAssertEqual(MonitoredEvent.internetDown.displayName, "互联网中断")
        XCTAssertEqual(LogSeverity.veryHigh.displayName, "非常高")
    }

    func testAFixedSettingWinsOverTheMac() {
        AppText.use(.english, preferredLanguages: ["zh-Hans-CN"])
        XCTAssertEqual(AppText.language, .english)

        AppText.use(.chinese, preferredLanguages: ["en-US"])
        XCTAssertEqual(AppText.language, .chinese)

        AppText.use(.system, preferredLanguages: ["zh-Hans-CN"])
        XCTAssertEqual(AppText.language, .chinese)

        AppText.use(.system, preferredLanguages: ["en-US"])
        XCTAssertEqual(AppText.language, .english)
    }

    func testTheLocaleFollowsTheLanguage() {
        AppText.language = .chinese
        XCTAssertEqual(AppText.localeIdentifier, "zh_Hans_CN")
        // Foundation may normalize the identifier (zh_Hans_CN → zh_CN).
        XCTAssertTrue(AppText.locale.identifier.hasPrefix("zh"))

        AppText.language = .english
        XCTAssertEqual(AppText.localeIdentifier, "en_US")
        XCTAssertEqual(AppText.locale.identifier, "en_US")
    }

    func testTheLanguageIsReadWhenTheTextIsBuilt() {
        let event = MonitoredEvent.internetDown

        XCTAssertEqual(event.displayName, "互联网中断")
        AppText.language = .english
        XCTAssertEqual(event.displayName, "Internet Down")
        AppText.language = .chinese
        XCTAssertEqual(event.displayName, "互联网中断")
    }

    func testScopedLanguagePutsTheOldOneBack() {
        AppText.language = .chinese

        let english = AppText.withLanguage(.english) { MonitoredEvent.packetLoss.displayName }

        XCTAssertEqual(english, "Packet Loss Detected")
        XCTAssertEqual(AppText.language, .chinese)
        XCTAssertEqual(MonitoredEvent.packetLoss.displayName, "检测到丢包")
    }

    // MARK: - The names of the app

    func testTheEnglishEventNamesAreTheUniFiOnes() {
        AppText.withLanguage(.english) {
            XCTAssertEqual(MonitoredEvent.internetDown.displayName, "Internet Down")
            XCTAssertEqual(MonitoredEvent.internetRestored.displayName, "Internet Restored")
            XCTAssertEqual(
                MonitoredEvent.internetDownMultipleTimes.displayName,
                "Multiple Internet Disconnections"
            )
            XCTAssertEqual(
                MonitoredEvent.internetDownTemporary.displayName,
                "Temporary Internet Disconnection"
            )
            XCTAssertEqual(MonitoredEvent.packetLoss.displayName, "Packet Loss Detected")
            XCTAssertEqual(MonitoredEvent.highLatency.displayName, "High Latency Detected")
            XCTAssertEqual(MonitoredEvent.threatDetected.displayName, "Threat Detected")
        }
    }

    func testTheSeverityNamesInBothLanguages() {
        XCTAssertEqual(LogSeverity.allCases.map(\.displayName), ["低", "中", "高", "非常高"])
        AppText.withLanguage(.english) {
            XCTAssertEqual(LogSeverity.allCases.map(\.displayName), ["Low", "Medium", "High", "Very High"])
        }
    }

    func testTheWANStatesInBothLanguages() {
        XCTAssertEqual(SnapshotWANState.allCasesForTest.map(\.displayName), ["在线", "离线", "未启用", "备用"])
        AppText.withLanguage(.english) {
            XCTAssertEqual(SnapshotWANState.allCasesForTest.map(\.displayName), ["Online", "Offline", "Disabled", "Standby"])
        }
    }

    func testTheLineOfThePanelInBothLanguages() {
        let line = WANLineStatus(
            id: "WAN1",
            ispName: "China Telecom",
            state: .offline,
            outageStartedAt: Date(timeIntervalSince1970: 0)
        )
        let later = Date(timeIntervalSince1970: 180)

        XCTAssertEqual(line.detailText(now: later), "已断开 3 分")
        XCTAssertEqual(line.accessibilityText(now: later), "WAN1，China Telecom，已断开 3 分")

        AppText.withLanguage(.english) {
            XCTAssertEqual(line.detailText(now: later), "Down 3 min")
            XCTAssertEqual(line.accessibilityText(now: later), "WAN1, China Telecom, Down 3 min")
        }
    }

    func testTheMenuBarReadOutInBothLanguages() {
        let status = MenuBarStatusBuilder.status(
            gatewayName: "Gateway",
            queryIntervalSeconds: 30,
            connectionState: .connected,
            errorDescription: nil,
            gatewayStatus: nil,
            events: [],
            now: Date()
        )

        XCTAssertEqual(status.accessibilityText, "Network Sentinel：近 24 小时没有中及以上的事件")
        AppText.withLanguage(.english) {
            XCTAssertEqual(
                status.accessibilityText,
                "Network Sentinel: No Medium or higher events in the last 24 hours"
            )
        }
    }

    // MARK: - 测试连接 and the gateway errors

    func testTheConnectionErrorFollowsTheLanguage() {
        let error = ConnectionTestError.unauthorized

        XCTAssertEqual(error.errorDescription, "API Key 不对或没有权限读取日志")
        AppText.withLanguage(.english) {
            XCTAssertEqual(error.errorDescription, "The API Key is wrong, or it may not read the log")
        }
    }

    func testTheGatewayErrorFollowsTheLanguage() {
        let error = SentinelAPIError.unauthorized(statusCode: 401)

        XCTAssertEqual(error.errorDescription, "API Key 无效或没有权限（HTTP 401）。")
        AppText.withLanguage(.english) {
            XCTAssertEqual(error.errorDescription, "The API Key is invalid or has no permission (HTTP 401).")
        }
    }

    func testTheAddressErrorFollowsTheLanguage() {
        XCTAssertEqual(GatewayAddressError.empty.errorDescription, "请输入 UniFi 网关地址")
        AppText.withLanguage(.english) {
            XCTAssertEqual(GatewayAddressError.empty.errorDescription, "Enter the UniFi gateway address")
        }
    }

    func testTheBarkErrorFollowsTheLanguage() {
        XCTAssertEqual(BarkError.invalidKey.errorDescription, "Bark Key 不对，请在「通知」里重新填。")
        AppText.withLanguage(.english) {
            XCTAssertEqual(
                BarkError.invalidKey.errorDescription,
                "The Bark Key is wrong. Enter it again in Notifications."
            )
        }
    }

    // MARK: - Notifications

    func testTheNotificationBodyFollowsTheLanguage() throws {
        let entry = try makeRestoredEntry(seconds: 85)
        let planner = NotificationPlanner()

        XCTAssertEqual(planner.notificationBody(for: entry), "WAN1 (China Telecom) 已恢复，断网 1 分 25 秒。")
        AppText.withLanguage(.english) {
            XCTAssertEqual(planner.notificationBody(for: entry), "WAN1 (China Telecom) is back, down for 1 min 25 s.")
        }
    }

    func testTheMergedCountLineFollowsTheLanguage() {
        XCTAssertEqual(T(.bodyMergedCount, 3), "10 分钟内同类 3 条。")
        AppText.withLanguage(.english) {
            XCTAssertEqual(T(.bodyMergedCount, 3), "3 more of the same kind within 10 minutes.")
        }
    }

    func testTheStateChangeNotificationFollowsTheLanguage() {
        let kind = MonitorLogSpec.stateChangeNotification(
            previous: .connected,
            current: .reconnecting,
            address: "https://192.168.8.254",
            errorDescription: "timeout"
        )

        XCTAssertEqual(kind?.title, "UniFi 网关连不上")
        XCTAssertEqual(kind?.body, "无法连接到 https://192.168.8.254：timeout\n请在「连接」里检查网关地址。")

        // A notification is built and sent at once, so it is built in English here.
        AppText.withLanguage(.english) {
            let kind = MonitorLogSpec.stateChangeNotification(
                previous: .connected,
                current: .reconnecting,
                address: "https://192.168.8.254",
                errorDescription: "timeout"
            )
            XCTAssertEqual(kind?.title, "UniFi gateway unreachable")
            XCTAssertEqual(
                kind?.body,
                "Cannot reach https://192.168.8.254: timeout\nCheck the gateway address in Connection."
            )
        }
    }

    func testTheWakeSummaryFollowsTheLanguage() {
        let event = try! XCTUnwrap(
            try LogicFixture.entry(id: "restored", event: .internetRestored, at: LogicFixture.now)
                .monitoredLogEvent
        )
        let summary = MonitorLogSpec.wakeSummary(for: [event]) { _ in "9:44" }

        XCTAssertEqual(summary?.title, "睡眠期间有 1 条新日志")
        XCTAssertEqual(summary?.body, "WAN1 Internet Restored（9:44）")

        AppText.withLanguage(.english) {
            let english = MonitorLogSpec.wakeSummary(for: [event]) { _ in "9:44" }
            XCTAssertEqual(english?.title, "New log entries while asleep: 1")
            XCTAssertEqual(english?.body, "WAN1 Internet Restored (9:44)")
        }
    }

    // MARK: - 日志 and the export

    func testThePagerFollowsTheLanguage() {
        XCTAssertEqual(LogPagination(totalCount: 126).rangeText, "第 1–25 条，共 126 条")
        XCTAssertEqual(LogPagination(totalCount: 0).rangeText, "共 0 条")

        AppText.withLanguage(.english) {
            XCTAssertEqual(LogPagination(totalCount: 126).rangeText, "1–25 of 126")
            XCTAssertEqual(LogPagination(totalCount: 0).rangeText, "No entries")
        }
    }

    func testTheLogFiltersFollowTheLanguage() {
        XCTAssertEqual(LogTimeRange.allCases.map(\.title), ["1 天", "7 天", "30 天"])
        XCTAssertEqual(LogCategory.allCases.map(\.title), ["全部", "网络", "威胁"])

        AppText.withLanguage(.english) {
            XCTAssertEqual(LogTimeRange.allCases.map(\.title), ["1 day", "7 days", "30 days"])
            XCTAssertEqual(LogCategory.allCases.map(\.title), ["All", "Network", "Threats"])
        }
    }

    func testTheCSVFollowsTheLanguage() {
        XCTAssertEqual(LogCSVExporter.csv(events: []), "时间,事件,严重性,线路,描述\r\n")

        AppText.withLanguage(.english) {
            XCTAssertEqual(LogCSVExporter.header, ["Time", "Event", "Severity", "Line", "Description"])
            XCTAssertEqual(LogCSVExporter.csv(events: []), "Time,Event,Severity,Line,Description\r\n")
            let name = LogCSVExporter.defaultFileName(
                date: Date(timeIntervalSince1970: 1_700_000_000),
                timeZone: TimeZone(identifier: "UTC")!
            )
            XCTAssertEqual(name, "NetworkSentinel-log-20231114.csv")
        }
    }

    // MARK: - The status line of the 连接 card

    func testTheMonitorStatusLineFollowsTheLanguage() {
        XCTAssertEqual(MonitorLogSpec.MonitorStatusText.connected(secondsAgo: 42).text, "已连上，42 秒前查过")
        XCTAssertEqual(MonitorLogSpec.MonitorStatusText.notQueried.text, "已连上，还没查过")

        AppText.withLanguage(.english) {
            XCTAssertEqual(
                MonitorLogSpec.MonitorStatusText.connected(secondsAgo: 42).text,
                "Connected, checked 42 s ago"
            )
            XCTAssertEqual(MonitorLogSpec.MonitorStatusText.notQueried.text, "Connected, not checked yet")
        }
    }

    // MARK: - Helpers

    /// `%@` and `%d` in the order they appear.
    private func placeholders(in text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: "%[@d]")
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }

    private func makeRestoredEntry(seconds: Int) throws -> MonitoredLogEvent {
        let entry = try LogicFixture.entry(
            id: "restored",
            event: .internetRestored,
            at: LogicFixture.now,
            duration: "\(seconds)s"
        )
        return try XCTUnwrap(entry.monitoredLogEvent)
    }
}

private extension SnapshotWANState {
    /// Every case in the order of the enum, for the checks of the names.
    static var allCasesForTest: [SnapshotWANState] {
        [.online, .offline, .disabled, .standby]
    }
}

import XCTest
@testable import SentinelCore

final class MenuBarStatusTests: XCTestCase {
    /// The state of the menu bar built from the injected clock.
    private func status(
        connectionState: GatewayConnectionState = .connected,
        errorDescription: String? = nil,
        gatewayStatus: GatewayStatus? = nil,
        events: [MonitoredLogEvent] = [],
        gatewayName: String? = "Dream Machine Pro Max",
        queryIntervalSeconds: Int = 30
    ) -> MenuBarStatus {
        MenuBarStatusBuilder.status(
            gatewayName: gatewayName,
            queryIntervalSeconds: queryIntervalSeconds,
            connectionState: connectionState,
            errorDescription: errorDescription,
            gatewayStatus: gatewayStatus,
            events: events,
            now: LogicFixture.now
        )
    }

    // MARK: - The dot of the 菜单栏图标

    func testTheDotIsQuietWithoutEvents() {
        let result = status(gatewayStatus: LogicFixture.gatewayStatus())

        XCTAssertEqual(result.indicator, .quiet)
        XCTAssertNil(result.highestSeverity)
    }

    func testALowEventLeavesTheDotQuiet() throws {
        let events = try [
            LogicFixture.monitoredEvent(id: "loss", event: .packetLoss, at: LogicFixture.time(-600), severity: .low)
        ]

        XCTAssertEqual(status(events: events).indicator, .quiet)
    }

    func testMediumOrHighTurnsTheDotYellow() throws {
        for severity in [LogSeverity.medium, .high] {
            let events = try [
                LogicFixture.monitoredEvent(id: "down", event: .internetDown, at: LogicFixture.time(-600), severity: severity)
            ]

            XCTAssertEqual(status(events: events).indicator, .warning, "severity \(severity.rawValue)")
        }
    }

    func testVeryHighTurnsTheDotRed() throws {
        let events = try [
            LogicFixture.monitoredEvent(id: "down", event: .internetDown, at: LogicFixture.time(-600), severity: .veryHigh)
        ]

        XCTAssertEqual(status(events: events).indicator, .critical)
    }

    func testALineThatIsDownTurnsTheDotRed() {
        let result = status(gatewayStatus: LogicFixture.gatewayStatus(wan2: .offline))

        XCTAssertEqual(result.indicator, .critical)
        XCTAssertTrue(result.lines[1].isDown)
    }

    func testABrokenConnectionTurnsTheDotGray() throws {
        // A 非常高 event does not win over a connection the app cannot trust.
        let events = try [
            LogicFixture.monitoredEvent(id: "down", event: .internetDown, at: LogicFixture.time(-600), severity: .veryHigh)
        ]

        for state in [GatewayConnectionState.reconnecting, .apiKeyRejected, .certificateChanged] {
            XCTAssertEqual(status(connectionState: state, events: events).indicator, .disconnected, "state \(state.rawValue)")
        }
    }

    // MARK: - The WAN lines

    func testTheLinesFollowTheGatewayAndTheLog() throws {
        let events = try [
            LogicFixture.monitoredEvent(
                id: "wan1", event: .internetDown, at: LogicFixture.time(-600),
                wanID: "WAN1", ispName: "China Telecom", severity: .veryHigh
            ),
            LogicFixture.monitoredEvent(
                id: "wan2", event: .internetDown, at: LogicFixture.time(-300),
                wanID: "WAN2", ispName: "China Unicom", severity: .medium
            ),
        ]

        let result = status(gatewayStatus: LogicFixture.gatewayStatus(wan2: .disabled), events: events)

        XCTAssertEqual(result.lines.map(\.id), ["WAN1", "WAN2"])
        XCTAssertEqual(result.lines[0].state, .online)
        XCTAssertEqual(result.lines[0].outageStartedAt, LogicFixture.time(-600))
        XCTAssertEqual(result.lines[0].ispName, "China Telecom")
        XCTAssertEqual(result.lines[1].ispName, "China Unicom")
        XCTAssertEqual(result.lines[1].state, .disabled)
        XCTAssertFalse(result.lines[1].isDown)
    }

    func testTheProviderNameComesFromTheNewestEntryOfThatLine() throws {
        let events = try [
            LogicFixture.monitoredEvent(
                id: "old", event: .internetDown, at: LogicFixture.time(-7_200),
                wanID: "WAN1", ispName: "China Unicom", severity: .high
            ),
            LogicFixture.monitoredEvent(
                id: "new", event: .internetRestored, at: LogicFixture.time(-600),
                wanID: "WAN1", ispName: "China Telecom", severity: .medium
            ),
        ]

        let result = status(gatewayStatus: LogicFixture.gatewayStatus(), events: events)

        XCTAssertEqual(result.lines.first?.ispName, "China Telecom")
    }

    func testTheLineWithoutALogEntryHasNoProviderName() {
        XCTAssertNil(status(gatewayStatus: LogicFixture.gatewayStatus()).lines.first?.ispName)
    }

    func testAnOpenOutageLeavesTheUpLineOnline() throws {
        let events = try [
            LogicFixture.monitoredEvent(id: "down", event: .internetDown, at: LogicFixture.time(-600), severity: .veryHigh)
        ]

        let line = try XCTUnwrap(status(gatewayStatus: LogicFixture.gatewayStatus(), events: events).lines.first)

        // The gateway reports the line as up, so the unrestored log entry only
        // stays available as the start of the outage.
        XCTAssertEqual(line.state, .online)
        XCTAssertEqual(line.outageStartedAt, LogicFixture.time(-600))
        XCTAssertFalse(line.isDown)
        XCTAssertEqual(line.detailText(now: LogicFixture.now), "在线")
    }

    func testASecondLineThatIsUpWhileTheFirstOneCarriesTheTrafficIsStandby() {
        let result = status(gatewayStatus: LogicFixture.gatewayStatus(wan2: .online))

        XCTAssertEqual(result.lines.map(\.state), [.online, .standby])
        XCTAssertFalse(result.lines[1].isDown)
        XCTAssertEqual(result.lines[1].detailText(now: LogicFixture.now), "备用")
        XCTAssertEqual(result.indicator, .quiet)
    }

    func testTheSecondLineIsOnlineWhileTheFirstLineIsDown() {
        let result = status(gatewayStatus: LogicFixture.gatewayStatus(wan1: .offline, wan2: .online))

        XCTAssertEqual(result.lines.map(\.state), [.offline, .online])
        XCTAssertTrue(result.lines[0].isDown)
        XCTAssertEqual(result.indicator, .critical)
        XCTAssertEqual(
            result.accessibilityText,
            "Network Sentinel：WAN1 已断开，WAN2 在线，有线路正在断网"
        )
    }

    func testTheRestoreDurationComesFromTheNewestFinishedOutage() throws {
        let events = try [
            LogicFixture.monitoredEvent(id: "down-old", event: .internetDown, at: LogicFixture.time(-7_200), severity: .veryHigh),
            LogicFixture.monitoredEvent(
                id: "restore-old", event: .internetRestored, at: LogicFixture.time(-7_100),
                severity: .medium, duration: "30s"
            ),
            LogicFixture.monitoredEvent(id: "down-new", event: .internetDown, at: LogicFixture.time(-3_600), severity: .veryHigh),
            LogicFixture.monitoredEvent(
                id: "restore-new", event: .internetRestored, at: LogicFixture.time(-3_000),
                severity: .medium, duration: "1m 40s"
            ),
        ]

        let line = try XCTUnwrap(status(gatewayStatus: LogicFixture.gatewayStatus(), events: events).lines.first)

        XCTAssertEqual(line.state, .online)
        XCTAssertNil(line.outageStartedAt)
        // A line that is up only says so: no 「已恢复」 time.
        XCTAssertEqual(line.detailText(now: LogicFixture.now), "在线")
    }

    func testADownLineCountsFromItsOpenOutage() throws {
        let events = try [
            LogicFixture.monitoredEvent(
                id: "down", event: .internetDown, at: LogicFixture.time(-180),
                wanID: "WAN2", ispName: "China Unicom", severity: .veryHigh
            )
        ]

        let result = status(gatewayStatus: LogicFixture.gatewayStatus(wan2: .offline), events: events)
        let line = result.lines[1]

        XCTAssertEqual(line.state, .offline)
        XCTAssertTrue(line.isDown)
        XCTAssertEqual(line.detailText(now: LogicFixture.now), "已断开 3 分")
        XCTAssertEqual(line.chipText, "WAN2 已断开")
        XCTAssertEqual(line.accessibilityText(now: LogicFixture.now), "WAN2，China Unicom，已断开 3 分")
    }

    func testTheDetailTextOfTheRemainingStates() {
        let online = WANLineStatus(id: "WAN1", ispName: nil, state: .online)
        XCTAssertEqual(online.detailText(now: LogicFixture.now), "在线")
        XCTAssertEqual(online.chipText, "WAN1 在线")
        XCTAssertEqual(online.accessibilityText(now: LogicFixture.now), "WAN1，在线")

        let down = WANLineStatus(id: "WAN1", ispName: nil, state: .offline)
        XCTAssertEqual(down.detailText(now: LogicFixture.now), "已断开")

        let disabled = WANLineStatus(id: "WAN2", ispName: nil, state: .disabled)
        XCTAssertEqual(disabled.detailText(now: LogicFixture.now), "未启用")
        XCTAssertEqual(disabled.chipText, "WAN2 未启用")

        let standby = WANLineStatus(id: "WAN2", ispName: nil, state: .standby)
        XCTAssertEqual(standby.detailText(now: LogicFixture.now), "备用")
        XCTAssertEqual(standby.chipText, "WAN2 备用")
    }

    func testThereAreNoLinesWithoutAGatewayStatus() {
        let result = status(gatewayStatus: nil)

        XCTAssertTrue(result.lines.isEmpty)
        XCTAssertEqual(result.indicator, .quiet)
        XCTAssertEqual(result.accessibilityText, "Network Sentinel：近 24 小时没有中及以上的事件")
    }

    // MARK: - The 24-hour window

    func testTheListKeepsTheLast24HoursNewestFirst() throws {
        let events = try [
            LogicFixture.monitoredEvent(id: "recent", event: .internetDown, at: LogicFixture.time(-600), severity: .high),
            // Older than 24 hours: it is neither listed nor counted.
            LogicFixture.monitoredEvent(id: "old", event: .internetDown, at: LogicFixture.time(-90_000), severity: .veryHigh),
        ]

        let result = status(events: events)

        XCTAssertEqual(result.recentEvents.map(\.id), ["recent"])
        XCTAssertEqual(result.outageCount24h, 1)
        XCTAssertEqual(result.highestSeverity, .high)
    }

    func testTheCountsCoverOutagesAndThreatsOfTheWindow() throws {
        let events = try [
            LogicFixture.monitoredEvent(id: "down", event: .internetDown, at: LogicFixture.time(-600), severity: .veryHigh),
            LogicFixture.monitoredEvent(
                id: "threat", event: .threatDetected, at: LogicFixture.time(-1_800),
                wanID: nil, ispName: nil, severity: .high
            ),
            LogicFixture.monitoredEvent(id: "old-down", event: .internetDown, at: LogicFixture.time(-90_000), severity: .veryHigh),
        ]

        let result = status(events: events)

        XCTAssertEqual(result.outageCount24h, 1)
        XCTAssertEqual(result.threatCount24h, 1)
        XCTAssertEqual(result.recentEvents.count, 2)
    }

    // MARK: - Connection

    func testTheReasonLineOnlyAppearsForABrokenConnection() {
        XCTAssertNil(status(connectionState: .connected).connectionReason)
        XCTAssertEqual(
            status(connectionState: .reconnecting).connectionReason,
            "网关连不上"
        )
        XCTAssertEqual(
            status(connectionState: .reconnecting, errorDescription: "网络连不上").connectionReason,
            "网络连不上"
        )
        XCTAssertEqual(
            status(connectionState: .apiKeyRejected).connectionReason,
            "API Key 无效，请在「连接」里重新填"
        )
        XCTAssertEqual(
            status(connectionState: .certificateChanged).connectionReason,
            "UniFi 网关的证书变了，请在「连接」里重新测试连接"
        )
    }

    func testTheUnreachableFlagFollowsTheConnectionState() {
        XCTAssertTrue(status(connectionState: .reconnecting).isGatewayUnreachable)
        XCTAssertFalse(status(connectionState: .apiKeyRejected).isGatewayUnreachable)
        XCTAssertFalse(status(connectionState: .connected).isGatewayUnreachable)
    }

    // MARK: - Read-out and chip

    func testTheReadOutNamesTheLinesAndTheSeverity() throws {
        let events = try [
            LogicFixture.monitoredEvent(id: "down", event: .internetDown, at: LogicFixture.time(-600), severity: .veryHigh)
        ]

        let result = status(gatewayStatus: LogicFixture.gatewayStatus(wan2: .disabled), events: events)

        XCTAssertEqual(
            result.accessibilityText,
            "Network Sentinel：WAN1 在线，WAN2 未启用，近 24 小时有非常高的事件"
        )
    }

    func testTheReadOutOfABrokenConnectionNamesTheProblem() throws {
        let events = try [
            LogicFixture.monitoredEvent(id: "down", event: .internetDown, at: LogicFixture.time(-600), severity: .high)
        ]

        XCTAssertEqual(
            status(connectionState: .apiKeyRejected, events: events).accessibilityText,
            "Network Sentinel：API Key 无效"
        )
        XCTAssertEqual(
            status(connectionState: .certificateChanged).accessibilityText,
            "Network Sentinel：证书变了"
        )
    }

    func testTheReadOutWithAQuietDay() {
        XCTAssertEqual(
            status(gatewayStatus: LogicFixture.gatewayStatus()).accessibilityText,
            "Network Sentinel：WAN1 在线，近 24 小时没有中及以上的事件"
        )
    }

    // MARK: - Small rules

    func testTheQueryIntervalIsNeverBelowOneSecond() {
        XCTAssertEqual(status(queryIntervalSeconds: 0).queryIntervalSeconds, 1)
        XCTAssertEqual(status(queryIntervalSeconds: 15).queryIntervalSeconds, 15)
    }

    func testTheGatewayNameFallsBackToAnEmptyString() {
        XCTAssertEqual(status(gatewayName: nil).gatewayName, "")
        XCTAssertEqual(status(gatewayName: "Dream Machine Pro Max").gatewayName, "Dream Machine Pro Max")
    }

    // MARK: - Shared with the status file

    func testThePanelAndTheStatusFileAgreeOnTheLines() throws {
        let events = try [
            LogicFixture.monitoredEvent(
                id: "down", event: .internetDown, at: LogicFixture.time(-600),
                wanID: "WAN1", ispName: "China Telecom", severity: .veryHigh
            )
        ]
        let gateway = LogicFixture.gatewayStatus(wan2: .disabled)

        let panel = status(gatewayStatus: gateway, events: events)
        let snapshot = StatusSnapshotBuilder.snapshot(
            gatewayStatus: gateway,
            events: events,
            now: LogicFixture.now,
            isGatewayReachable: true
        )

        XCTAssertEqual(panel.lines.map(\.id), snapshot.wanInterfaces.map(\.id))
        XCTAssertEqual(panel.lines.map(\.ispName), snapshot.wanInterfaces.map(\.ispName))
        XCTAssertEqual(panel.lines.map(\.state), snapshot.wanInterfaces.map(\.state))
        XCTAssertEqual(panel.lines.map(\.outageStartedAt), snapshot.wanInterfaces.map(\.outageStartedAt))
    }
}

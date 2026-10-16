import XCTest
@testable import SentinelCore

final class StatusFileTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = try LogicFixture.makeTemporaryDirectory()
    }

    override func tearDownWithError() throws {
        LogicFixture.removeTemporaryDirectory(directory)
    }

    private func store(_ refresher: WidgetRefreshing = NoOpWidgetRefresher()) -> StatusFileStore {
        StatusFileStore(directory: directory, refresher: refresher)
    }

    /// A snapshot built from the injected clock and the gateway fixture.
    private func sampleSnapshot() -> StatusSnapshot {
        let events = (try? [
            LogicFixture.monitoredEvent(id: "down-1", event: .internetDown, at: LogicFixture.time(-3_600), severity: .veryHigh),
            LogicFixture.monitoredEvent(id: "restore-1", event: .internetRestored, at: LogicFixture.time(-3_500), severity: .medium, duration: "1m 40s"),
            LogicFixture.monitoredEvent(id: "threat-1", event: .threatDetected, at: LogicFixture.time(-1_800), wanID: nil, ispName: nil, severity: .high),
        ]) ?? []

        return StatusSnapshotBuilder.snapshot(
            gatewayStatus: LogicFixture.gatewayStatus(),
            events: events,
            now: LogicFixture.now,
            isGatewayReachable: true
        )
    }

    // MARK: - Round trip

    func testWriteAndReadBackAreIdentical() throws {
        let snapshot = sampleSnapshot()

        try store().write(snapshot)
        let restored = try XCTUnwrap(try store().read())

        XCTAssertEqual(restored, snapshot)
    }

    func testTheFileIsNamedStatusJSONInTheGivenDirectory() throws {
        let fileStore = store()
        XCTAssertEqual(fileStore.fileURL.lastPathComponent, "status.json")
        XCTAssertEqual(fileStore.fileURL.deletingLastPathComponent(), directory)
        XCTAssertEqual(StatusFileStore.fileName, "status.json")

        try fileStore.write(sampleSnapshot())

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileStore.fileURL.path))
    }

    func testReadingBeforeTheFirstWriteReturnsNil() throws {
        XCTAssertNil(try store().read())
    }

    func testTheDirectoryIsCreatedWhenItDoesNotExistYet() throws {
        let nested = directory.appendingPathComponent("AppGroup", isDirectory: true)

        try StatusFileStore(directory: nested).write(sampleSnapshot())

        XCTAssertNotNil(try StatusFileStore(directory: nested).read())
    }

    func testWritingTwiceReplacesTheFile() throws {
        var snapshot = sampleSnapshot()
        try store().write(snapshot)

        snapshot = StatusSnapshotBuilder.snapshot(
            gatewayStatus: LogicFixture.gatewayStatus(),
            events: [],
            now: LogicFixture.time(600),
            isGatewayReachable: false
        )
        try store().write(snapshot)

        let restored = try XCTUnwrap(try store().read())
        XCTAssertEqual(restored, snapshot)
        XCTAssertFalse(restored.isGatewayReachable)
    }

    // MARK: - Widget

    func testWritingRefreshesTheWidget() throws {
        let refresher = RecordingWidgetRefresher()

        try store(refresher).write(sampleSnapshot())
        XCTAssertEqual(refresher.refreshCount, 1)

        try store(refresher).write(sampleSnapshot())
        XCTAssertEqual(refresher.refreshCount, 2)
    }

    func testTheNoOpRefresherDoesNothing() {
        NoOpWidgetRefresher().refresh()
    }

    // MARK: - No secrets

    func testTheFileHasNoAPIKey() throws {
        try store().write(sampleSnapshot())

        let text = try String(contentsOf: store().fileURL, encoding: .utf8)

        XCTAssertFalse(text.isEmpty)
        XCTAssertFalse(text.contains("X-API-Key"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("apikey"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("api_key"))
        XCTAssertFalse(text.contains("keychain"))
        XCTAssertFalse(text.contains("192.168.8.254"))
    }

    func testTheFileIsReadableJSONWithTheExpectedFields() throws {
        try store().write(sampleSnapshot())

        let data = try Data(contentsOf: store().fileURL)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["gatewayName"] as? String, "Dream Machine Pro Max")
        XCTAssertEqual(object["isGatewayReachable"] as? Bool, true)
        XCTAssertEqual(object["outageCount24h"] as? Int, 1)
        XCTAssertEqual(object["threatCount24h"] as? Int, 1)
        XCTAssertEqual(object["highestSeverity24h"] as? String, "VERY_HIGH")
        XCTAssertNotNil(object["updatedAt"] as? String)
        XCTAssertEqual((object["wanInterfaces"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual((object["recentLogs"] as? [[String: Any]])?.count, 3)
    }

    func testTheSnapshotCanBeDecodedFromRawJSON() throws {
        let json: [String: Any] = [
            "gatewayName": "Gateway",
            "updatedAt": "2026-10-13T12:00:00Z",
            "isGatewayReachable": false,
            "wanInterfaces": [
                ["id": "WAN1", "state": "offline", "outageStartedAt": "2026-10-13T11:00:00Z"],
            ],
            "outageCount24h": 2,
            "threatCount24h": 0,
            "recentLogs": [],
        ]

        let data = try JSONSerialization.data(withJSONObject: json)
        let snapshot = try StatusFileStore.decoder.decode(StatusSnapshot.self, from: data)

        XCTAssertEqual(snapshot.gatewayName, "Gateway")
        XCTAssertFalse(snapshot.isGatewayReachable)
        XCTAssertEqual(snapshot.wan1?.state, .offline)
        XCTAssertNotNil(snapshot.wan1?.outageStartedAt)
        XCTAssertNil(snapshot.highestSeverity24h)
        XCTAssertEqual(snapshot.outageCount24h, 2)
    }

    // MARK: - Snapshot content

    func testTheSnapshotKeepsOnlyTheFiveNewestLogs() throws {
        let events = try (1...8).map { index in
            try LogicFixture.monitoredEvent(
                id: "down-\(index)",
                event: .internetDown,
                at: LogicFixture.time(TimeInterval(index * 60)),
                severity: .high
            )
        }

        let snapshot = StatusSnapshotBuilder.snapshot(
            gatewayStatus: LogicFixture.gatewayStatus(),
            events: events,
            now: LogicFixture.time(8 * 60),
            isGatewayReachable: true
        )

        XCTAssertEqual(snapshot.recentLogs.count, 5)
        XCTAssertEqual(snapshot.recentLogs.map(\.id), ["down-8", "down-7", "down-6", "down-5", "down-4"])
        XCTAssertEqual(snapshot.recentLogs.first?.event, .internetDown)
        XCTAssertEqual(snapshot.recentLogs.first?.severity, .high)
        XCTAssertEqual(snapshot.recentLogs.first?.title, "互联网中断")
    }

    func testTheRecentLogTitlesAreTheChineseEventNames() throws {
        let events = try [
            LogicFixture.monitoredEvent(id: "threat", event: .threatDetected, at: LogicFixture.time(-120), wanID: nil, ispName: nil, severity: .high),
            LogicFixture.monitoredEvent(id: "down", event: .internetDown, at: LogicFixture.time(-60), severity: .veryHigh),
        ]

        let summaries = StatusSnapshotBuilder.summaries(of: events)

        XCTAssertEqual(summaries.map(\.title), ["互联网中断", "检测到威胁"])
        XCTAssertEqual(summaries.map(\.event), [.internetDown, .threatDetected])
        XCTAssertEqual(summaries.map(\.id), ["down", "threat"])
    }

    func testTheCountsOnlyCoverTheLast24Hours() throws {
        let events = try [
            LogicFixture.monitoredEvent(id: "recent-down", event: .internetDown, at: LogicFixture.time(-3_600), severity: .medium),
            LogicFixture.monitoredEvent(id: "recent-threat", event: .threatDetected, at: LogicFixture.time(-7_200), wanID: nil, ispName: nil, severity: .low),
            // Older than 24 hours: kept in the recent list, not counted.
            LogicFixture.monitoredEvent(id: "old-down", event: .internetDown, at: LogicFixture.time(-90_000), severity: .veryHigh),
            LogicFixture.monitoredEvent(id: "old-threat", event: .threatDetected, at: LogicFixture.time(-100_000), wanID: nil, ispName: nil, severity: .low),
        ]

        let snapshot = StatusSnapshotBuilder.snapshot(
            gatewayStatus: LogicFixture.gatewayStatus(),
            events: events,
            now: LogicFixture.now,
            isGatewayReachable: true
        )

        XCTAssertEqual(snapshot.outageCount24h, 1)
        XCTAssertEqual(snapshot.threatCount24h, 1)
        XCTAssertEqual(snapshot.highestSeverity24h, .medium)
        XCTAssertEqual(snapshot.recentLogs.count, 4)
    }

    func testTheSnapshotHasNoHighestSeverityWithoutLogs() {
        let snapshot = StatusSnapshotBuilder.snapshot(
            gatewayStatus: LogicFixture.gatewayStatus(),
            events: [],
            now: LogicFixture.now,
            isGatewayReachable: true
        )

        XCTAssertNil(snapshot.highestSeverity24h)
        XCTAssertEqual(snapshot.outageCount24h, 0)
        XCTAssertEqual(snapshot.threatCount24h, 0)
        XCTAssertTrue(snapshot.recentLogs.isEmpty)
    }

    func testAnOpenOutageKeepsTheUpLineOnline() throws {
        let events = try [
            LogicFixture.monitoredEvent(id: "down", event: .internetDown, at: LogicFixture.time(-600), severity: .veryHigh)
        ]

        let snapshot = StatusSnapshotBuilder.snapshot(
            gatewayStatus: LogicFixture.gatewayStatus(),
            events: events,
            now: LogicFixture.now,
            isGatewayReachable: true
        )

        let wan1 = try XCTUnwrap(snapshot.wan1)
        // The gateway reports the line as up, so the unrestored entry only
        // stays visible as the start of the outage.
        XCTAssertEqual(wan1.state, .online)
        XCTAssertEqual(wan1.ispName, "China Telecom")
        XCTAssertEqual(wan1.outageStartedAt, LogicFixture.time(-600))
        XCTAssertEqual(snapshot.currentOutageWAN?.id, "WAN1")
    }

    func testASecondLineThatIsUpIsStandby() throws {
        let snapshot = StatusSnapshotBuilder.snapshot(
            gatewayStatus: LogicFixture.gatewayStatus(wan2: .online),
            events: [],
            now: LogicFixture.now,
            isGatewayReachable: true
        )

        XCTAssertEqual(snapshot.wan1?.state, .online)
        XCTAssertEqual(snapshot.wan2?.state, .standby)
        XCTAssertNil(snapshot.currentOutageWAN)
    }

    func testADownLineIsOfflineInTheStatusFile() throws {
        let snapshot = StatusSnapshotBuilder.snapshot(
            gatewayStatus: LogicFixture.gatewayStatus(wan2: .offline),
            events: [],
            now: LogicFixture.now,
            isGatewayReachable: true
        )

        XCTAssertEqual(snapshot.wan2?.state, .offline)
    }

    func testAClosedOutageLeavesTheLineOnline() throws {
        let events = try [
            LogicFixture.monitoredEvent(id: "down", event: .internetDown, at: LogicFixture.time(-600), severity: .veryHigh),
            LogicFixture.monitoredEvent(id: "restore", event: .internetRestored, at: LogicFixture.time(-500), severity: .medium, duration: "1m 40s"),
        ]

        let snapshot = StatusSnapshotBuilder.snapshot(
            gatewayStatus: LogicFixture.gatewayStatus(wan2: .disabled),
            events: events,
            now: LogicFixture.now,
            isGatewayReachable: true
        )

        XCTAssertEqual(snapshot.wan1?.state, .online)
        XCTAssertNil(snapshot.wan1?.outageStartedAt)
        XCTAssertEqual(snapshot.wan2?.state, .disabled)
        XCTAssertNil(snapshot.currentOutageWAN)
    }

    func testTheSnapshotWithoutAGatewayStatusIsStillValid() throws {
        let snapshot = StatusSnapshotBuilder.snapshot(
            gatewayStatus: nil,
            events: [],
            now: LogicFixture.now,
            isGatewayReachable: false
        )

        XCTAssertEqual(snapshot.gatewayName, "")
        XCTAssertTrue(snapshot.wanInterfaces.isEmpty)
        XCTAssertFalse(snapshot.isGatewayReachable)
        XCTAssertEqual(snapshot.updatedAt, LogicFixture.now)
    }

    func testTheSnapshotCarriesNoAPIKeyEvenAfterEncoding() throws {
        try store().write(sampleSnapshot())

        let data = try Data(contentsOf: store().fileURL)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertFalse(text.contains("apiKey"))
        XCTAssertFalse(text.contains("X-API-Key"))
    }

    func testRemoveDeletesTheFile() throws {
        try store().write(sampleSnapshot())

        try store().remove()

        XCTAssertNil(try store().read())
        XCTAssertFalse(FileManager.default.fileExists(atPath: store().fileURL.path))
        // Removing twice is harmless.
        try store().remove()
    }
}

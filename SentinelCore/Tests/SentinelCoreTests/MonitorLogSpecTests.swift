import Foundation
import SentinelCore
import Testing

/// The pure rules of the monitoring engine: query range, first run, wake
/// summary, retention, status line and the local log file.
///
/// The suite uses `swift-testing`, the framework `swift test` runs on Swift 6;
/// `XCTest` on this toolchain cannot be linked into a command-line build of the
/// fixtures, and the checks need no test bundle of their own.
@Suite("MonitorLogSpec")
struct MonitorLogSpecTests {
    // MARK: - Query range

    @Test("The first query reads the last 24 hours")
    func firstQueryReadsTheLast24Hours() {
        let range = MonitorLogSpec.queryRange(lastReadAt: nil, now: LogicFixture.now)

        #expect(range.to == LogicFixture.now)
        #expect(range.from == LogicFixture.now.addingTimeInterval(-24 * 60 * 60))
    }

    @Test("A later query overlaps the last read by two minutes")
    func aQueryOverlapsTheLastReadByTwoMinutes() {
        let lastReadAt = LogicFixture.time(-120)

        let range = MonitorLogSpec.queryRange(lastReadAt: lastReadAt, now: LogicFixture.now)

        #expect(range.to == LogicFixture.now)
        #expect(range.from == lastReadAt.addingTimeInterval(-120))
    }

    @Test("A query never ends before it starts")
    func aQueryNeverEndsBeforeItStarts() {
        // A clock that jumped backwards must not produce an empty range.
        let range = MonitorLogSpec.queryRange(lastReadAt: LogicFixture.time(600), now: LogicFixture.now)

        #expect(range.from == LogicFixture.now)
        #expect(range.to == LogicFixture.now)
    }

    // MARK: - First run

    @Test("An empty deduplication table is the first run")
    func anEmptyDeduplicationTableIsTheFirstRun() {
        #expect(MonitorLogSpec.isFirstRun(seenLogIDs: SeenLogIDs()))
    }

    @Test("A stored id is not the first run any more")
    func aStoredIDIsNotTheFirstRunAnyMore() {
        var seen = SeenLogIDs()
        seen.insert("log-1")

        #expect(!MonitorLogSpec.isFirstRun(seenLogIDs: seen))
    }

    @Test("The first run finds every monitored entry and never twice")
    func theFirstRunFindsEverythingAndNeverTwice() throws {
        let monitored = try [
            LogicFixture.entry(id: "down-1", event: .internetDown, at: LogicFixture.time(-3_600)),
            LogicFixture.entry(id: "down-2", event: .internetDown, at: LogicFixture.time(-3_000)),
        ]
        let unmonitored = try SystemLogEntry.json([
            "id": "client-1",
            "timestamp": Int64(LogicFixture.time(-2_000).timeIntervalSince1970 * 1_000),
            "category": "WLAN",
            "key": "EVT_WU_Connected",
        ])
        let batch = monitored + [unmonitored]

        var seen = SeenLogIDs()
        let first = MonitorLogSpec.newEvents(in: batch, seenLogIDs: &seen)

        // The unmonitored entry is neither returned nor stored.
        #expect(first.map(\.id) == ["down-1", "down-2"])
        #expect(seen.count == 2)
        #expect(seen.contains("down-1"))
        #expect(!seen.contains("client-1"))

        let second = MonitorLogSpec.newEvents(in: batch, seenLogIDs: &seen)
        #expect(second.isEmpty)
    }

    // MARK: - Wake round

    @Test("The wake round only counts what appeared after the sleep")
    func theWakeRoundOnlyCountsWhatAppearedAfterTheSleep() throws {
        let wokeAt = LogicFixture.time(-600)
        let entries = try [
            LogicFixture.entry(id: "before", event: .internetDown, at: LogicFixture.time(-3_600)),
            LogicFixture.entry(id: "after", event: .internetRestored, at: LogicFixture.time(-300)),
        ]

        let events = MonitorLogSpec.eventsSince(wokeAt, in: entries)

        #expect(events.map(\.id) == ["after"])
    }

    @Test("A quiet wake is not summarized")
    func aQuietWakeIsNotSummarized() {
        #expect(!MonitorLogSpec.shouldSummarizeWake(newEventCount: 0))
        #expect(!MonitorLogSpec.shouldSummarizeWake(newEventCount: 3))
    }

    @Test("A busy wake is summarized")
    func aBusyWakeIsSummarized() {
        #expect(MonitorLogSpec.shouldSummarizeWake(newEventCount: 4))
    }

    @Test("The wake summary names the most severe entry")
    func theWakeSummaryNamesTheMostSevereEntry() throws {
        let events = try [
            LogicFixture.monitoredEvent(id: "low", event: .packetLoss, at: LogicFixture.time(-300), severity: .low),
            LogicFixture.monitoredEvent(id: "high", event: .internetDown, at: LogicFixture.time(-200), severity: .high),
            LogicFixture.monitoredEvent(id: "medium", event: .internetRestored, at: LogicFixture.time(-100), severity: .medium),
            LogicFixture.monitoredEvent(id: "high-2", event: .threatDetected, at: LogicFixture.time(-50), wanID: nil, ispName: nil, severity: .high),
        ]

        let summary = try #require(MonitorLogSpec.wakeSummary(for: events) { _ in "09:30" })

        #expect(summary.count == 4)
        #expect(summary.title == "睡眠期间有 4 条新日志")
        // The newest entry at the highest severity wins.
        #expect(summary.body.hasPrefix("Threat Detected（09:30）"))
        #expect(summary.body.contains("另外 3 条在主窗口看。"))
    }

    @Test("A wake summary of one entry has no rest line")
    func aWakeSummaryOfOneEntryHasNoRestLine() throws {
        let events = try [
            LogicFixture.monitoredEvent(id: "only", event: .internetDown, at: LogicFixture.time(-100))
        ]

        let summary = try #require(MonitorLogSpec.wakeSummary(for: events) { _ in "09:30" })

        #expect(summary.count == 1)
        #expect(!summary.body.contains("另外"))
    }

    @Test("A wake summary of nothing is nil")
    func aWakeSummaryOfNothingIsNil() {
        #expect(MonitorLogSpec.wakeSummary(for: []) { _ in "09:30" } == nil)
    }

    // MARK: - 24-hour summary

    @Test("The summary counts the last 24 hours")
    func theSummaryCountsTheLast24Hours() throws {
        let events = try [
            LogicFixture.monitoredEvent(id: "down-old", event: .internetDown, at: LogicFixture.time(-25 * 3_600), severity: .veryHigh),
            LogicFixture.monitoredEvent(id: "down", event: .internetDown, at: LogicFixture.time(-3_600), severity: .medium),
            LogicFixture.monitoredEvent(id: "threat", event: .threatDetected, at: LogicFixture.time(-1_800), wanID: nil, ispName: nil, severity: .high),
            LogicFixture.monitoredEvent(id: "restore", event: .internetRestored, at: LogicFixture.time(-600), severity: .low),
        ]

        let summary = MonitorLogSpec.summary(of: events, now: LogicFixture.now)

        #expect(summary.outageCount == 1)
        #expect(summary.threatCount == 1)
        #expect(summary.highestSeverity == .high)
    }

    @Test("The summary of nothing is empty")
    func theSummaryOfNothingIsEmpty() {
        #expect(MonitorLogSpec.summary(of: [], now: LogicFixture.now) == .none)
    }

    // MARK: - Retention

    @Test("Retention drops the events that are too old")
    func retentionDropsTheEventsThatAreTooOld() throws {
        let events = try [
            storedEvent(id: "old", at: LogicFixture.time(-91 * 24 * 3_600)),
            storedEvent(id: "kept", at: LogicFixture.time(-24 * 3_600)),
        ]

        let kept = MonitorLogSpec.retained(events, now: LogicFixture.now, retentionDays: 90)

        #expect(kept.map(\.id) == ["kept"])
    }

    @Test("Retention keeps everything inside the window, oldest first")
    func retentionKeepsEverythingInsideTheWindow() throws {
        let events = try [
            storedEvent(id: "newer", at: LogicFixture.time(-60)),
            storedEvent(id: "older", at: LogicFixture.time(-89 * 24 * 3_600)),
        ]

        let kept = MonitorLogSpec.retained(events, now: LogicFixture.now, retentionDays: 90)

        #expect(kept.map(\.id) == ["older", "newer"])
    }

    @Test("Zero days of retention keeps nothing")
    func zeroDaysOfRetentionKeepsNothing() throws {
        let events = try [storedEvent(id: "any", at: LogicFixture.time(-1))]

        #expect(MonitorLogSpec.retained(events, now: LogicFixture.now, retentionDays: 0).isEmpty)
    }

    // MARK: - Status line

    @Test("The status line counts the seconds since the last query")
    func theStatusLineCountsTheSecondsSinceTheLastQuery() {
        let text = MonitorLogSpec.statusText(
            state: .connected,
            lastQueryAt: LogicFixture.time(-42),
            now: LogicFixture.now,
            errorDescription: nil
        )

        #expect(text == .connected(secondsAgo: 42))
        #expect(text.text == "已连上，42 秒前查过")
    }

    @Test("The status line before the first query")
    func theStatusLineBeforeTheFirstQuery() {
        let text = MonitorLogSpec.statusText(
            state: .connected,
            lastQueryAt: nil,
            now: LogicFixture.now,
            errorDescription: nil
        )

        #expect(text == .notQueried)
        #expect(text.text == "已连上，还没查过")
    }

    @Test("The status line shows why the gateway is unreachable")
    func theStatusLineShowsWhyTheGatewayIsUnreachable() {
        let text = MonitorLogSpec.statusText(
            state: .reconnecting,
            lastQueryAt: LogicFixture.time(-90),
            now: LogicFixture.now,
            errorDescription: "无法连接到 UniFi 网关，请检查网关地址和网络。"
        )

        #expect(text == .unreachable(reason: "无法连接到 UniFi 网关，请检查网关地址和网络。"))
        #expect(text.text == "无法连接到 UniFi 网关，请检查网关地址和网络。")
    }

    @Test("The status line of a changed certificate asks for a new test")
    func theStatusLineOfAChangedCertificateAsksForANewTest() {
        let text = MonitorLogSpec.statusText(
            state: .certificateChanged,
            lastQueryAt: LogicFixture.time(-90),
            now: LogicFixture.now,
            errorDescription: nil
        )

        #expect(text == .certificateChanged)
        #expect(text.text.contains("证书"))
    }

    @Test("The status line of a rejected API Key")
    func theStatusLineOfARejectedAPIKey() {
        let text = MonitorLogSpec.statusText(
            state: .apiKeyRejected,
            lastQueryAt: LogicFixture.time(-90),
            now: LogicFixture.now,
            errorDescription: nil
        )

        #expect(text == .apiKeyRejected)
        #expect(text.text.contains("API Key"))
    }

    // MARK: - State change notifications

    @Test("A warned state recovers with one notification")
    func aWarnedStateRecoversWithOneNotification() {
        let kind = MonitorLogSpec.stateChangeNotification(
            previous: .reconnecting,
            current: .connected,
            address: "https://192.168.8.254",
            errorDescription: nil
        )

        #expect(kind == .gatewayRestored)
        #expect(kind?.title == "UniFi 网关已恢复连接")
    }

    @Test("The first connected round of a fresh app is silent")
    func theFirstConnectedRoundOfAFreshAppIsSilent() {
        // 已连接 is the state the app starts in: no notification for it.
        #expect(MonitorLogSpec.stateChangeNotification(
            previous: .connected,
            current: .connected,
            address: "https://192.168.8.254",
            errorDescription: nil
        ) == nil)
    }

    @Test("An unreachable gateway names the address and the reason")
    func anUnreachableGatewayNamesTheAddressAndTheReason() throws {
        let kind = try #require(MonitorLogSpec.stateChangeNotification(
            previous: .connected,
            current: .reconnecting,
            address: "https://192.168.8.254",
            errorDescription: "无法连接到 UniFi 网关，请检查网关地址和网络。"
        ))

        #expect(kind.title == "UniFi 网关连不上")
        #expect(kind.body.contains("无法连接到 https://192.168.8.254"))
        #expect(kind.body.contains("请在「连接」里检查网关地址。"))
    }

    @Test("An invalid API Key asks for the settings")
    func anInvalidAPIKeyAsksForTheSettings() throws {
        let kind = try #require(MonitorLogSpec.stateChangeNotification(
            previous: .connected,
            current: .apiKeyRejected,
            address: "https://192.168.8.254",
            errorDescription: nil
        ))

        #expect(kind.title == "API Key 无效")
        #expect(kind.body.contains("「连接」"))
    }

    @Test("A changed certificate asks for a new test")
    func aChangedCertificateAsksForANewTest() throws {
        let kind = try #require(MonitorLogSpec.stateChangeNotification(
            previous: .connected,
            current: .certificateChanged,
            address: "https://192.168.8.254",
            errorDescription: nil
        ))

        #expect(kind.title == "UniFi 网关的证书变了")
        #expect(kind.body.contains("重新测试连接"))
    }

    // MARK: - Notification text

    @Test("A monitor event notification keeps the planner text")
    func aMonitorEventNotificationKeepsThePlannerText() {
        let record = NotificationRecord(
            event: .internetDown,
            severity: .veryHigh,
            wanID: "WAN1",
            title: "互联网中断 🟥🟥🟥🟥",
            body: "WAN1 (China Telecom) 已断开。",
            logIDs: ["down-1"],
            timestamp: LogicFixture.now,
            mergedCount: 1
        )

        let kind = NotificationKind.monitorEvent(record)

        #expect(kind.title == record.title)
        #expect(kind.body == record.body)
        #expect(kind.isMonitorEvent)
    }

    // MARK: - Local log file

    @Test("The local log round-trips through the directory")
    func theLocalLogRoundTripsThroughTheDirectory() throws {
        let directory = try LogicFixture.makeTemporaryDirectory()
        defer { LogicFixture.removeTemporaryDirectory(directory) }
        let store = MonitorLogStore(directory: directory)

        let stored = try storedEvent(id: "down-1", at: LogicFixture.time(-60))
        try store.saveEvents([stored])
        var seen = SeenLogIDs()
        seen.insert("down-1")
        try store.saveSeenLogIDs(seen)
        try store.saveReadState(MonitorReadState(lastReadAt: LogicFixture.now))

        #expect(store.loadEvents() == [stored])
        #expect(store.loadSeenLogIDs() == seen)
        #expect(store.loadReadState().lastReadAt == LogicFixture.now)
        #expect(store.loadReadState().connectionState == .connected)
    }

    @Test("The local log is oldest first after loading")
    func theLocalLogIsOldestFirstAfterLoading() throws {
        let directory = try LogicFixture.makeTemporaryDirectory()
        defer { LogicFixture.removeTemporaryDirectory(directory) }
        let store = MonitorLogStore(directory: directory)

        try store.saveEvents([
            try storedEvent(id: "newer", at: LogicFixture.time(-60)),
            try storedEvent(id: "older", at: LogicFixture.time(-600)),
        ])

        #expect(store.loadEvents().map(\.id) == ["older", "newer"])
    }

    @Test("A stored event keeps the gateway text of the entry")
    func aStoredEventKeepsTheGatewayTextOfTheEntry() throws {
        let directory = try LogicFixture.makeTemporaryDirectory()
        defer { LogicFixture.removeTemporaryDirectory(directory) }
        let store = MonitorLogStore(directory: directory)

        let monitored = try LogicFixture.monitoredEvent(
            id: "restore-1",
            event: .internetRestored,
            at: LogicFixture.time(-120),
            severity: .medium,
            duration: "1m 25s"
        )
        try store.saveEvents([try #require(StoredMonitorEvent(entry: monitored.entry))])

        let loaded = try #require(store.loadEvents().first?.monitoredLogEvent)

        #expect(loaded.id == "restore-1")
        #expect(loaded.event == .internetRestored)
        #expect(loaded.timestamp == monitored.timestamp)
        #expect(loaded.title == monitored.title)
        #expect(loaded.message == monitored.message)
        #expect(loaded.wanID == "WAN1")
        #expect(loaded.ispName == "China Telecom")
        #expect(loaded.durationText == "1m 25s")
        #expect(loaded.severity == .medium)
    }

    @Test("A threat keeps its endpoints")
    func aThreatKeepsItsEndpoints() throws {
        let directory = try LogicFixture.makeTemporaryDirectory()
        defer { LogicFixture.removeTemporaryDirectory(directory) }
        let store = MonitorLogStore(directory: directory)

        let monitored = try LogicFixture.monitoredEvent(
            id: "threat-1",
            event: .threatDetected,
            at: LogicFixture.time(-120),
            wanID: nil,
            ispName: nil,
            severity: .veryHigh,
            source: ThreatEndpoint(value: "198.51.100.7", isClient: false),
            destination: ThreatEndpoint(value: "nas", isClient: true)
        )
        try store.saveEvents([try #require(StoredMonitorEvent(entry: monitored.entry))])

        let loaded = try #require(store.loadEvents().first?.monitoredLogEvent)

        #expect(loaded.source?.value == "198.51.100.7")
        #expect(loaded.source?.isClient == false)
        #expect(loaded.destination?.value == "nas")
        #expect(loaded.destination?.isClient == true)
    }

    @Test("A broken log file counts as empty")
    func aBrokenLogFileCountsAsEmpty() throws {
        let directory = try LogicFixture.makeTemporaryDirectory()
        defer { LogicFixture.removeTemporaryDirectory(directory) }
        let store = MonitorLogStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json at all".utf8).write(to: store.eventsURL)
        try Data("{}".utf8).write(to: store.seenLogIDsURL)
        try Data("[]".utf8).write(to: store.readStateURL)

        #expect(store.loadEvents().isEmpty)
        #expect(store.loadSeenLogIDs().isEmpty)
        #expect(store.loadReadState().lastReadAt == nil)
        #expect(store.loadReadState().connectionState == .connected)
    }

    @Test("A missing directory loads as empty")
    func aMissingDirectoryLoadsAsEmpty() {
        let store = MonitorLogStore(
            directory: URL(fileURLWithPath: "/tmp/network-sentinel-does-not-exist-\(UUID().uuidString)")
        )

        #expect(store.loadEvents().isEmpty)
        #expect(store.loadSeenLogIDs().isEmpty)
        #expect(store.loadReadState().lastReadAt == nil)
    }

    @Test("The local log stores no API Key")
    func theLocalLogStoresNoAPIKey() throws {
        let directory = try LogicFixture.makeTemporaryDirectory()
        defer { LogicFixture.removeTemporaryDirectory(directory) }
        let store = MonitorLogStore(directory: directory)

        // No stored type has a field for the API Key; the marker must not show
        // up in any of the three files either.
        try store.saveEvents([try storedEvent(id: "down-1", at: LogicFixture.time(-60))])
        try store.saveReadState(MonitorReadState(lastReadAt: LogicFixture.now))

        var checked = 0
        for url in [store.eventsURL, store.seenLogIDsURL, store.readStateURL]
        where FileManager.default.fileExists(atPath: url.path) {
            checked += 1
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(!text.lowercased().contains("api key"), "\(url.lastPathComponent) mentioned an API Key")
        }
        #expect(checked == 2)
    }

    // MARK: - Read state

    @Test("Three network failures make the gateway unreachable")
    func threeNetworkFailuresMakeTheGatewayUnreachable() {
        var state = MonitorReadState()

        for _ in 1...GatewayReachability.defaultFailureThreshold {
            state.recordQuery(succeeded: false, error: .network(URLError(.cannotConnectToHost)))
        }

        #expect(state.connectionState == .reconnecting)
    }

    @Test("A success clears the failures")
    func aSuccessClearsTheFailures() {
        var state = MonitorReadState()
        for _ in 1...GatewayReachability.defaultFailureThreshold {
            state.recordQuery(succeeded: false, error: .network(URLError(.cannotConnectToHost)))
        }

        state.recordQuery(succeeded: true, error: nil)

        #expect(state.connectionState == .connected)
        #expect(state.reachability.consecutiveFailureCount == 0)
    }

    @Test("A rejected API Key is its own state")
    func aRejectedAPIKeyIsItsOwnState() {
        var state = MonitorReadState()

        state.recordQuery(succeeded: false, error: .unauthorized(statusCode: 401))

        #expect(state.connectionState == .apiKeyRejected)
    }

    @Test("A changed certificate is its own state")
    func aChangedCertificateIsItsOwnState() {
        var state = MonitorReadState()

        state.recordQuery(succeeded: false, error: .certificateChanged)

        #expect(state.connectionState == .certificateChanged)
        #expect(state.reachability.isCertificateChanged)
    }

    @Test("The read time only moves forward")
    func theReadTimeOnlyMovesForward() {
        var state = MonitorReadState()
        state.recordRead(at: LogicFixture.now)

        state.recordRead(at: LogicFixture.time(-600))

        #expect(state.lastReadAt == LogicFixture.now)
    }

    // MARK: - Helpers

    /// One stored event of the local log, built the way the engine builds it.
    private func storedEvent(id: String, at date: Date) throws -> StoredMonitorEvent {
        let monitored = try LogicFixture.monitoredEvent(id: id, event: .internetDown, at: date)
        return try #require(StoredMonitorEvent(entry: monitored.entry))
    }
}

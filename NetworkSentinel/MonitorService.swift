import AppKit
import Combine
import SentinelCore
import SwiftUI
import UserNotifications

/// The monitoring engine of the app.
///
/// One round reads the gateway status (`stat/device`) and the system log
/// (`system-log/all`) through the pinned-certificate session, keeps the new
/// monitored events in the local log, and sends the notifications the rules ask
/// for. The engine owns the clock (a repeating timer at the 查询间隔) and the
/// 睡眠醒来补查; every rule it applies lives in `MonitorLogSpec`, so the rules
/// are tested without a gateway.
///
/// The API Key is read from the keychain for one request and is never kept in a
/// property, written to a file or put into a notification.
@MainActor
final class MonitorService: ObservableObject {
    /// The settings and the connection the engine works with. Two of them are
    /// equal exactly when a change keeps the running engine valid.
    ///
    /// The pinned certificate is kept as its fingerprint text: a stored
    /// `PinnedCertificate` keeps the comparison on the main actor, which the
    /// publisher that watches the settings cannot use.
    @MainActor
    struct Configuration: Equatable {
        let address: String?
        let siteReference: String?
        let pinnedCertificateFingerprint: String?
        let hasAPIKey: Bool
        let queryIntervalSeconds: Int
        let logRetentionDays: Int

        init(
            address: String?,
            siteReference: String?,
            pinnedCertificateFingerprint: String?,
            hasAPIKey: Bool,
            queryIntervalSeconds: Int,
            logRetentionDays: Int
        ) {
            self.address = address
            self.siteReference = siteReference
            self.pinnedCertificateFingerprint = pinnedCertificateFingerprint
            self.hasAPIKey = hasAPIKey
            self.queryIntervalSeconds = queryIntervalSeconds
            self.logRetentionDays = logRetentionDays
        }

        init(_ configuration: AppConfiguration) {
            self.init(
                address: configuration.gatewayAddress?.urlString,
                siteReference: configuration.siteReference,
                pinnedCertificateFingerprint: configuration.pinnedCertificate?.sha256,
                hasAPIKey: configuration.hasAPIKey,
                queryIntervalSeconds: configuration.monitorSettings.queryIntervalSeconds,
                logRetentionDays: configuration.monitorSettings.logRetentionDays
            )
        }

        /// `true` when the app has everything it needs to query the gateway.
        var isConfigured: Bool {
            address != nil && siteReference != nil && pinnedCertificateFingerprint != nil && hasAPIKey
        }
    }

    // MARK: - Published state, for the windows and the menu bar

    /// Gateway name, model, firmware and WAN lines of the last successful query.
    @Published private(set) var gatewayStatus: GatewayStatus?
    /// Monitored events of the local log, newest first.
    @Published private(set) var events: [MonitoredLogEvent] = []
    /// Counters of the last 24 hours of the local log.
    @Published private(set) var summary: MonitorLogSpec.LogSummaryStats = .none
    /// State of the gateway, including an unreachable gateway and a changed certificate.
    @Published private(set) var connectionState: GatewayConnectionState = .connected
    /// When the last round finished, `nil` before the first one.
    @Published private(set) var lastQueryAt: Date?
    /// Chinese text of the last failure, `nil` while everything works.
    @Published private(set) var lastErrorDescription: String?
    /// `true` while a round is running.
    @Published private(set) var isQuerying = false
    /// What the last Bark push did, `nil` while Bark never ran.
    ///
    /// The 通知 page shows the time of the last success, or the Chinese reason
    /// of the last failure. A failed push never fails a query round.
    @Published private(set) var lastBarkResult: BarkResult?

    /// The API Key of the running configuration; see `cachedAPIKey(for:)`.
    private var apiKeyCache: (address: String, key: String)?
    /// `true` once the engine is running.
    @Published private(set) var isRunning = false

    // MARK: - Dependencies

    /// Set by `AppState`: a notification tap opens the 主窗口.
    weak var windows: WindowCoordinator?

    private let configuration: AppConfiguration
    private let logStore: MonitorLogStore
    private let sender: UserNotificationSending
    /// Session of the Bark pushes. `URLSession.shared` in the app, a stub in tests.
    private let barkSession: URLSession

    // MARK: - Engine state

    private var seenLogIDs = SeenLogIDs()
    private var readState = MonitorReadState()
    private var lastStoredEvents: [StoredMonitorEvent] = []
    /// Records of the notifications already sent, for the merge window.
    private var recentNotifiedRecords: [NotificationRecord] = []
    private var timer: DispatchSourceTimer?
    private var settingsSubscription: AnyCancellable?
    private var wakeObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    /// The settings the engine is running with; `nil` before the first round.
    private var runningConfiguration: Configuration?
    /// When the Mac went to sleep, so a wake round only looks at what appeared since.
    private var sleptAt: Date?
    /// The delegate of the notification centre; `UNUserNotificationCenter` keeps it.
    private var notificationDelegate: SystemNotificationDelegate?

    init(
        configuration: AppConfiguration,
        sender: UserNotificationSending? = nil,
        logStore: MonitorLogStore = MonitorService.makeLogStore(),
        barkSession: URLSession = .shared
    ) {
        self.configuration = configuration
        self.logStore = logStore
        self.sender = sender ?? SystemNotificationSender()
        self.barkSession = barkSession

        seenLogIDs = logStore.loadSeenLogIDs()
        readState = logStore.loadReadState()
        lastStoredEvents = logStore.loadEvents()
        connectionState = readState.connectionState

        if self.sender is SystemNotificationSender {
            let forwarder = NotificationTapForwarder()
            let delegate = SystemNotificationDelegate(tapForwarder: forwarder)
            forwarder.setHandler { [weak self] in
                self?.windows?.showMainWindow()
            }
            notificationDelegate = delegate
            UNUserNotificationCenter.current().delegate = delegate
        }

        // A saved connection, a changed query interval or a new retention all
        // restart the engine with the new settings.
        settingsSubscription = configuration.objectWillChange
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let updated = Configuration(self.configuration)
                if let running = self.runningConfiguration, running == updated { return }
                self.applyRestart(with: updated)
            }
    }

    deinit {
        timer?.cancel()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
    }

    /// Seconds between two rounds, at least one.
    private var queryIntervalSeconds: Int {
        max(1, configuration.monitorSettings.queryIntervalSeconds)
    }

    // MARK: - Lifecycle

    /// Starts the engine and queries at once. Calling it twice changes nothing.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        removeObservers()

        // The engine owns the wake round: a Mac that slept must not wait for
        // the next interval before it knows what happened.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.runRound(isWake: true) }
        }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.sleptAt = Date() }
        }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }

        scheduleTimer()
        Task { await runRound(isWake: false) }
    }

    /// Stops the engine: no timer, no wake round.
    func stop() {
        isRunning = false
        apiKeyCache = nil
        timer?.cancel()
        timer = nil
        runningConfiguration = nil
        removeObservers()
    }

    /// Drops the wake, sleep and termination observers.
    private func removeObservers() {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        if let sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
            self.sleepObserver = nil
        }
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
            self.terminationObserver = nil
        }
    }

    /// Restarts the engine after a settings change.
    private func applyRestart(with configuration: Configuration) {
        apiKeyCache = nil
        runningConfiguration = configuration
        guard isRunning, configuration.isConfigured else {
            timer?.cancel()
            timer = nil
            return
        }
        scheduleTimer()
    }

    /// Runs the engine every 查询间隔. A round that is still running is skipped.
    private func scheduleTimer() {
        timer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        let interval = DispatchTimeInterval.seconds(queryIntervalSeconds)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            Task { @MainActor in await self?.runRound(isWake: false) }
        }
        self.timer = timer
        timer.resume()
    }

    // MARK: - One round

    /// Runs one round: gateway state, log, local log, notifications, 状态文件.
    private func runRound(isWake: Bool) async {
        // Two rounds never overlap: the timer of a slower query is dropped.
        guard !isQuerying, let query = makeQuery() else {
            runningConfiguration = Configuration(configuration)
            return
        }

        isQuerying = true
        defer { isQuerying = false }

        let stateBefore = readState.connectionState
        let isFirstRun = MonitorLogSpec.isFirstRun(seenLogIDs: seenLogIDs)
        let now = Date()
        let range = MonitorLogSpec.queryRange(lastReadAt: readState.lastReadAt, now: now)

        let client = UniFiGatewayClient(
            baseURL: query.baseURL,
            apiKey: query.apiKey,
            session: query.session
        )

        var gatewayStatus: GatewayStatus?
        var statusError: Error?
        do {
            gatewayStatus = try await client.fetchGatewayStatus(site: query.siteReference)
        } catch {
            statusError = error
        }

        var entries: [SystemLogEntry] = []
        var logError: Error?
        do {
            entries = try await client.fetchSystemLog(
                site: query.siteReference,
                from: range.from,
                to: range.to
            )
        } catch {
            logError = error
        }

        let didReachGateway = gatewayStatus != nil
        readState.recordQuery(
            succeeded: didReachGateway,
            error: didReachGateway ? nil : Self.apiError(from: logError ?? statusError)
        )

        // The newest log time of the whole response, monitored or not: the next
        // range starts there, so the overlap covers a late entry.
        if let newest = entries.map(\.timestamp).max() {
            readState.recordRead(at: newest)
        }

        let reportedError = statusError ?? logError
        lastErrorDescription = reportedError.map(Self.chineseDescription)
        if let gatewayStatus {
            self.gatewayStatus = gatewayStatus
        }

        // The sleep period decides what a wake round reports; the local log
        // always receives everything, so the 主窗口 shows the whole history.
        let newEntries = isWake
            ? MonitorLogSpec.eventsSince(sleptAt ?? range.from, in: entries)
            : MonitorLogSpec.newEvents(in: entries, seenLogIDs: &seenLogIDs)
        sleptAt = nil

        appendToLocalLog(entries, retentionDays: query.logRetentionDays, now: now)

        if isFirstRun {
            // A fresh install read 24 hours of history: recording it is enough,
            // a burst of notifications about old events would be noise.
            if !newEntries.isEmpty {
                await sender.requestAuthorizationIfNeeded()
            }
        } else {
            await deliverNotifications(for: newEntries, isWake: isWake)
        }

        refreshPublishedState(now: now)
        persist()
        writeStatusFile(now: now)
        await reportStateChange(from: stateBefore, address: query.addressText, error: reportedError)

        lastQueryAt = Date()
        runningConfiguration = Configuration(configuration)
    }

    /// Everything one query needs, or `nil` when the app is not configured.
    private func makeQuery() -> (
        baseURL: URL,
        apiKey: String,
        session: URLSession,
        siteReference: String,
        addressText: String,
        logRetentionDays: Int
    )? {
        guard let address = configuration.gatewayAddress,
              let siteReference = configuration.siteReference,
              let pinned = configuration.pinnedCertificate,
              let apiKey = cachedAPIKey(for: address.urlString) else {
            return nil
        }

        return (
            baseURL: address.url,
            apiKey: apiKey,
            session: GatewayTrust.session(gatewayHost: address.host, mode: .pinned(pinned)),
            siteReference: siteReference,
            addressText: address.urlString,
            logRetentionDays: configuration.monitorSettings.logRetentionDays
        )
    }

    /// The API Key, read from the keychain once per gateway address.
    ///
    /// Reading the keychain every round would ask the user again whenever the
    /// keychain wants a confirmation; the key only changes with the address or
    /// through the 连接设置窗口, which restarts the engine.
    private func cachedAPIKey(for address: String) -> String? {
        if let cached = apiKeyCache, cached.address == address {
            return cached.key
        }
        guard let key: String = (try? configuration.apiKey()) ?? nil, !key.isEmpty else {
            return nil
        }
        apiKeyCache = (address: address, key: key)
        return key
    }

    /// Adds the monitored events of the round to the local log and applies the
    /// retention. Only the seven monitored events are ever stored.
    private func appendToLocalLog(_ entries: [SystemLogEntry], retentionDays: Int, now: Date) {
        var byID = Dictionary(
            lastStoredEvents.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for entry in entries {
            guard let stored = StoredMonitorEvent(entry: entry) else { continue }
            byID[stored.id] = stored
        }

        lastStoredEvents = MonitorLogSpec.retained(
            Array(byID.values),
            now: now,
            retentionDays: retentionDays
        )
    }

    // MARK: - Notifications

    /// Sends what the rules ask for.
    private func deliverNotifications(for newEvents: [MonitoredLogEvent], isWake: Bool) async {
        // A wake round with many new entries sends one summary: the Mac was
        // asleep, so a burst of single notifications would be noise.
        if isWake, MonitorLogSpec.shouldSummarizeWake(newEventCount: newEvents.count) {
            if let summary = MonitorLogSpec.wakeSummary(for: newEvents, timeText: Self.timeText) {
                await send(.wakeSummary(summary))
            }
            return
        }

        let plan = NotificationPlanner().plan(
            entries: newEvents.map(\.entry),
            settings: configuration.monitorSettings,
            now: Date(),
            recentRecords: recentNotifiedRecords
        )
        recentNotifiedRecords = plan.records

        for record in plan.notifications {
            await send(.monitorEvent(record))
        }
    }

    /// The one-time notification of a gateway state change.
    ///
    /// Only a change sends anything: the engine compares the state before the
    /// round with the state after it, so the same state never repeats.
    private func reportStateChange(
        from previous: GatewayConnectionState,
        address: String?,
        error: Error?
    ) async {
        let current = readState.connectionState
        guard current != previous else { return }

        let kind = MonitorLogSpec.stateChangeNotification(
            previous: previous,
            current: current,
            address: address,
            errorDescription: error.map(Self.chineseDescription)
        )
        guard let kind else { return }
        await send(kind)
    }

    private func send(_ kind: NotificationKind) async {
        await sender.send(title: kind.title, body: kind.body)
        // Bark goes out whatever the system permission says, and a failed push
        // never touches the notification above.
        await sendBark(title: kind.title, body: kind.body, level: kind.barkLevel)
    }

    // MARK: - Bark

    /// Pushes the same text to the phone when the user turned Bark on.
    ///
    /// The Key is read from the cached configuration, so no push asks the
    /// keychain again. Every failure lands in `lastBarkResult` and stops there:
    /// a phone that cannot be reached must not fail the query round.
    private func sendBark(title: String, body: String, level: BarkLevel) async {
        guard configuration.barkEnabled else { return }

        do {
            let client = BarkClient(configuration: try configuration.barkConfiguration(), session: barkSession)
            try await client.send(title: title, body: body, level: level, sound: configuration.barkSound)
            lastBarkResult = .success(at: Date())
        } catch {
            lastBarkResult = .failure(Self.chineseDescription(error), at: Date())
        }
    }

    /// Sends the test push of the 通知 page with the current settings.
    ///
    /// The test ignores the Bark switch — the user pressed the button on purpose
    /// — but it needs a saved Key and a usable server address.
    ///
    /// - Returns: the time of a successful push, or the Chinese reason of a
    ///   failure. The result is also published as `lastBarkResult`.
    @discardableResult
    func sendBarkTest() async -> BarkResult {
        do {
            let client = BarkClient(configuration: try configuration.barkConfiguration(), session: barkSession)
            try await client.send(
                title: "Network Sentinel 测试推送",
                body: "Bark 推送已连通，断网和威胁通知会同步发到这台设备。",
                level: .active,
                sound: configuration.barkSound
            )
            let result = BarkResult.success(at: Date())
            lastBarkResult = result
            return result
        } catch {
            let result = BarkResult.failure(Self.chineseDescription(error), at: Date())
            lastBarkResult = result
            return result
        }
    }

    // MARK: - Published state

    #if DEBUG
    /// Fills the published state from the local log and a given gateway state,
    /// without querying. Only the debug snapshot renderer uses it.
    func loadSnapshotState(gatewayStatus: GatewayStatus?, now: Date) {
        self.gatewayStatus = gatewayStatus
        refreshPublishedState(now: now)
        lastQueryAt = now
    }
    #endif

    private func refreshPublishedState(now: Date) {
        let monitored = lastStoredEvents.compactMap(\.monitoredLogEvent)
        events = monitored.sorted { $0.timestamp > $1.timestamp }
        summary = MonitorLogSpec.summary(of: monitored, now: now)
        connectionState = readState.connectionState
    }

    /// Writes the local log, the deduplication table and the read state.
    private func persist() {
        try? logStore.saveEvents(lastStoredEvents)
        try? logStore.saveSeenLogIDs(seenLogIDs)
        try? logStore.saveReadState(readState)
    }

    // MARK: - 状态文件

    /// Writes the 状态文件 for the future widget.
    private func writeStatusFile(now: Date) {
        guard let directory = AppGroup.containerURL ?? Self.applicationSupportDirectory() else { return }

        let snapshot = StatusSnapshotBuilder.snapshot(
            gatewayStatus: gatewayStatus,
            events: lastStoredEvents.compactMap(\.monitoredLogEvent),
            now: now,
            isGatewayReachable: readState.connectionState.isGatewayReachable
        )
        try? StatusFileStore(directory: directory).write(snapshot)
    }

    // MARK: - Status line of 设置

    /// The status the 连接 card shows right now.
    func monitorStatusText(at now: Date = Date()) -> String {
        MonitorLogSpec.statusText(
            state: connectionState,
            lastQueryAt: lastQueryAt,
            now: now,
            errorDescription: lastErrorDescription
        ).text
    }

    /// The color of the status dot of the 连接 card.
    ///
    /// - Parameter now: the current time; the status text of the card needs it,
    ///   the color does not, so the dot stays green until the state changes.
    func monitorStatusTone(at now: Date = Date()) -> StatusTone {
        _ = now
        switch connectionState {
        case .connected:
            return lastQueryAt == nil ? .neutral : .ok
        case .reconnecting, .apiKeyRejected, .certificateChanged:
            return .failure
        }
    }

    // MARK: - Pieces

    /// The local log directory: the Application Support directory of the app,
    /// which is the container path inside the sandbox.
    ///
    /// Not isolated: the initializer uses it for its default argument.
    nonisolated private static func applicationSupportDirectory() -> URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("NetworkSentinel", isDirectory: true)
    }

    /// The store used by the app: the App Group when it exists, otherwise the
    /// Application Support directory.
    nonisolated static func makeLogStore() -> MonitorLogStore {
        let directory = AppGroup.containerURL
            ?? applicationSupportDirectory()
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return MonitorLogStore(directory: directory)
    }

    /// The `SentinelAPIError` behind a thrown error, for the reachability rules.
    private static func apiError(from error: Error?) -> SentinelAPIError? {
        guard let error else { return nil }
        if let apiError = error as? SentinelAPIError { return apiError }
        return .network(URLError(.unknown))
    }

    /// Chinese text of a failure, without request data.
    private static func chineseDescription(_ error: Error) -> String {
        if let apiError = error as? SentinelAPIError {
            return apiError.errorDescription ?? "查询失败"
        }
        return error.localizedDescription
    }

    /// `15:04` for the wake summary body.
    private static func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - UserNotifications

/// What the engine needs from the notification centre, so a test can stand in.
@MainActor
protocol UserNotificationSending {
    /// Asks for the permission once; a denied permission is never asked again.
    func requestAuthorizationIfNeeded() async
    /// Shows one notification with a banner and a sound.
    func send(title: String, body: String) async
}

/// The live sender: `UNUserNotificationCenter` of the app.
@MainActor
final class SystemNotificationSender: UserNotificationSending {
    private let center = UNUserNotificationCenter.current()

    func requestAuthorizationIfNeeded() async {
        let settings = await center.notificationSettings()
        // A denied permission is never asked again: the user already said no.
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func send(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }
}

/// Carries the tap of a notification from the delegate to the app.
///
/// The delegate is not on the main actor, so it cannot touch the app directly.
final class NotificationTapForwarder: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@MainActor () -> Void)?

    func setHandler(_ handler: @escaping @MainActor () -> Void) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    func forward() {
        lock.lock()
        let handler = self.handler
        lock.unlock()
        guard let handler else { return }
        Task { @MainActor in handler() }
    }
}

/// The `UNUserNotificationCenterDelegate` of the app.
///
/// The app is often in the foreground when a notification arrives, so
/// `willPresent` asks for a banner and a sound instead of silence. A tap opens
/// the 主窗口.
final class SystemNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private let tapForwarder: NotificationTapForwarder

    init(tapForwarder: NotificationTapForwarder) {
        self.tapForwarder = tapForwarder
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        tapForwarder.forward()
        completionHandler()
    }
}

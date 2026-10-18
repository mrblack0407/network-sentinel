import AppKit
import Combine
import SentinelCore

/// Asks GitHub for the latest release and keeps the result for the sidebar and
/// the 通知 page.
///
/// The checker never installs anything: it reads `releases/latest`, compares the
/// tag of the release with `AppInfo.marketingVersion` and keeps the release page
/// address, which the sidebar opens in the browser. Every failure is silent — no
/// alert, no notification, no log line — and the next scheduled check tries
/// again.
///
/// The switch lives in `AppConfiguration`: while it is off the checker holds no
/// timer and no wake observer, so the app sends no request at all.
@MainActor
final class UpdateChecker: ObservableObject {
    /// A release newer than the running app, for the sidebar and the card.
    ///
    /// `nil` while the app is up to date, while the switch is off and before a
    /// check had a readable answer.
    @Published private(set) var latestRelease: AppUpdate.Release?
    /// `true` once the last check read a release, so the card can say 已是最新版本.
    ///
    /// A check that cannot reach GitHub or read its answer turns it off again:
    /// the card then says 尚未检查 rather than repeating an old answer.
    @Published private(set) var hasChecked = false

    /// How often a running app asks GitHub again.
    private static let checkInterval: TimeInterval = 24 * 60 * 60
    /// Timeout of one request, so a stuck connection never holds the checker.
    private static let requestTimeout: TimeInterval = 15

    private let configuration: AppConfiguration
    private let session: URLSession
    /// The settings subscription: the switch starts and stops the checker.
    private var settingsSubscription: AnyCancellable?
    /// `true` while the checker holds a timer.
    private var isRunning = false
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    /// `true` while one check is in flight; two never overlap.
    private var isChecking = false

    init(configuration: AppConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session

        // Turning the switch on checks at once; turning it off drops the timer
        // and the result, so the sidebar stops offering an update.
        settingsSubscription = configuration.$checksForUpdates
            .dropFirst()
            .sink { [weak self] isOn in
                Task { @MainActor in
                    guard let self else { return }
                    if isOn {
                        self.start()
                    } else {
                        self.stop()
                    }
                }
            }
    }

    deinit {
        timer?.invalidate()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    // MARK: - Lifecycle

    /// Checks right away, then every 24 hours and after a wake that passed
    /// them. Calling it twice changes nothing.
    func start() {
        guard configuration.checksForUpdates else {
            stop()
            return
        }
        guard !isRunning else { return }
        isRunning = true

        // A Mac that slept through the 24 hours checks when it wakes instead of
        // waiting for the timer, which does not fire while the Mac sleeps.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.checkIfDue() }
        }

        let timer = Timer(timeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIfDue() }
        }
        // The checker lives as long as the app, so the common modes keep the
        // timer running while a menu or a window is being tracked.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        Task { await check() }
    }

    /// Stops all further checks and drops the result of the last one.
    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        // The switch is off: no stale 「有新版本」 may stay in the sidebar.
        latestRelease = nil
        hasChecked = false
    }

    // MARK: - Checking

    /// Checks when the last check is at least 24 hours ago.
    ///
    /// The timer and the wake observer both come here, so a Mac that slept
    /// through several days checks once, not once per missed day.
    private func checkIfDue() {
        guard configuration.checksForUpdates, isRunning else { return }
        if let lastCheck = configuration.lastUpdateCheckAt,
           Date().timeIntervalSince(lastCheck) < Self.checkInterval {
            return
        }
        Task { await check() }
    }

    /// One request to `releases/latest`, and the result for the windows.
    ///
    /// A network failure, an HTTP error and an answer this version cannot read
    /// all stay silent. A readable answer is a fact either way, so it replaces
    /// the previous result: a release that is not newer clears the offer.
    private func check() async {
        guard configuration.checksForUpdates, !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        guard let request = makeRequest() else { return }
        // Recorded before the request, so a GitHub that cannot be reached is
        // asked again after the interval, not on every wake.
        configuration.recordUpdateCheck(at: Date())

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                // 查不到: the card says 尚未检查 instead of claiming the last
                // answer is still the state of this check.
                hasChecked = false
                return
            }
            // The switch may have been turned off while the request was in
            // flight; the answer then belongs to nobody.
            guard configuration.checksForUpdates else { return }

            guard let release = AppUpdate.release(fromLatestRelease: data) else {
                // A readable answer this version cannot use means there is no
                // newer version to offer.
                hasChecked = false
                latestRelease = nil
                return
            }
            hasChecked = true
            latestRelease = AppUpdate.isNewer(release.version, than: AppInfo.marketingVersion)
                ? release
                : nil
        } catch {
            // Silent by design: no alert, no notification, no log line. The next
            // check tries again.
            hasChecked = false
        }
    }

    /// The request the GitHub API expects.
    ///
    /// The version goes into the `User-Agent` GitHub asks for, and the fixed
    /// timeout keeps a slow connection from holding the checker.
    private func makeRequest() -> URLRequest? {
        guard let endpoint = AppUpdate.latestReleaseEndpoint(for: AppInfo.repositoryURL) else {
            return nil
        }

        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("NetworkSentinel/\(AppInfo.marketingVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = Self.requestTimeout
        return request
    }
}

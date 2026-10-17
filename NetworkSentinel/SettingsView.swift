import SentinelCore
import SwiftUI

/// 设置: colored group titles, one card per setting, saved on every change.
struct SettingsPage: View {
    @ObservedObject var configuration: AppConfiguration
    /// The monitoring engine: the 连接 card shows its real state.
    @ObservedObject var monitor: MonitorService

    @StateObject private var launchAtLogin = LaunchAtLogin()
    @State private var connectionTest: ConnectionTestState = .idle
    @State private var isShowingConnectionSheet = false

    var body: some View {
        GeometryReader { proxy in
            let columns = SettingsGridLayout.columns(forWidth: proxy.size.width)

            ScrollView {
                VStack(alignment: .leading, spacing: SentinelMetrics.contentSpacing) {
                    Text(T(.pageSettings))
                        .font(.system(size: SentinelMetrics.pageTitleFontSize, weight: .bold))
                        .tracking(SentinelMetrics.pageTitleTracking)
                        .accessibilityAddTraits(.isHeader)

                    // Group order and title colors: 通用 pink, UniFi 网关 purple,
                    // 监控事件 teal — the colors follow the position, not the group.
                    GroupHeader(title: T(.settingsGroupGeneral), color: SentinelColor.groupPink)
                    LazyVGrid(columns: SettingsGridLayout.twoColumns, alignment: .leading, spacing: SentinelMetrics.cardSpacing) {
                        launchAtLoginCard
                        logRetentionCard
                    }

                    GroupHeader(title: T(.settingsGroupGateway), color: SentinelColor.groupPurple)
                    LazyVGrid(columns: SettingsGridLayout.twoColumns, alignment: .leading, spacing: SentinelMetrics.cardSpacing) {
                        connectionCard
                        queryIntervalCard
                    }

                    GroupHeader(title: T(.settingsGroupEvents), color: SentinelColor.groupTeal)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: SentinelMetrics.cardSpacing) {
                        ForEach(Self.displayedEvents, id: \.self) { event in
                            eventCard(event)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(isPresented: $isShowingConnectionSheet) {
            ConnectionSettingsSheet(configuration: configuration)
        }
        .onChange(of: isShowingConnectionSheet) { isShowing in
            // A saved connection replaces the status of the card.
            if !isShowing { connectionTest = .idle }
        }
    }

    // MARK: - UniFi 网关

    /// The card refreshes every second so 「N 秒前查过」 stays true without the
    /// engine publishing a value every tick.
    private var connectionCard: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            SettingsCard(
                title: T(.settingsConnection),
                description: connectionDescription,
                statusTone: connectionStatusTone(at: context.date),
                statusText: connectionStatusText(at: context.date),
                control: Button(T(.settingsConnectionTest)) {
                    reTest()
                }
                .disabled(!canReTest),
                accessory: Button {
                    isShowingConnectionSheet = true
                } label: {
                    Text("•••")
                        .font(.system(size: SentinelMetrics.hintFontSize))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.plain)
                .help(T(.settingsConnectionSettings))
                .accessibilityLabel(T(.settingsConnectionSettings))
            )
        }
    }

    private var connectionDescription: String {
        guard let address = configuration.gatewayAddress?.urlString else {
            return T(.settingsConnectionNoAddress)
        }
        return T(.settingsConnectionAddress, address)
    }

    /// The card shows what 测试连接 is doing while it runs, and the real state of
    /// the engine the rest of the time.
    private func connectionStatusTone(at now: Date) -> StatusTone {
        switch connectionTest {
        case .testing: return .neutral
        case .success: return .ok
        case .failure: return .failure
        case .idle:
            guard configuration.isConfigured else { return .warn }
            guard monitor.isRunning else { return .neutral }
            return monitor.monitorStatusTone(at: now)
        }
    }

    private func connectionStatusText(at now: Date) -> String {
        switch connectionTest {
        case .testing: return T(.settingsConnectionTesting)
        case .success(let gatewayName): return T(.settingsConnectionSuccess, gatewayName)
        case .failure(let reason, _): return reason.message
        case .idle:
            guard configuration.isConfigured else { return T(.settingsConnectionNotConnected) }
            guard monitor.isRunning else { return T(.settingsConnectionNotRunning) }
            return monitor.monitorStatusText(at: now)
        }
    }

    private var canReTest: Bool {
        configuration.gatewayAddress != nil && configuration.hasAPIKey && connectionTest != .testing
    }

    /// 「测试连接」 on the card: checks the stored gateway again and renews the
    /// pinned certificate, which is how a new gateway certificate is accepted.
    private func reTest() {
        guard let address = configuration.gatewayAddress else { return }
        guard let apiKey: String = (try? configuration.apiKey()) ?? nil, !apiKey.isEmpty else {
            connectionTest = .failure(reason: .noStoredKey, field: .apiKey)
            return
        }

        connectionTest = .testing
        Task { @MainActor in
            switch await ConnectionTestRunner.run(addressText: address.urlString, apiKey: apiKey) {
            case .success(let result):
                try? configuration.saveConnection(result: result, apiKey: apiKey)
                connectionTest = .success(gatewayName: result.gatewayName)
            case .failure(let error):
                connectionTest = .failure(reason: .connection(error), field: error.field)
            }
        }
    }

    private var queryIntervalCard: some View {
        SettingsCard(
            title: T(.settingsQueryInterval),
            description: T(.settingsQueryIntervalDescription),
            statusTone: .ok,
            statusText: T(.settingsQueryIntervalStatus, configuration.monitorSettings.queryIntervalSeconds),
            control: SegmentedPills(
                options: MonitorSettings.queryIntervalOptions.map {
                    SegmentedPills<Int>.Option(value: $0, title: T(.settingsQueryIntervalOption, $0))
                },
                selection: configuration.monitorSettings.queryIntervalSeconds,
                onSelect: { configuration.setQueryInterval(seconds: $0) },
                accessibilityLabel: T(.settingsQueryInterval)
            )
        )
    }

    // MARK: - 监控事件

    private func eventCard(_ event: MonitoredEvent) -> some View {
        let isMonitored = configuration.monitorSettings.isEnabled(event)

        return SettingsCard(
            title: event.displayName,
            description: Self.eventDescription(event),
            statusTone: isMonitored ? .ok : .warn,
            statusText: isMonitored ? T(.settingsEventsMonitored) : T(.settingsEventsNotMonitored),
            keepsControlBeside: true,
            control: Toggle("", isOn: monitoredBinding(event))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(T(.settingsEventsToggle, event.displayName))
        )
    }

    private func monitoredBinding(_ event: MonitoredEvent) -> Binding<Bool> {
        Binding(
            get: { configuration.monitorSettings.isEnabled(event) },
            set: { configuration.setMonitored(event, enabled: $0) }
        )
    }

    /// Order of the event cards in 设置, taken from `Design/Mockups.html`.
    ///
    /// `MonitoredEvent.allCases` keeps the detection order of SentinelCore,
    /// which is not the order of the mockup: 检测到威胁 comes fourth here.
    private static let displayedEvents: [MonitoredEvent] = [
        .internetDown,
        .internetRestored,
        .internetDownMultipleTimes,
        .threatDetected,
        .internetDownTemporary,
        .packetLoss,
        .highLatency,
    ]

    /// Description of one event card, taken from `Design/Mockups.html`.
    private static func eventDescription(_ event: MonitoredEvent) -> String {
        switch event {
        case .internetDown: return T(.settingsEventInternetDownDescription)
        case .internetRestored: return T(.settingsEventInternetRestoredDescription)
        case .internetDownMultipleTimes: return T(.settingsEventMultipleDescription)
        case .threatDetected: return T(.settingsEventThreatDescription)
        case .internetDownTemporary: return T(.settingsEventTemporaryDescription)
        case .packetLoss: return T(.settingsEventPacketLossDescription)
        case .highLatency: return T(.settingsEventHighLatencyDescription)
        }
    }

    // MARK: - 通用

    private var launchAtLoginCard: some View {
        SettingsCard(
            title: T(.settingsLaunch),
            description: T(.settingsLaunchDescription),
            statusTone: launchAtLoginStatusTone,
            statusText: launchAtLoginStatusText,
            keepsControlBeside: true,
            control: Toggle("", isOn: Binding(
                get: { launchAtLogin.isEnabled },
                set: { launchAtLogin.setEnabled($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityLabel(T(.settingsLaunch))
        )
    }

    private var launchAtLoginStatusTone: StatusTone {
        if launchAtLogin.errorMessage != nil || launchAtLogin.requiresApproval { return .failure }
        return launchAtLogin.isEnabled ? .ok : .neutral
    }

    private var launchAtLoginStatusText: String {
        if let errorMessage = launchAtLogin.errorMessage { return errorMessage }
        if launchAtLogin.requiresApproval { return T(.settingsLaunchApproval) }
        return launchAtLogin.isEnabled ? T(.settingsOn) : T(.settingsOff)
    }

    private var logRetentionCard: some View {
        SettingsCard(
            title: T(.settingsRetention),
            description: T(.settingsRetentionDescription),
            statusTone: .ok,
            statusText: T(.settingsRetentionStatus, configuration.monitorSettings.logRetentionDays),
            control: SegmentedPills(
                options: MonitorSettings.logRetentionOptions.map {
                    SegmentedPills<Int>.Option(value: $0, title: T(.settingsRetentionOption, $0))
                },
                selection: configuration.monitorSettings.logRetentionDays,
                onSelect: { configuration.setLogRetention(days: $0) },
                accessibilityLabel: T(.settingsRetention)
            )
        )
    }
}

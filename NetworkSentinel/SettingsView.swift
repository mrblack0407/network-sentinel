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
                    Text("设置")
                        .font(.system(size: SentinelMetrics.pageTitleFontSize, weight: .bold))
                        .tracking(SentinelMetrics.pageTitleTracking)
                        .accessibilityAddTraits(.isHeader)

                    // Group order and title colors: 通用 pink, UniFi 网关 purple,
                    // 监控事件 teal — the colors follow the position, not the group.
                    GroupHeader(title: "通用", color: SentinelColor.groupPink)
                    LazyVGrid(columns: SettingsGridLayout.twoColumns, alignment: .leading, spacing: SentinelMetrics.cardSpacing) {
                        launchAtLoginCard
                        logRetentionCard
                    }

                    GroupHeader(title: "UniFi 网关", color: SentinelColor.groupPurple)
                    LazyVGrid(columns: SettingsGridLayout.twoColumns, alignment: .leading, spacing: SentinelMetrics.cardSpacing) {
                        connectionCard
                        queryIntervalCard
                    }

                    GroupHeader(title: "监控事件", color: SentinelColor.groupTeal)
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
                title: "连接",
                description: connectionDescription,
                statusTone: connectionStatusTone(at: context.date),
                statusText: connectionStatusText(at: context.date),
                control: Button("测试连接") {
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
                .help("连接设置")
                .accessibilityLabel("连接设置")
            )
        }
    }

    private var connectionDescription: String {
        guard let address = configuration.gatewayAddress?.urlString else {
            return "还没填 UniFi 网关地址"
        }
        return "\(address)\nAPI Key 存在钥匙串里"
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
        case .testing: return "正在测试连接…"
        case .success(let gatewayName): return "已连上 \(gatewayName)，能读到网络和威胁日志"
        case .failure(let reason, _): return reason
        case .idle:
            guard configuration.isConfigured else { return "还没连上 UniFi 网关" }
            guard monitor.isRunning else { return "监控没在运行" }
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
            connectionTest = .failure(reason: "钥匙串里没有 API Key，请打开连接设置重新填", field: .apiKey)
            return
        }

        connectionTest = .testing
        Task { @MainActor in
            switch await ConnectionTestRunner.run(addressText: address.urlString, apiKey: apiKey) {
            case .success(let result):
                try? configuration.saveConnection(result: result, apiKey: apiKey)
                connectionTest = .success(gatewayName: result.gatewayName)
            case .failure(let error):
                connectionTest = .failure(reason: error.reason, field: error.field)
            }
        }
    }

    private var queryIntervalCard: some View {
        SettingsCard(
            title: "查询间隔",
            description: "多久向网关查一次新日志。间隔越短通知越快。",
            statusTone: .ok,
            statusText: "每 \(configuration.monitorSettings.queryIntervalSeconds) 秒查一次",
            control: SegmentedPills(
                options: MonitorSettings.queryIntervalOptions.map {
                    SegmentedPills<Int>.Option(value: $0, title: "\($0) 秒")
                },
                selection: configuration.monitorSettings.queryIntervalSeconds,
                onSelect: { configuration.setQueryInterval(seconds: $0) },
                accessibilityLabel: "查询间隔"
            )
        )
    }

    // MARK: - 监控事件

    private func eventCard(_ event: MonitoredEvent) -> some View {
        let isMonitored = configuration.monitorSettings.isEnabled(event)

        return SettingsCard(
            title: event.displayName,
            description: Self.eventDescriptions[event] ?? "",
            statusTone: isMonitored ? .ok : .warn,
            statusText: isMonitored ? "监控中" : "未监控",
            control: Toggle("", isOn: monitoredBinding(event))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel("监控\(event.displayName)")
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

    /// Descriptions of the event cards, taken from `Design/Mockups.html`.
    private static let eventDescriptions: [MonitoredEvent: String] = [
        .internetDown: "WAN 线路断开时记录。UniFi 一般标为非常高。",
        .internetRestored: "断开的线路恢复时记录，并算出断了多久。",
        .internetDownMultipleTimes: "同一条线路 24 小时内多次中断时，UniFi 发出的提醒。",
        .threatDetected: "UniFi 的入侵防护发现可疑流量时记录。",
        .internetDownTemporary: "断开后很快自己恢复的闪断。",
        .packetLoss: "WAN 线路有丢包，但没有断网。",
        .highLatency: "WAN 线路延迟变高。",
    ]

    // MARK: - 通用

    private var launchAtLoginCard: some View {
        SettingsCard(
            title: "开机自启",
            description: "登录 Mac 后自动在菜单栏运行。",
            statusTone: launchAtLoginStatusTone,
            statusText: launchAtLoginStatusText,
            control: Toggle("", isOn: Binding(
                get: { launchAtLogin.isEnabled },
                set: { launchAtLogin.setEnabled($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityLabel("开机自启")
        )
    }

    private var launchAtLoginStatusTone: StatusTone {
        if launchAtLogin.errorMessage != nil { return .failure }
        return launchAtLogin.isEnabled ? .ok : .neutral
    }

    private var launchAtLoginStatusText: String {
        if let errorMessage = launchAtLogin.errorMessage { return errorMessage }
        return launchAtLogin.isEnabled ? "已开启" : "已关闭"
    }

    private var logRetentionCard: some View {
        SettingsCard(
            title: "日志保留",
            description: "超过这个时间的日志自动删除。",
            statusTone: .ok,
            statusText: "保留 \(configuration.monitorSettings.logRetentionDays) 天",
            control: SegmentedPills(
                options: MonitorSettings.logRetentionOptions.map {
                    SegmentedPills<Int>.Option(value: $0, title: "\($0) 天")
                },
                selection: configuration.monitorSettings.logRetentionDays,
                onSelect: { configuration.setLogRetention(days: $0) },
                accessibilityLabel: "日志保留"
            )
        )
    }
}

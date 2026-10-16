import AppKit
import Combine
import SentinelCore
import SwiftUI
import UserNotifications

/// 通知: the system permission of the app and the rules that decide what is
/// posted.
///
/// The page only reads and writes the settings `AppConfiguration` owns and the
/// authorization state of `UNUserNotificationCenter`; the decision to post a
/// notification stays in `MonitorService` and `SentinelCore`.
struct NotificationsPage: View {
    @ObservedObject var configuration: AppConfiguration
    /// The engine, for the Bark test push and the result of the last push.
    @ObservedObject var monitor: MonitorService

    /// What the user types into the Bark Key field; cleared once it is saved.
    @State private var barkKeyText = ""
    @State private var isBarkKeyRevealed = false
    /// Result of 「保存」 or 「发送测试」 on this page, shown under the buttons.
    @State private var barkMessage: (tone: StatusTone, text: String)?
    @State private var isSendingBarkTest = false

    /// Authorization the system reports for this app.
    @State private var authorization: UNAuthorizationStatus = .notDetermined

    var body: some View {
        GeometryReader { proxy in
            let columns = SettingsGridLayout.columns(forWidth: proxy.size.width)

            ScrollView {
                VStack(alignment: .leading, spacing: SentinelMetrics.contentSpacing) {
                    Text("通知")
                        .font(.system(size: SentinelMetrics.pageTitleFontSize, weight: .bold))
                        .tracking(SentinelMetrics.pageTitleTracking)
                        .accessibilityAddTraits(.isHeader)

                    GroupHeader(title: "系统通知", color: SentinelColor.groupNotifications)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: SentinelMetrics.cardSpacing) {
                        permissionCard
                    }

                    GroupHeader(title: "通知", color: SentinelColor.groupNotifications)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: SentinelMetrics.cardSpacing) {
                        notificationThresholdCard
                        alwaysNotifyOnRestoreCard
                        mergeSameKindCard
                    }

                    GroupHeader(title: "Bark 推送", color: SentinelColor.groupGeneral)
                    LazyVGrid(columns: SettingsGridLayout.twoColumns, alignment: .leading, spacing: SentinelMetrics.cardSpacing) {
                        barkSwitchCard
                        barkKeyCard
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // The user may change the permission in 系统设置 while the app runs, so
        // the card is refreshed whenever the app comes back to the front.
        .task { await refreshAuthorization() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshAuthorization() }
        }
    }

    // MARK: - 系统通知权限

    /// `true` when the system lets the app post notifications.
    private var isAuthorized: Bool {
        switch authorization {
        case .authorized, .provisional, .ephemeral: return true
        case .denied, .notDetermined: return false
        @unknown default: return false
        }
    }

    private var permissionCard: some View {
        SettingsCard(
            title: "系统通知权限",
            description: "在系统设置里允许后，断网和威胁的通知才会弹出来。",
            statusTone: isAuthorized ? .ok : .warn,
            statusText: isAuthorized ? "已允许" : "已关闭",
            control: permissionControl
        )
    }

    /// 「打开系统设置」 is only useful while the permission is missing.
    @ViewBuilder
    private var permissionControl: some View {
        if !isAuthorized {
            ToolbarButton(
                title: "打开系统设置",
                accessibilityLabel: "打开系统设置的通知面板"
            ) {
                openNotificationSettings()
            }
        }
    }

    /// Opens 系统设置 → 通知, where the app can be allowed.
    private func openNotificationSettings() {
        let panes = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.notifications",
        ]
        for pane in panes {
            guard let url = URL(string: pane) else { continue }
            if NSWorkspace.shared.open(url) { return }
        }
    }

    /// Reads what the system reports for this app.
    private func refreshAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorization = settings.authorizationStatus
    }

    // MARK: - 通知

    private var notificationThresholdCard: some View {
        SettingsCard(
            title: "弹通知",
            description: "选哪一级，就通知这一级及以上。",
            statusTone: .ok,
            statusText: Self.thresholdStatusText(for: configuration.monitorSettings.notifications.minimumSeverity),
            control: SegmentedPills(
                options: LogSeverity.allCases.map {
                    SegmentedPills<LogSeverity>.Option(value: $0, title: $0.displayName)
                },
                selection: configuration.monitorSettings.notifications.minimumSeverity,
                onSelect: { configuration.setMinimumSeverity($0) },
                accessibilityLabel: "弹通知的严重性"
            )
        )
    }

    private static func thresholdStatusText(for minimum: LogSeverity) -> String {
        let names = LogSeverity.allCases
            .filter { $0 >= minimum }
            .map { "「\($0.displayName)」" }
        return names.joined(separator: names.count > 2 ? "" : "和") + "会弹通知"
    }

    private var alwaysNotifyOnRestoreCard: some View {
        let isOn = configuration.monitorSettings.notifications.alwaysNotifyOnRestore

        return SettingsCard(
            title: "恢复时总是通知",
            description: "线路恢复时不管严重性都弹一条，写明断了多久。",
            statusTone: isOn ? .ok : .neutral,
            statusText: isOn ? "已开启" : "已关闭",
            control: Toggle("", isOn: Binding(
                get: { configuration.monitorSettings.notifications.alwaysNotifyOnRestore },
                set: { configuration.setAlwaysNotifyOnRestore($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityLabel("恢复时总是通知")
        )
    }

    private var mergeSameKindCard: some View {
        let isOn = configuration.monitorSettings.notifications.mergeSameKind
        let minutes = configuration.monitorSettings.notifications.mergeWindowSeconds / 60

        return SettingsCard(
            title: "同类事件合并",
            description: "\(minutes) 分钟内同类的事件合成一条通知。",
            statusTone: isOn ? .ok : .neutral,
            statusText: isOn ? "已开启" : "已关闭",
            control: Toggle("", isOn: Binding(
                get: { configuration.monitorSettings.notifications.mergeSameKind },
                set: { configuration.setMergeSameKind($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityLabel("同类事件合并")
        )
    }

    // MARK: - Bark 推送

    /// 「Bark 推送」: the switch and the state of the last push.
    private var barkSwitchCard: some View {
        let status = barkStatus
        return SettingsCard(
            title: "Bark 推送",
            description: "把同样的通知同步推到装了 Bark 的 iPhone。网关连不上和「非常高」的事件用时效性通知，专注模式下也能收到。",
            statusTone: status.tone,
            statusText: status.text,
            control: Toggle("", isOn: $configuration.barkEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!configuration.hasBarkKey)
                .accessibilityLabel("Bark 推送")
        )
    }

    private var barkStatus: (tone: StatusTone, text: String) {
        guard configuration.hasBarkKey else { return (.neutral, "还没填 Bark Key") }
        guard configuration.barkEnabled else { return (.neutral, "已关闭") }
        if let result = monitor.lastBarkResult {
            if result.succeeded {
                return (.ok, "已开启，上次推送 \(Self.barkTimeFormatter.string(from: result.date))")
            }
            return (.failure, "上次推送失败：\(result.failureReason ?? "原因不明")")
        }
        return (.ok, "已开启")
    }

    /// 「Bark Key」: the key, the server and the actions.
    private var barkKeyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bark Key")
                .font(.system(size: SentinelMetrics.cardTitleFontSize, weight: .semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text(configuration.hasBarkKey ? "Key 已存在钥匙串里，粘贴新的可替换" : "在 Bark App 首页复制推送链接或 Key")
                    .font(.system(size: SentinelMetrics.cardBodyFontSize))
                    .foregroundStyle(.secondary)
                ConnectionFieldBox(isError: barkMessage?.tone == .failure) {
                    HStack(spacing: 8) {
                        Group {
                            if isBarkKeyRevealed {
                                TextField("粘贴 Bark Key 或推送链接", text: $barkKeyText)
                            } else {
                                SecureField("粘贴 Bark Key 或推送链接", text: $barkKeyText)
                            }
                        }
                        .textFieldStyle(.plain)
                        .font(.system(size: SentinelMetrics.inputFontSize, design: .monospaced))

                        Button(isBarkKeyRevealed ? "隐藏" : "显示") { isBarkKeyRevealed.toggle() }
                            .buttonStyle(.plain)
                            .font(.system(size: SentinelMetrics.cardBodyFontSize))
                            .foregroundStyle(Color.accentColor)
                            .accessibilityLabel(isBarkKeyRevealed ? "隐藏 Bark Key" : "显示 Bark Key")
                    }
                }
                .accessibilityLabel("Bark Key")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("服务器（用自建服务器时才改）")
                    .font(.system(size: SentinelMetrics.cardBodyFontSize))
                    .foregroundStyle(.secondary)
                ConnectionFieldBox(isError: false) {
                    TextField(BarkConfiguration.defaultServerAddress, text: $configuration.barkServerAddress)
                        .textFieldStyle(.plain)
                        .font(.system(size: SentinelMetrics.inputFontSize, design: .monospaced))
                }
                .accessibilityLabel("Bark 服务器地址")
            }

            HStack(spacing: 8) {
                if let message = barkMessage {
                    Circle()
                        .fill(message.tone.color)
                        .frame(width: SentinelMetrics.statusLineDotSize, height: SentinelMetrics.statusLineDotSize)
                    Text(message.text)
                        .font(.system(size: SentinelMetrics.cardBodyFontSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if configuration.hasBarkKey {
                    ToolbarButton(title: "删除 Key", accessibilityLabel: "删除 Bark Key") { removeBarkKey() }
                    ToolbarButton(
                        title: isSendingBarkTest ? "发送中…" : "发送测试",
                        accessibilityLabel: "发送一条 Bark 测试推送"
                    ) { sendBarkTest() }
                    .disabled(isSendingBarkTest)
                }
                ToolbarButton(title: "保存", accessibilityLabel: "保存 Bark Key") { saveBarkKey() }
                    .disabled(barkKeyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(SentinelMetrics.settingsCardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SentinelColor.card, in: RoundedRectangle(cornerRadius: SentinelMetrics.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: SentinelMetrics.cardCornerRadius)
                .stroke(SentinelColor.border, lineWidth: 1)
        )
    }

    private func saveBarkKey() {
        do {
            _ = try configuration.saveBarkKey(barkKeyText)
            barkKeyText = ""
            isBarkKeyRevealed = false
            configuration.barkEnabled = true
            barkMessage = (.ok, "已保存，可以点「发送测试」试一下")
        } catch {
            barkMessage = (.failure, error.localizedDescription)
        }
    }

    private func removeBarkKey() {
        do {
            try configuration.removeBarkKey()
            configuration.barkEnabled = false
            barkMessage = (.neutral, "已删除 Bark Key")
        } catch {
            barkMessage = (.failure, error.localizedDescription)
        }
    }

    private func sendBarkTest() {
        isSendingBarkTest = true
        Task {
            let result = await monitor.sendBarkTest()
            isSendingBarkTest = false
            barkMessage = result.succeeded
                ? (.ok, "测试推送已发出，看看手机收到没有")
                : (.failure, result.failureReason ?? "发送失败")
        }
    }

    private static let barkTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "M/d H:mm"
        return formatter
    }()
}

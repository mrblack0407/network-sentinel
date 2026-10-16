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
}

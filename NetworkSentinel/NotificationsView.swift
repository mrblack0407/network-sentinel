import AppKit
import Combine
import SentinelCore
import SwiftUI
import UserNotifications

/// What 「保存」 or 「发送测试」 of the Bark card last did.
///
/// The message is kept as a case, not as a finished text, so a language change
/// rewrites the line under the buttons like every other text of the page.
enum BarkMessage: Equatable {
    /// The Key was saved.
    case saved
    /// The Key was removed.
    case deleted
    /// The test push was sent.
    case testSent
    /// Something failed; the reason is text of the app or of the system.
    case failure(String)

    var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }

    /// Color of the dot in front of the message.
    var tone: StatusTone {
        switch self {
        case .saved, .testSent: return .ok
        case .deleted: return .neutral
        case .failure: return .failure
        }
    }

    /// Text of the message in the current language.
    var text: String {
        switch self {
        case .saved: return T(.notificationsBarkSaved)
        case .deleted: return T(.notificationsBarkDeleted)
        case .testSent: return T(.notificationsBarkTestSent)
        case .failure(let reason): return reason
        }
    }
}

/// 通知: the system permission of the app, the update check and the rules that
/// decide what is posted.
///
/// The page only reads and writes the settings `AppConfiguration` owns, the
/// authorization state of `UNUserNotificationCenter` and the result of
/// `UpdateChecker`; the decision to post a notification stays in
/// `MonitorService` and `SentinelCore`.
struct NotificationsPage: View {
    @ObservedObject var configuration: AppConfiguration
    /// The engine, for the Bark test push and the result of the last push.
    @ObservedObject var monitor: MonitorService
    /// The update check, for the 「自动检查更新」 card.
    @ObservedObject var updateChecker: UpdateChecker

    /// The Bark Key field: filled with the saved Key (shown as dots, 「显示」
    /// reveals it), like the API Key of the 连接设置窗口.
    @State private var barkKeyText = ""
    @State private var isBarkKeyRevealed = false
    /// Result of 「保存」 or 「发送测试」 on this page, shown under the buttons.
    @State private var barkMessage: BarkMessage?
    @State private var isSendingBarkTest = false

    /// Authorization the system reports for this app.
    @State private var authorization: UNAuthorizationStatus = .notDetermined

    var body: some View {
        GeometryReader { proxy in
            let columns = SettingsGridLayout.columns(forWidth: proxy.size.width)

            ScrollView {
                VStack(alignment: .leading, spacing: SentinelMetrics.contentSpacing) {
                    Text(T(.pageNotifications))
                        .font(.system(size: SentinelMetrics.pageTitleFontSize, weight: .bold))
                        .tracking(SentinelMetrics.pageTitleTracking)
                        .accessibilityAddTraits(.isHeader)

                    GroupHeader(title: T(.notificationsGroupPermission), color: SentinelColor.groupPink)
                    LazyVGrid(columns: SettingsGridLayout.twoColumns, alignment: .leading, spacing: SentinelMetrics.cardSpacing) {
                        permissionCard
                        updateCard
                    }

                    GroupHeader(title: T(.notificationsGroupNotifications), color: SentinelColor.groupPurple)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: SentinelMetrics.cardSpacing) {
                        notificationThresholdCard
                        alwaysNotifyOnRestoreCard
                        mergeSameKindCard
                    }

                    GroupHeader(title: T(.notificationsGroupBark), color: SentinelColor.groupTeal)
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
        .onAppear { barkKeyText = configuration.barkKey() ?? "" }
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
            title: T(.notificationsPermissionTitle),
            description: T(.notificationsPermissionDescription),
            statusTone: isAuthorized ? .ok : .warn,
            statusText: isAuthorized ? T(.notificationsPermissionAllowed) : T(.notificationsPermissionOff),
            control: permissionControl
        )
    }

    /// 「打开系统设置」 is only useful while the permission is missing.
    @ViewBuilder
    private var permissionControl: some View {
        if !isAuthorized {
            ToolbarButton(
                title: T(.notificationsPermissionOpen),
                accessibilityLabel: T(.notificationsPermissionOpenReadOut)
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

    // MARK: - 自动检查更新

    /// 「自动检查更新」: the switch and what the last check found.
    private var updateCard: some View {
        let status = updateStatus

        return SettingsCard(
            title: T(.notificationsUpdateTitle),
            description: T(.notificationsUpdateDescription),
            statusTone: status.tone,
            statusText: status.text,
            keepsControlBeside: true,
            control: Toggle("", isOn: $configuration.checksForUpdates)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(T(.notificationsUpdateTitle))
        )
    }

    /// The state of the update check, in the order the card shows it.
    ///
    /// A switch that is off wins over everything else: while it is off there is
    /// no result to show. A check that never read a release — a new install, an
    /// unreachable GitHub — is 尚未检查.
    private var updateStatus: (tone: StatusTone, text: String) {
        guard configuration.checksForUpdates else { return (.neutral, T(.settingsOff)) }
        if let release = updateChecker.latestRelease {
            return (.ok, T(.notificationsUpdateAvailable, release.version))
        }
        return updateChecker.hasChecked
            ? (.ok, T(.notificationsUpdateUpToDate))
            : (.neutral, T(.notificationsUpdateNotChecked))
    }

    // MARK: - 通知

    private var notificationThresholdCard: some View {
        SettingsCard(
            title: T(.notificationsThreshold),
            description: T(.notificationsThresholdDescription),
            statusTone: .ok,
            statusText: Self.thresholdStatusText(for: configuration.monitorSettings.notifications.minimumSeverity),
            control: SegmentedPills(
                options: LogSeverity.allCases.map {
                    SegmentedPills<LogSeverity>.Option(value: $0, title: $0.displayName)
                },
                selection: configuration.monitorSettings.notifications.minimumSeverity,
                onSelect: { configuration.setMinimumSeverity($0) },
                accessibilityLabel: T(.notificationsThresholdReadOut)
            )
        )
    }

    private static func thresholdStatusText(for minimum: LogSeverity) -> String {
        let names = LogSeverity.allCases
            .filter { $0 >= minimum }
            .map { T(.notificationsThresholdQuoted, $0.displayName) }
        let separator = names.count > 2
            ? T(.notificationsThresholdList)
            : T(.notificationsThresholdPair)
        return names.joined(separator: separator) + T(.notificationsThresholdSuffix)
    }

    private var alwaysNotifyOnRestoreCard: some View {
        let isOn = configuration.monitorSettings.notifications.alwaysNotifyOnRestore

        return SettingsCard(
            title: T(.notificationsRestoreTitle),
            description: T(.notificationsRestoreDescription),
            statusTone: isOn ? .ok : .neutral,
            statusText: isOn ? T(.settingsOn) : T(.settingsOff),
            keepsControlBeside: true,
            control: Toggle("", isOn: Binding(
                get: { configuration.monitorSettings.notifications.alwaysNotifyOnRestore },
                set: { configuration.setAlwaysNotifyOnRestore($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityLabel(T(.notificationsRestoreTitle))
        )
    }

    private var mergeSameKindCard: some View {
        let isOn = configuration.monitorSettings.notifications.mergeSameKind
        let minutes = configuration.monitorSettings.notifications.mergeWindowSeconds / 60

        return SettingsCard(
            title: T(.notificationsMergeTitle),
            description: T(.notificationsMergeDescription, minutes),
            statusTone: isOn ? .ok : .neutral,
            statusText: isOn ? T(.settingsOn) : T(.settingsOff),
            keepsControlBeside: true,
            control: Toggle("", isOn: Binding(
                get: { configuration.monitorSettings.notifications.mergeSameKind },
                set: { configuration.setMergeSameKind($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityLabel(T(.notificationsMergeTitle))
        )
    }

    // MARK: - Bark 推送

    /// 「Bark 推送」: the switch and the state of the last push.
    private var barkSwitchCard: some View {
        let status = barkStatus
        return SettingsCard(
            title: T(.notificationsBarkTitle),
            description: T(.notificationsBarkDescription),
            statusTone: status.tone,
            statusText: status.text,
            keepsControlBeside: true,
            control: Toggle("", isOn: $configuration.barkEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!configuration.hasBarkKey)
                .accessibilityLabel(T(.notificationsBarkTitle))
        )
    }

    private var barkStatus: (tone: StatusTone, text: String) {
        guard configuration.hasBarkKey else { return (.neutral, T(.notificationsBarkNoKey)) }
        guard configuration.barkEnabled else { return (.neutral, T(.settingsOff)) }
        if let result = monitor.lastBarkResult {
            if result.succeeded {
                return (.ok, T(.notificationsBarkLastPush, Self.barkTime(result.date)))
            }
            return (.failure, T(
                .notificationsBarkLastFailed,
                result.failureReason ?? T(.notificationsBarkUnknownReason)
            ))
        }
        return (.ok, T(.notificationsBarkOn))
    }

    /// 「Bark 设置」: the server, the key, the ringtone and the actions.
    private var barkKeyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(T(.notificationsBarkSettings))
                .font(.system(size: SentinelMetrics.cardTitleFontSize, weight: .semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text(T(.notificationsBarkServer))
                    .font(.system(size: SentinelMetrics.cardBodyFontSize))
                    .foregroundStyle(.secondary)
                ConnectionFieldBox(isError: false) {
                    TextField(BarkConfiguration.defaultServerAddress, text: $configuration.barkServerAddress)
                        .textFieldStyle(.plain)
                        .font(.system(size: SentinelMetrics.inputFontSize, design: .monospaced))
                }
                .accessibilityLabel(T(.notificationsBarkServerReadOut))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(
                    configuration.hasBarkKey
                        ? T(.notificationsBarkKeySaved)
                        : T(.notificationsBarkKeyEmpty)
                )
                    .font(.system(size: SentinelMetrics.cardBodyFontSize))
                    .foregroundStyle(.secondary)
                ConnectionFieldBox(isError: barkMessage?.isFailure == true) {
                    HStack(spacing: 8) {
                        Group {
                            if isBarkKeyRevealed {
                                TextField(T(.notificationsBarkKeyPlaceholder), text: $barkKeyText)
                            } else {
                                SecureField(T(.notificationsBarkKeyPlaceholder), text: $barkKeyText)
                            }
                        }
                        .textFieldStyle(.plain)
                        .font(.system(size: SentinelMetrics.inputFontSize, design: .monospaced))

                        Button(isBarkKeyRevealed ? T(.notificationsBarkHide) : T(.notificationsBarkShow)) { isBarkKeyRevealed.toggle() }
                            .buttonStyle(.plain)
                            .font(.system(size: SentinelMetrics.cardBodyFontSize))
                            .foregroundStyle(Color.accentColor)
                            .accessibilityLabel(isBarkKeyRevealed ? T(.notificationsBarkHideReadOut) : T(.notificationsBarkShowReadOut))
                    }
                }
                .accessibilityLabel("Bark Key")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(T(.notificationsBarkRingtone))
                    .font(.system(size: SentinelMetrics.cardBodyFontSize))
                    .foregroundStyle(.secondary)
                ConnectionFieldBox(isError: false) {
                    TextField(T(.notificationsBarkRingtonePlaceholder), text: $configuration.barkSound)
                        .textFieldStyle(.plain)
                        .font(.system(size: SentinelMetrics.inputFontSize, design: .monospaced))
                }
                .accessibilityLabel(T(.notificationsBarkRingtone))
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
                    ToolbarButton(title: T(.notificationsBarkDeleteKey), accessibilityLabel: T(.notificationsBarkDeleteKeyReadOut)) { removeBarkKey() }
                    ToolbarButton(
                        title: isSendingBarkTest ? T(.notificationsBarkSending) : T(.notificationsBarkSendTest),
                        accessibilityLabel: T(.notificationsBarkSendTestReadOut)
                    ) { sendBarkTest() }
                    .disabled(isSendingBarkTest)
                }
                ToolbarButton(title: T(.notificationsBarkSave), accessibilityLabel: T(.notificationsBarkSaveReadOut)) { saveBarkKey() }
                    .disabled(!isBarkKeyChanged)
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

    /// `true` when the field holds something new to save.
    private var isBarkKeyChanged: Bool {
        let typed = barkKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !typed.isEmpty && typed != (configuration.barkKey() ?? "")
    }

    private func saveBarkKey() {
        do {
            _ = try configuration.saveBarkKey(barkKeyText)
            // A pasted push link is stored as its Key: show what was saved.
            barkKeyText = configuration.barkKey() ?? ""
            isBarkKeyRevealed = false
            configuration.barkEnabled = true
            barkMessage = .saved
        } catch {
            barkMessage = .failure(error.localizedDescription)
        }
    }

    private func removeBarkKey() {
        do {
            try configuration.removeBarkKey()
            barkKeyText = ""
            configuration.barkEnabled = false
            barkMessage = .deleted
        } catch {
            barkMessage = .failure(error.localizedDescription)
        }
    }

    private func sendBarkTest() {
        isSendingBarkTest = true
        Task {
            let result = await monitor.sendBarkTest()
            isSendingBarkTest = false
            barkMessage = result.succeeded
                ? .testSent
                : .failure(result.failureReason ?? T(.notificationsBarkSendFailed))
        }
    }

    /// `10/16 9:44` of the last push, in the language of the page.
    private static func barkTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppText.locale
        formatter.dateFormat = "M/d H:mm"
        return formatter.string(from: date)
    }
}

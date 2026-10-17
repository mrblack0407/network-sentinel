import AppKit
import SentinelCore
import SwiftUI

/// 菜单栏弹出面板: the gateway name, the WAN lines, the last five events and
/// the three links at the bottom.
struct MenuBarPanel: View {
    @ObservedObject var state: AppState
    @ObservedObject var configuration: AppConfiguration
    /// The engine: the panel shows what it published.
    @ObservedObject var monitor: MonitorService

    /// Which events the list shows. 全部 until the user picks another one.
    @State private var filter: PanelEventFilter = .all

    var body: some View {
        let now = Date()
        let status = MenuBarStatusBuilder.status(
            gatewayName: monitor.gatewayStatus?.name ?? configuration.gatewayName,
            queryIntervalSeconds: configuration.monitorSettings.queryIntervalSeconds,
            connectionState: monitor.connectionState,
            errorDescription: monitor.lastErrorDescription,
            gatewayStatus: monitor.gatewayStatus,
            events: monitor.events,
            now: now
        )
        let events = Array(status.recentEvents.filter { filter.includes($0.event) }.prefix(Self.eventLimit))

        VStack(alignment: .leading, spacing: SentinelMetrics.panelSpacing) {
            header(status)

            if let reason = status.connectionReason {
                connectionReason(reason)
            }

            if !status.lines.isEmpty {
                lineList(status.lines, now: now)
            }

            filterRow(status)

            eventList(events)

            Divider()

            footer
        }
        .padding(SentinelMetrics.panelPadding)
        .frame(width: SentinelMetrics.panelWidth, alignment: .leading)
    }

    /// Events the panel lists at most, as in the mockup.
    private static let eventLimit = 5

    // MARK: - Header

    /// Gateway name (`.gwrow`).
    private func header(_ status: MenuBarStatus) -> some View {
        Text(status.gatewayName.isEmpty ? "Network Sentinel" : status.gatewayName)
            .font(.system(size: SentinelMetrics.panelTitleFontSize, weight: .bold))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    /// The red line above the WAN lines: why the app cannot read the gateway.
    private func connectionReason(_ reason: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: SentinelMetrics.hintFontSize))
                .accessibilityHidden(true)

            Text(reason)
                .font(.system(size: SentinelMetrics.hintFontSize))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(SentinelColor.failure)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("连接问题：\(reason)")
    }

    // MARK: - WAN lines

    /// One row per WAN line the gateway reported, in one grouped box
    /// (`.sc.tight`): 14 pt corners, a hairline border and a line between rows.
    private func lineList(_ lines: [WANLineStatus], now: Date) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                if index > 0 {
                    Divider()
                }
                lineRow(line, now: now)
            }
        }
        .padding(.vertical, SentinelMetrics.tightGroupVerticalPadding)
        .background(
            RoundedRectangle(cornerRadius: SentinelMetrics.tightGroupCornerRadius)
                .fill(SentinelColor.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SentinelMetrics.tightGroupCornerRadius)
                .stroke(SentinelColor.border, lineWidth: 1)
        )
    }

    /// One line (`.wan`): status dot, `WAN1`, the provider and the state on the right.
    private func lineRow(_ line: WANLineStatus, now: Date) -> some View {
        HStack(spacing: 10) {
            GlowDot(tone: line.state.tone)

            Text(line.id)
                .font(.system(size: SentinelMetrics.timestampFontSize, design: .monospaced))
                .frame(width: SentinelMetrics.panelLineIDColumnWidth, alignment: .leading)

            if let ispName = line.ispName, !ispName.isEmpty {
                Text(ispName)
                    .font(.system(size: SentinelMetrics.panelRowFontSize))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(line.detailText(now: now))
                .font(.system(size: SentinelMetrics.timestampFontSize))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(SentinelMetrics.tightRowPadding)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(line.accessibilityText(now: now))
    }

    // MARK: - Filter and summary

    private func filterRow(_ status: MenuBarStatus) -> some View {
        HStack(spacing: 8) {
            SegmentedPills(
                options: PanelEventFilter.allCases.map {
                    SegmentedPills<PanelEventFilter>.Option(value: $0, title: $0.title)
                },
                selection: filter,
                onSelect: { filter = $0 },
                accessibilityLabel: "事件筛选"
            )

            Spacer(minLength: 8)

            Text("24 小时：中断 \(status.outageCount24h) 次 · 威胁 \(status.threatCount24h) 条")
                .font(.system(size: SentinelMetrics.hintFontSize))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityLabel("近 24 小时中断 \(status.outageCount24h) 次，威胁 \(status.threatCount24h) 条")
        }
    }

    // MARK: - Events

    /// The newest events of the filter, in the same grouped box as the lines.
    ///
    /// The box always keeps the height of a full list, whatever the filter
    /// finds: a shorter panel makes the menu bar window resize, and macOS then
    /// moves it away from the icon.
    private func eventList(_ events: [MonitoredLogEvent]) -> some View {
        ZStack(alignment: .top) {
            // Invisible full list that sets the height of the box.
            VStack(spacing: 0) {
                ForEach(0..<Self.eventLimit, id: \.self) { index in
                    if index > 0 {
                        Divider()
                    }
                    placeholderRow
                }
            }
            .hidden()
            .accessibilityHidden(true)

            if events.isEmpty {
                Text("近 24 小时没有监控事件")
                    .font(.system(size: SentinelMetrics.hintFontSize))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        if index > 0 {
                            Divider()
                        }
                        eventRow(event)
                    }
                }
            }
        }
        .padding(.vertical, SentinelMetrics.tightGroupVerticalPadding)
        .background(
            RoundedRectangle(cornerRadius: SentinelMetrics.tightGroupCornerRadius)
                .fill(SentinelColor.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SentinelMetrics.tightGroupCornerRadius)
                .stroke(SentinelColor.border, lineWidth: 1)
        )
    }

    /// A row with the same parts and paddings as `eventRow`, for the height.
    private var placeholderRow: some View {
        HStack(spacing: 12) {
            SeverityBar(severity: .low)
            Text("互联网中断")
                .font(.system(size: SentinelMetrics.panelRowFontSize))
                .frame(maxWidth: .infinity, alignment: .leading)
            LogTimestampColumns(date: Date(timeIntervalSince1970: 0))
        }
        .monospacedDigit()
        .padding(SentinelMetrics.tightRowPadding)
    }

    private func eventRow(_ event: MonitoredLogEvent) -> some View {
        HStack(spacing: 12) {
            SeverityBar(severity: event.severity)
                .frame(width: SentinelMetrics.severityColumnWidth, alignment: .leading)

            Text(event.event.displayName)
                .font(.system(size: SentinelMetrics.panelRowFontSize))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(.primary)

            // Date and time are two right-aligned columns, so rows line up
            // whatever the number of digits in the month, day or hour.
            LogTimestampColumns(date: event.timestamp)
        }
        .monospacedDigit()
        .padding(SentinelMetrics.tightRowPadding)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.readOut(of: event))
    }

    /// One event in one sentence, for a screen reader.
    private static func readOut(of event: MonitoredLogEvent) -> String {
        "\(event.severity?.displayName ?? "严重性未知")，\(event.event.displayName)，\(LogTimestampText.stamp(event.timestamp))"
    }

    // MARK: - Footer

    /// The three links (`.foot`), evenly spread under a hairline.
    private var footer: some View {
        HStack(spacing: 12) {
            PanelFooterButton(title: "打开主窗口", accessibilityLabel: "打开主窗口") {
                state.windows.showMainWindow()
            }

            Spacer(minLength: 12)

            PanelFooterButton(title: "设置…", accessibilityLabel: "打开设置") {
                state.windows.showMainWindow(selecting: .settings)
            }

            Spacer(minLength: 12)

            PanelFooterButton(
                title: "退出",
                accessibilityLabel: "退出 Network Sentinel",
                shortcut: KeyboardShortcut("q", modifiers: .command)
            ) {
                NSApp.terminate(nil)
            }
        }
        .padding(.top, SentinelMetrics.panelFooterTopPadding)
    }
}

/// The 全部 / 网络 / 威胁 filter of the event list of the 菜单栏弹出面板.
enum PanelEventFilter: String, CaseIterable, Identifiable {
    case all
    case network
    case threat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .network: return "网络"
        case .threat: return "威胁"
        }
    }

    /// `true` when the event is shown with this filter.
    ///
    /// 网络 is the six monitored events that are not 检测到威胁.
    func includes(_ event: MonitoredEvent) -> Bool {
        switch self {
        case .all: return true
        case .network: return event != .threatDetected
        case .threat: return event == .threatDetected
        }
    }
}

/// One link of the footer of the 菜单栏弹出面板.
struct PanelFooterButton: View {
    let title: String
    let accessibilityLabel: String
    /// Keyboard shortcut of the link, `nil` for the plain ones.
    var shortcut: KeyboardShortcut? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: SentinelMetrics.smallButtonFontSize))
                .foregroundStyle(Color.accentColor)
                .padding(.vertical, 3)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcut)
        .accessibilityLabel(accessibilityLabel)
    }
}

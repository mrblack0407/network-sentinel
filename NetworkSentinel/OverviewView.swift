import SentinelCore
import SwiftUI

/// 概览: the gateway line, one card per WAN line, the threat card and 最近事件.
///
/// Everything on the page comes from what `MonitorService` published; the rules
/// themselves live in `SentinelCore` (`MenuBarStatusBuilder`, `OutageStripBuilder`,
/// `WANLineStatisticsBuilder`, `ThreatStatisticsBuilder`), so the page only draws.
struct OverviewView: View {
    @ObservedObject var configuration: AppConfiguration
    /// The monitoring engine: 线路状态, 24 小时统计 and the log all come from it.
    @ObservedObject var monitor: MonitorService
    /// The page selection, for 「去设置」 of the connection banner.
    @ObservedObject var windowState: MainWindowState

    /// The 最近事件 filter, the same 全部 / 网络 / 威胁 as the 菜单栏弹出面板.
    @State private var eventFilter: PanelEventFilter = .all

    /// Events the 最近事件 card lists at most.
    private static let eventLimit = 10
    /// Width of the 事件 column of a 最近事件 row, so the descriptions line up.
    private static let eventNameWidth: CGFloat = 118

    var body: some View {
        // 「已断开 3 分」 and the strip count from 「现在」, so the page follows
        // the clock instead of waiting for the next query.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            GeometryReader { proxy in
                content(now: context.date, width: proxy.size.width)
            }
        }
    }

    // MARK: - Page

    private func content(now: Date, width: CGFloat) -> some View {
        let status = MenuBarStatusBuilder.status(
            gatewayName: monitor.gatewayStatus?.name ?? configuration.gatewayName,
            queryIntervalSeconds: configuration.monitorSettings.queryIntervalSeconds,
            connectionState: monitor.connectionState,
            errorDescription: monitor.lastErrorDescription,
            gatewayStatus: monitor.gatewayStatus,
            events: monitor.events,
            now: now
        )

        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("概览")
                    .font(.system(size: 20, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)

                if let reason = status.connectionReason {
                    connectionBanner(reason)
                }

                gatewayInfo(status)

                if monitor.lastQueryAt == nil {
                    // A fresh install: the first round has not finished yet.
                    loading
                } else {
                    cards(status, now: now, width: width)
                }
            }
            .padding(EdgeInsets(top: 16, leading: 22, bottom: 24, trailing: 22))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The red line at the top: why the app cannot read the gateway right now.
    private func connectionBanner(_ reason: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(SentinelColor.failure)
                .accessibilityHidden(true)

            Text(reason)
                .font(.system(size: 12.5))
                .foregroundStyle(SentinelColor.failure)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("去设置") {
                windowState.selection = .settings
            }
            .accessibilityLabel("去设置")
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(SentinelColor.failure.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(SentinelColor.failure.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    /// 网关, 查询间隔 and 上次查询.
    private func gatewayInfo(_ status: MenuBarStatus) -> some View {
        HStack(alignment: .top, spacing: 12) {
            infoColumn(title: "网关", value: status.gatewayName.isEmpty ? "—" : status.gatewayName)
            infoColumn(title: "查询间隔", value: "\(status.queryIntervalSeconds) 秒")
            infoColumn(
                title: "上次查询",
                value: monitor.lastQueryAt.map(LogTimestampText.clock) ?? "—"
            )
        }
    }

    private func infoColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)：\(value)")
    }

    /// The page before the first round finished.
    private var loading: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("正在读取 UniFi 网关的日志…")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在读取 UniFi 网关的日志")
    }

    // MARK: - Cards

    @ViewBuilder
    private func cards(_ status: MenuBarStatus, now: Date, width: CGFloat) -> some View {
        let outages = OutagePairer.outages(in: monitor.events)

        LazyVGrid(columns: SettingsGridLayout.columns(forWidth: width), alignment: .leading, spacing: 14) {
            ForEach(status.lines) { line in
                lineCard(line, outages: outages, now: now)
            }
            threatCard(now: now)
        }

        recentEventsCard(status)
    }

    /// 一条线路一张卡片: 状态, 「已恢复 1 分 25 秒」, 24 小时色条 and the 三栏统计.
    private func lineCard(_ line: WANLineStatus, outages: [Outage], now: Date) -> some View {
        let strip = OutageStripBuilder.strip(
            events: monitor.events,
            outages: outages,
            wanID: line.id,
            now: now
        )
        let statistics = WANLineStatisticsBuilder.statistics(
            outages: outages,
            wanID: line.id,
            now: now
        )

        return SentinelCard {
            VStack(alignment: .leading, spacing: 8) {
                CardLabel(text: Self.lineLabel(line))

                BigStat(text: Self.stateText(line.state), color: Self.stateColor(line.state))

                Text(line.detailText(now: now))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                OutageStripView(strip: strip)

                SubStatistics(items: [
                    SubStatistic(id: "count", value: "\(statistics.outageCount)", unit: "次", caption: "24 小时中断"),
                    SubStatistic(id: "total", value: statistics.totalText, caption: "累计断网"),
                    SubStatistic(id: "longest", value: statistics.longestText, caption: "最长一次"),
                ])
            }
        }
    }

    /// 检测到威胁 of the last 24 hours, split by severity.
    private func threatCard(now: Date) -> some View {
        let statistics = ThreatStatisticsBuilder.statistics(events: monitor.events, now: now)

        return SentinelCard {
            VStack(alignment: .leading, spacing: 8) {
                CardLabel(text: "检测到威胁 · 24 小时")

                BigStat(text: "\(statistics.total)", unit: "条")

                if statistics.total == 0 {
                    Text("近 24 小时没有威胁")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    // The three columns carry the numbers; the line keeps the
                    // card the same shape as the 线路卡片 next to it.
                    Text("UniFi 入侵防护记下的尝试")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                SubStatistics(items: [
                    SubStatistic(id: "very-high", value: "\(statistics.veryHigh)", caption: "非常高"),
                    SubStatistic(id: "high", value: "\(statistics.high)", caption: "高"),
                    SubStatistic(id: "medium", value: "\(statistics.mediumAndBelow)", caption: "中及以下"),
                ])
            }
        }
    }

    /// 最近事件: the newest ten entries of the last 24 hours.
    private func recentEventsCard(_ status: MenuBarStatus) -> some View {
        let events = Array(
            status.recentEvents
                .filter { eventFilter.includes($0.event) }
                .prefix(Self.eventLimit)
        )

        return SentinelCard(fillsHeight: false) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    CardLabel(text: "最近事件")
                    Spacer(minLength: 8)
                    SegmentedPills(
                        options: PanelEventFilter.allCases.map {
                            SegmentedPills<PanelEventFilter>.Option(value: $0, title: $0.title)
                        },
                        selection: eventFilter,
                        onSelect: { eventFilter = $0 },
                        accessibilityLabel: "事件筛选"
                    )
                }

                if events.isEmpty {
                    Text("近 24 小时没有监控事件")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 16)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                            if index > 0 {
                                Divider()
                            }
                            recentEventRow(event)
                        }
                    }
                }
            }
        }
    }

    private func recentEventRow(_ event: MonitoredLogEvent) -> some View {
        HStack(spacing: 12) {
            SeverityBar(severity: event.severity)

            Text(event.event.displayName)
                .font(.system(size: 12.5))
                .lineLimit(1)
                .frame(width: Self.eventNameWidth, alignment: .leading)

            Text(NotificationPlanner().notificationBody(for: event))
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            LogTimestampColumns(date: event.timestamp)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.readOut(of: event))
    }

    // MARK: - Texts

    /// `WAN1 · CHINA TELECOM`, or `WAN1` when the gateway sent no provider.
    private static func lineLabel(_ line: WANLineStatus) -> String {
        let isp = line.ispName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !isp.isEmpty else { return line.id }
        return "\(line.id) · \(isp.uppercased())"
    }

    /// The big state of a line card.
    ///
    /// 断网中 is the wording of the mockup for a line the gateway reports as
    /// down; 备用 and 未启用 are not a problem, so they keep the plain color.
    private static func stateText(_ state: SnapshotWANState) -> String {
        switch state {
        case .online: return "在线"
        case .offline: return "断网中"
        case .standby: return "备用"
        case .disabled: return "未启用"
        }
    }

    private static func stateColor(_ state: SnapshotWANState) -> Color {
        switch state {
        case .online: return SentinelColor.ok
        case .offline: return SentinelColor.failure
        case .standby, .disabled: return .primary
        }
    }

    /// One event in one sentence, for a screen reader.
    private static func readOut(of event: MonitoredLogEvent) -> String {
        let severity = event.severity?.displayName ?? "严重性未知"
        let description = NotificationPlanner().notificationBody(for: event)
        return "\(severity)，\(event.event.displayName)，\(description)，\(LogTimestampText.stamp(event.timestamp))"
    }
}

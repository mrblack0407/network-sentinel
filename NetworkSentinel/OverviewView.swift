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
    private static let eventLimit = 5

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
            VStack(alignment: .leading, spacing: SentinelMetrics.contentSpacing) {
                Text(T(.pageOverview))
                    .font(.system(size: SentinelMetrics.pageTitleFontSize, weight: .bold))
                    .tracking(SentinelMetrics.pageTitleTracking)
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The red line at the top: why the app cannot read the gateway right now.
    private func connectionBanner(_ reason: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: SentinelMetrics.hintFontSize))
                .foregroundStyle(SentinelColor.failure)
                .accessibilityHidden(true)

            Text(reason)
                .font(.system(size: SentinelMetrics.bodyFontSize))
                .foregroundStyle(SentinelColor.failure)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(T(.overviewOpenSettings)) {
                windowState.selection = .settings
            }
            .accessibilityLabel(T(.overviewOpenSettings))
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

    /// 网关, 查询间隔 and 上次查询 (`.hstats`).
    private func gatewayInfo(_ status: MenuBarStatus) -> some View {
        HStack(alignment: .top, spacing: SentinelMetrics.contentSpacing) {
            infoColumn(title: T(.overviewGateway), value: status.gatewayName.isEmpty ? "—" : status.gatewayName)
            infoColumn(title: T(.overviewQueryInterval), value: T(.overviewIntervalSeconds, status.queryIntervalSeconds))
            infoColumn(
                title: T(.overviewLastQuery),
                value: monitor.lastQueryAt.map(LogTimestampText.clock) ?? "—"
            )
        }
    }

    private func infoColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: SentinelMetrics.statisticLabelFontSize))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: SentinelMetrics.statisticValueFontSize, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(T(.commonLabelValue, title, value))
    }

    /// The page before the first round finished.
    private var loading: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(T(.overviewLoading))
                .font(.system(size: SentinelMetrics.bodyFontSize))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(T(.overviewLoadingReadOut))
    }

    // MARK: - Cards

    @ViewBuilder
    private func cards(_ status: MenuBarStatus, now: Date, width: CGFloat) -> some View {
        let outages = OutagePairer.outages(in: monitor.events)
        // One column per card: a gateway without WAN2 shows the 线路卡片 and the
        // 威胁卡片 alone, sharing the row instead of leaving a column empty.
        let columns = SettingsGridLayout.cardColumns(cardCount: status.lines.count + 1, width: width)

        VStack(alignment: .leading, spacing: SentinelMetrics.cardSpacing) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: SentinelMetrics.cardSpacing) {
                ForEach(status.lines) { line in
                    lineCard(line, outages: outages, now: now)
                }
                threatCard(now: now)
            }

            recentEventsCard(status)
        }
    }

    /// 一条线路一张卡片: 状态, how long it has been down, 24 小时色条 and the 三栏统计.
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
            VStack(alignment: .leading, spacing: SentinelMetrics.cardContentSpacing) {
                CardLabel(text: Self.lineLabel(line))

                BigStat(text: Self.stateText(line.state), color: Self.stateColor(line.state))

                Text(Self.hint(for: line, now: now))
                    .font(.system(size: SentinelMetrics.hintFontSize))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                OutageStripView(strip: strip)

                SubStatistics(items: [
                    SubStatistic(
                        id: "count",
                        value: "\(statistics.outageCount)",
                        unit: T(.commonUnitTimes),
                        caption: T(.overviewSubOutages24h)
                    ),
                    SubStatistic(id: "total", value: statistics.totalText, caption: T(.overviewSubTotalOutage)),
                    SubStatistic(id: "longest", value: statistics.longestText, caption: T(.overviewSubLongest)),
                ])
            }
        }
    }

    /// 检测到威胁 of the last 24 hours, split by severity.
    private func threatCard(now: Date) -> some View {
        let statistics = ThreatStatisticsBuilder.statistics(events: monitor.events, now: now)

        return SentinelCard {
            VStack(alignment: .leading, spacing: SentinelMetrics.cardContentSpacing) {
                CardLabel(text: T(.overviewThreatCardLabel))

                BigStat(text: "\(statistics.total)", unit: T(.commonUnitItems))

                if statistics.total == 0 {
                    Text(T(.overviewNoThreats))
                        .font(.system(size: SentinelMetrics.hintFontSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    // The three columns carry the numbers; the line keeps the
                    // card the same shape as the 线路卡片 next to it.
                    Text(T(.overviewThreatHint))
                        .font(.system(size: SentinelMetrics.hintFontSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                SubStatistics(items: [
                    SubStatistic(id: "very-high", value: "\(statistics.veryHigh)", caption: T(.overviewSubVeryHigh)),
                    SubStatistic(id: "high", value: "\(statistics.high)", caption: T(.overviewSubHigh)),
                    SubStatistic(id: "medium", value: "\(statistics.mediumAndBelow)", caption: T(.overviewSubMediumAndBelow)),
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
            VStack(alignment: .leading, spacing: SentinelMetrics.cardContentSpacing) {
                HStack(spacing: 8) {
                    CardLabel(text: T(.overviewRecentEvents))
                    Spacer(minLength: 8)
                    SegmentedPills(
                        options: PanelEventFilter.allCases.map {
                            SegmentedPills<PanelEventFilter>.Option(value: $0, title: $0.title)
                        },
                        selection: eventFilter,
                        onSelect: { eventFilter = $0 },
                        accessibilityLabel: T(.overviewEventFilter)
                    )
                }

                if events.isEmpty {
                    Text(T(.overviewNoEvents))
                        .font(.system(size: SentinelMetrics.hintFontSize))
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
                .frame(width: SentinelMetrics.severityColumnWidth, alignment: .leading)

            Text(event.event.displayName)
                .font(.system(size: SentinelMetrics.bodyFontSize))
                .lineLimit(1)
                .frame(width: AppText.language == .english ? SentinelMetrics.eventNameColumnWidthEnglish : SentinelMetrics.eventNameColumnWidth, alignment: .leading)

            Text(LogDescription.text(for: event))
                .font(.system(size: SentinelMetrics.bodyFontSize))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            LogTimestampColumns(date: event.timestamp)
        }
        .padding(SentinelMetrics.listRowPadding)
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
        case .online: return T(.overviewStateOnline)
        case .offline: return T(.overviewStateDown)
        case .standby: return T(.overviewStateStandby)
        case .disabled: return T(.overviewStateDisabled)
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
        let severity = event.severity?.displayName ?? T(.commonUnknownSeverity)
        let separator = T(.commonListSeparator)
        let description = LogDescription.text(for: event)
        return "\(severity)\(separator)\(event.event.displayName)\(separator)"
            + "\(description)\(separator)\(LogTimestampText.stamp(event.timestamp))"
    }

    /// The line hint under the big state: how long a line has been down, blank
    /// while it is up.
    private static func hint(for line: WANLineStatus, now: Date) -> String {
        // The big state already says 「在线」; the hint line stays (blank) so
        // the cards keep their height.
        line.state == .online ? " " : line.detailText(now: now)
    }
}

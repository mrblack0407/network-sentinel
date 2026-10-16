import AppKit
import SentinelCore
import SwiftUI
import UniformTypeIdentifiers

/// 日志: the monitored local log with the 时间, 类型 and 严重性 filters, a
/// paged table and the CSV export.
///
/// The table shows the same Chinese text the notifications use, and the entries
/// themselves are the ones `MonitorService` published: the page never queries the
/// gateway itself.
struct LogsView: View {
    /// The monitoring engine: the local log comes from it.
    @ObservedObject var monitor: MonitorService

    // The three filters, with the defaults of the mockup.
    @State private var timeRange: LogTimeRange = .day7
    @State private var category: LogCategory = .all
    @State private var minimumSeverity: LogSeverity = .low
    @State private var currentPage = 1
    @State private var exportErrorMessage: String?

    /// Rows of one page.
    private static let pageSize = LogPagination.defaultPageSize
    /// Widths of the fixed columns, so the header and the rows line up.
    private static let severityWidth = SentinelMetrics.logsSeverityColumnWidth
    private static let eventNameWidth = SentinelMetrics.logsEventNameColumnWidth

    var body: some View {
        // The 时间 filter counts from 「现在」, so the table follows the clock
        // even while no new entry arrives.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(now: context.date)
        }
    }

    private func content(now: Date) -> some View {
        let filter = LogFilter(
            timeRange: timeRange,
            category: category,
            minimumSeverity: minimumSeverity
        )
        let entries = filter.apply(to: monitor.events, now: now)
        let pagination = LogPagination(
            totalCount: entries.count,
            pageSize: Self.pageSize,
            currentPage: currentPage
        )

        return ScrollView {
            VStack(alignment: .leading, spacing: SentinelMetrics.contentSpacing) {
                header(entries)
                table(pagination.page(of: entries))
                pager(pagination)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // A changed filter always starts at the first page.
        .onChange(of: timeRange) { _ in currentPage = 1 }
        .onChange(of: category) { _ in currentPage = 1 }
        .onChange(of: minimumSeverity) { _ in currentPage = 1 }
        .alert(
            "导出失败",
            isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: { if !$0 { exportErrorMessage = nil } }
            ),
            presenting: exportErrorMessage
        ) { _ in
            Button("好", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    // MARK: - Title and tools

    private func header(_ entries: [MonitoredLogEvent]) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 10) {
                titleLabel
                Spacer(minLength: 12)
                tools(entries)
            }
            VStack(alignment: .leading, spacing: 8) {
                titleLabel
                tools(entries)
            }
        }
    }

    private var titleLabel: some View {
        Text("日志")
            .font(.system(size: SentinelMetrics.pageTitleFontSize, weight: .bold))
            .tracking(SentinelMetrics.pageTitleTracking)
            .accessibilityAddTraits(.isHeader)
    }

    private func tools(_ entries: [MonitoredLogEvent]) -> some View {
        HStack(alignment: .center, spacing: 8) {
            SegmentedPills(
                options: LogTimeRange.allCases.map {
                    SegmentedPills<LogTimeRange>.Option(value: $0, title: $0.title)
                },
                selection: timeRange,
                onSelect: { timeRange = $0 },
                accessibilityLabel: "时间范围"
            )

            SegmentedPills(
                options: LogCategory.allCases.map {
                    SegmentedPills<LogCategory>.Option(value: $0, title: $0.title)
                },
                selection: category,
                onSelect: { category = $0 },
                accessibilityLabel: "事件类型"
            )

            SegmentedPills(
                options: LogSeverity.allCases.map {
                    SegmentedPills<LogSeverity>.Option(value: $0, title: $0.displayName)
                },
                selection: minimumSeverity,
                onSelect: { minimumSeverity = $0 },
                accessibilityLabel: "严重性"
            )

            ToolbarButton(title: "导出 CSV", accessibilityLabel: "导出 CSV") {
                export(entries)
            }
        }
    }

    // MARK: - Table

    private func table(_ rows: [MonitoredLogEvent]) -> some View {
        SentinelCard(fillsHeight: false, padding: SentinelMetrics.tableCardPadding) {
            VStack(alignment: .leading, spacing: 0) {
                tableHeader

                Divider()

                if rows.isEmpty {
                    emptyMessage
                } else {
                    // The card hugs its rows, as in the mockup; the page scrolls.
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, event in
                            if index > 0 {
                                Divider()
                            }
                            tableRow(event)
                        }
                    }
                }
            }
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 12) {
            Text("严重性")
                .frame(width: Self.severityWidth, alignment: .leading)
            Text("事件")
                .frame(width: Self.eventNameWidth, alignment: .leading)
            Text("描述")
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {
                Text("日期")
                    .frame(width: SentinelMetrics.dateColumnWidth, alignment: .trailing)
                Text("时间")
                    .frame(width: SentinelMetrics.timeColumnWidth, alignment: .trailing)
            }
        }
        .font(.system(size: SentinelMetrics.tableHeaderFontSize, weight: .semibold))
        .tracking(SentinelMetrics.tableHeaderTracking)
        .foregroundStyle(.secondary)
        .padding(SentinelMetrics.tableRowPadding)
    }

    private var emptyMessage: some View {
        Text("这段时间没有符合条件的日志")
            .font(.system(size: SentinelMetrics.bodyFontSize))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .accessibilityLabel("这段时间没有符合条件的日志")
    }

    private func tableRow(_ event: MonitoredLogEvent) -> some View {
        HStack(spacing: 12) {
            SeverityBar(severity: event.severity)
                .frame(width: Self.severityWidth, alignment: .leading)

            Text(event.event.displayName)
                .font(.system(size: SentinelMetrics.tableFontSize))
                .lineLimit(1)
                .frame(width: Self.eventNameWidth, alignment: .leading)

            Text(LogDescription.text(for: event))
                .font(.system(size: SentinelMetrics.tableFontSize))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            LogTimestampColumns(date: event.timestamp)
        }
        .padding(SentinelMetrics.tableRowPadding)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.readOut(of: event))
    }

    // MARK: - Pager

    private func pager(_ pagination: LogPagination) -> some View {
        HStack(spacing: 10) {
            Text(pagination.rangeText)
                .font(.system(size: SentinelMetrics.hintFontSize, design: .monospaced))
                .foregroundStyle(.secondary)
                .accessibilityLabel(pagination.rangeText)

            Spacer(minLength: 12)

            HStack(spacing: 4) {
                PagerButton(
                    title: "‹",
                    isCurrent: false,
                    isEnabled: pagination.currentPage > 1,
                    accessibilityLabel: "上一页"
                ) {
                    currentPage = max(1, pagination.currentPage - 1)
                }

                ForEach(pagination.pageItems) { item in
                    switch item {
                    case .page(let number):
                        PagerButton(
                            title: "\(number)",
                            isCurrent: number == pagination.currentPage,
                            isEnabled: true,
                            accessibilityLabel: "第 \(number) 页"
                        ) {
                            currentPage = number
                        }
                    case .ellipsis:
                        Text("…")
                            .font(.system(size: SentinelMetrics.hintFontSize))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 12)
                            .accessibilityHidden(true)
                    }
                }

                PagerButton(
                    title: "›",
                    isCurrent: false,
                    isEnabled: pagination.currentPage < pagination.pageCount,
                    accessibilityLabel: "下一页"
                ) {
                    currentPage = min(pagination.pageCount, pagination.currentPage + 1)
                }
            }
        }
    }

    // MARK: - CSV export

    /// Asks for a file and writes every entry of the current filter, not only
    /// the rows of the page that is on screen.
    private func export(_ entries: [MonitoredLogEvent]) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = LogCSVExporter.defaultFileName()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try LogCSVExporter.data(events: entries).write(to: url, options: .atomic)
        } catch {
            exportErrorMessage = "无法写入 \(url.lastPathComponent)：\(error.localizedDescription)"
        }
    }

    // MARK: - Texts

    /// One entry in one sentence, for a screen reader.
    private static func readOut(of event: MonitoredLogEvent) -> String {
        let severity = event.severity?.displayName ?? "严重性未知"
        let line = event.wanID.map { "\($0)，" } ?? ""
        let description = LogDescription.text(for: event)
        return "\(severity)，\(event.event.displayName)，\(line)\(description)，\(LogTimestampText.stamp(event.timestamp))"
    }
}

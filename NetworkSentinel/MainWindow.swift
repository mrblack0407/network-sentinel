import AppKit
import SentinelCore
import SwiftUI

/// 主窗口: the sidebar of 「概览」「全部日志」「通知」「设置」 and the page it selects.
struct MainWindow: View {
    @ObservedObject var configuration: AppConfiguration
    /// The monitoring engine, for the status line of 设置 and the 线路标签.
    @ObservedObject var monitor: MonitorService
    /// The selected page, owned by `WindowCoordinator` so 「设置…」 of the
    /// 菜单栏弹出面板 can switch the page of a window that is already open.
    @ObservedObject var windowState: MainWindowState

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $windowState.selection)
                .frame(width: SentinelMetrics.sidebarWidth)

            // The 线路标签 and the page share one padded column, the `.main` of
            // the mockup: the page itself carries no padding.
            VStack(alignment: .leading, spacing: SentinelMetrics.contentSpacing) {
                WANStatusChips(configuration: configuration, monitor: monitor)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                page
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(SentinelMetrics.contentPadding)
        }
        .frame(
            minWidth: WindowCoordinator.mainWindowMinimumSize.width,
            minHeight: WindowCoordinator.mainWindowMinimumSize.height
        )
    }

    @ViewBuilder
    private var page: some View {
        switch windowState.selection {
        case .overview:
            OverviewView(configuration: configuration, monitor: monitor, windowState: windowState)
        case .logs:
            LogsView(monitor: monitor)
        case .notifications:
            NotificationsPage(configuration: configuration)
        case .settings:
            SettingsPage(configuration: configuration, monitor: monitor)
        }
    }
}

/// The page the 主窗口 shows.
///
/// The 主窗口 keeps no selection of its own, so 「设置…」 of the 菜单栏弹出面板
/// can open a window that is already up on 设置.
@MainActor
final class MainWindowState: ObservableObject {
    @Published var selection: SidebarItem = .overview
}

/// 线路标签: one small chip per WAN line, at the top right of the 主窗口.
struct WANStatusChips: View {
    @ObservedObject var configuration: AppConfiguration
    @ObservedObject var monitor: MonitorService

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

        HStack(spacing: 8) {
            if status.isGatewayUnreachable {
                // Without the gateway the line states of the last query would be
                // a guess, so the chips say why they are missing.
                StatusChip(tone: .neutral, text: "网关连不上", accessibilityLabel: "网关连不上")
            } else {
                ForEach(status.lines) { line in
                    StatusChip(
                        tone: line.state.tone,
                        text: line.chipText,
                        accessibilityLabel: line.accessibilityText(now: now)
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// One row of the sidebar.
enum SidebarItem: String, CaseIterable, Identifiable {
    case overview
    case logs
    case notifications
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "概览"
        case .logs: return "全部日志"
        case .notifications: return "通知"
        case .settings: return "设置"
        }
    }

    var symbolName: String {
        switch self {
        case .overview: return "chart.line.uptrend.xyaxis"
        case .logs: return "list.bullet.rectangle"
        case .notifications: return "bell"
        case .settings: return "slider.horizontal.3"
        }
    }
}

/// The sidebar: the pages, the 「配置」 group and the GitHub row at the bottom.
struct SidebarView: View {
    @Binding var selection: SidebarItem

    /// Pages above the 「配置」 group title.
    private static let mainPages: [SidebarItem] = [.overview, .logs]
    /// Pages under the 「配置」 group title.
    private static let configuredPages: [SidebarItem] = [.notifications, .settings]

    var body: some View {
        VStack(alignment: .leading, spacing: SentinelMetrics.sidebarSpacing) {
            ForEach(Self.mainPages) { item in
                SidebarRow(item: item, isSelected: selection == item) { selection = item }
            }

            Text("配置")
                .font(.system(size: SentinelMetrics.sidebarSectionFontSize))
                .foregroundStyle(.secondary)
                .padding(SentinelMetrics.sidebarSectionPadding)
                .accessibilityAddTraits(.isHeader)

            ForEach(Self.configuredPages) { item in
                SidebarRow(item: item, isSelected: selection == item) { selection = item }
            }

            Spacer(minLength: 12)

            GitHubRow()
        }
        .padding(SentinelMetrics.sidebarPadding)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial)
    }
}

/// One sidebar row (`.si`): icon and title, with a light gray block while selected.
struct SidebarRow: View {
    let item: SidebarItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SentinelMetrics.sidebarRowSpacing) {
                Image(systemName: item.symbolName)
                    .font(.system(size: SentinelMetrics.bodyFontSize))
                    .frame(width: SentinelMetrics.sidebarIconSize, height: SentinelMetrics.sidebarIconSize)
                Text(item.title)
                    .font(.system(size: SentinelMetrics.bodyFontSize, weight: .medium))
                Spacer(minLength: 0)
            }
            .padding(SentinelMetrics.sidebarRowPadding)
            .background(
                RoundedRectangle(cornerRadius: SentinelMetrics.sidebarRowCornerRadius)
                    .fill(isSelected ? SentinelColor.selection : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// The GitHub row at the bottom of the sidebar (`.ghub`): 项目名 and version.
struct GitHubRow: View {
    /// `.ghub:hover` shows a light gray block behind the row.
    @State private var isHovering = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(AppInfo.repositoryURL)
        } label: {
            HStack(spacing: SentinelMetrics.githubRowSpacing) {
                Image("GitHubMark")
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: SentinelMetrics.githubIconSize, height: SentinelMetrics.githubIconSize)
                    .foregroundStyle(isHovering ? Color.primary : Color.secondary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Network Sentinel")
                        .font(.system(size: SentinelMetrics.githubNameFontSize, weight: .semibold))
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text("for UniFi")
                        Spacer(minLength: 8)
                        Text("v\(AppInfo.marketingVersion)")
                    }
                    .font(.system(size: SentinelMetrics.githubDetailFontSize, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SentinelMetrics.githubRowPadding)
            .background(
                RoundedRectangle(cornerRadius: SentinelMetrics.githubRowCornerRadius)
                    .fill(isHovering ? SentinelColor.selection : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("在 GitHub 上查看源代码")
        .accessibilityLabel("在 GitHub 上查看源代码")
    }
}

import AppKit
import SwiftUI

/// 主窗口: the sidebar of 「概览」「全部日志」「设置」 and the page it selects.
struct MainWindow: View {
    @ObservedObject var configuration: AppConfiguration

    @State private var selection: SidebarItem = .overview

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $selection)
                .frame(width: 200)

            page
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(
            minWidth: WindowCoordinator.mainWindowMinimumSize.width,
            minHeight: WindowCoordinator.mainWindowMinimumSize.height
        )
    }

    @ViewBuilder
    private var page: some View {
        switch selection {
        case .overview:
            PlaceholderPage(title: "概览")
        case .logs:
            PlaceholderPage(title: "全部日志")
        case .settings:
            SettingsPage(configuration: configuration)
        }
    }
}

/// One row of the sidebar.
enum SidebarItem: String, CaseIterable, Identifiable {
    case overview
    case logs
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "概览"
        case .logs: return "全部日志"
        case .settings: return "设置"
        }
    }

    var symbolName: String {
        switch self {
        case .overview: return "chart.line.uptrend.xyaxis"
        case .logs: return "list.bullet.rectangle"
        case .settings: return "slider.horizontal.3"
        }
    }
}

/// The sidebar: the pages, the 「配置」 group and the GitHub row at the bottom.
struct SidebarView: View {
    @Binding var selection: SidebarItem

    /// Pages above the 「配置」 group title.
    private static let mainPages: [SidebarItem] = [.overview, .logs]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Self.mainPages) { item in
                SidebarRow(item: item, isSelected: selection == item) { selection = item }
            }

            Text("配置")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 14)
                .padding(.bottom, 2)
                .accessibilityAddTraits(.isHeader)

            SidebarRow(item: .settings, isSelected: selection == .settings) { selection = .settings }

            Spacer(minLength: 12)

            GitHubRow()
        }
        .padding(EdgeInsets(top: 14, leading: 10, bottom: 14, trailing: 10))
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial)
    }
}

/// One sidebar row: icon and title, with a light gray block while selected.
struct SidebarRow: View {
    let item: SidebarItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: item.symbolName)
                    .font(.system(size: 13))
                    .frame(width: 16, height: 16)
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? SentinelColor.selection : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// The GitHub row at the bottom of the sidebar: 项目名 and version.
struct GitHubRow: View {
    var body: some View {
        Button {
            NSWorkspace.shared.open(AppInfo.repositoryURL)
        } label: {
            HStack(spacing: 10) {
                Image("GitHubMark")
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 26, height: 26)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Network Sentinel")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text("for UniFi")
                        Spacer(minLength: 8)
                        Text("v\(AppInfo.marketingVersion)")
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("在 GitHub 上查看源代码")
        .accessibilityLabel("在 GitHub 上查看源代码")
    }
}

/// A page that is not built yet. 概览 and 全部日志 arrive in step 5.
struct PlaceholderPage: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            Text("第 5 步做")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 16, leading: 22, bottom: 24, trailing: 22))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

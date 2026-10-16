import AppKit
import SwiftUI

/// 菜单栏弹出面板: the gateway name, 「打开主窗口」 and 「退出」.
///
/// Step 4 adds the WAN lines and the recent log entries.
struct MenuBarPanel: View {
    @ObservedObject var state: AppState
    @ObservedObject var configuration: AppConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(configuration.gatewayName ?? "Network Sentinel")
                .font(.headline)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)

            Divider()

            Button {
                state.windows.showMainWindow()
            } label: {
                Text("打开主窗口")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .accessibilityLabel("打开主窗口")

            Button {
                NSApp.terminate(nil)
            } label: {
                Text("退出")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .keyboardShortcut("q")
            .accessibilityLabel("退出 Network Sentinel")
        }
        .padding(16)
        .frame(width: 260, alignment: .leading)
    }
}

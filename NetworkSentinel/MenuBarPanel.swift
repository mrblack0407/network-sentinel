import AppKit
import SwiftUI

/// Placeholder content for the menu bar panel.
///
/// Later steps replace this with connection status, recent events and settings.
struct MenuBarPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Network Sentinel")
                .font(.headline)

            Text("for UniFi  v\(Self.marketingVersion)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(16)
        .frame(width: 260, alignment: .leading)
    }

    /// `CFBundleShortVersionString`, so the panel never shows a hand-written version.
    private static var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
    }
}

import SwiftUI

@main
struct NetworkSentinelApp: App {
    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel()
        } label: {
            Image("MenuBarIcon")
                .accessibilityLabel("Network Sentinel")
        }
        .menuBarExtraStyle(.window)
    }
}

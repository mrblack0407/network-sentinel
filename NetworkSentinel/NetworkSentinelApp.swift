import SwiftUI

/// Network Sentinel: a menu bar app for UniFi.
///
/// The only scene is the menu bar icon; the 首次启动窗口 and the 主窗口 are
/// AppKit windows created by `WindowCoordinator`. The icon is inserted as soon
/// as the app is configured, so an unconfigured app shows the 首次启动窗口 alone.
@main
struct NetworkSentinelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var state: AppState

    init() {
        let state = AppState(configuration: AppConfiguration())
        _state = StateObject(wrappedValue: state)
        AppDelegate.appState = state
    }

    var body: some Scene {
        MenuBarExtra(isInserted: $state.showsMenuBarIcon) {
            MenuBarPanel(state: state, configuration: state.configuration)
        } label: {
            Image("MenuBarIcon")
                .accessibilityLabel("Network Sentinel")
        }
        .menuBarExtraStyle(.window)
    }
}

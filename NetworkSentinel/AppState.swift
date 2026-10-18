import AppKit
import Combine
import SwiftUI

/// Window state of the app.
///
/// The app is a menu bar app: `showsMenuBarIcon` drives `MenuBarExtra`, and the
/// windows are created by `WindowCoordinator` only when they are wanted. A
/// configured app therefore starts with the menu bar icon alone.
@MainActor
final class AppState: ObservableObject {
    /// Stored settings of the app.
    let configuration: AppConfiguration
    /// The two windows of the app.
    let windows: WindowCoordinator
    /// The monitoring engine: it queries the gateway while the app runs.
    let monitor: MonitorService
    /// The update check: asks GitHub for a newer version while its switch is on.
    let updateChecker: UpdateChecker

    /// `true` while the menu bar icon is inserted.
    @Published var showsMenuBarIcon: Bool

    init(configuration: AppConfiguration, monitor injectedMonitor: MonitorService? = nil) {
        self.configuration = configuration
        configuration.appearance.apply()
        // An unconfigured app shows the 首次启动窗口 only: no menu bar icon.
        self.showsMenuBarIcon = configuration.isConfigured
        let monitor = injectedMonitor ?? MonitorService(configuration: configuration)
        self.monitor = monitor
        let updateChecker = UpdateChecker(configuration: configuration)
        self.updateChecker = updateChecker
        self.windows = WindowCoordinator(
            configuration: configuration,
            monitor: monitor,
            updateChecker: updateChecker
        )
        windows.state = self
        // A notification tap opens the 主窗口.
        monitor.windows = windows

        if injectedMonitor != nil {
            // The debug snapshot renderer drives an injected engine itself and
            // must not ask GitHub for a version.
        } else {
            updateChecker.start()
            if configuration.isConfigured {
                // A configured app starts monitoring right away.
                monitor.start()
            } else {
                // `AppDelegate` shows the 首次启动窗口 as well. The two paths cover the
                // order of the launch sequence; showing the window twice is harmless
                // because the second call only brings it to the front.
                DispatchQueue.main.async { [weak self] in
                    self?.windows.showFirstLaunchWindow()
                }
            }
        }
    }

    /// The user finished the 首次启动窗口: the menu bar icon appears, the
    /// 主窗口 opens on 「概览」 and the engine starts.
    func finishFirstLaunch() {
        showsMenuBarIcon = true
        windows.showMainWindow()
        monitor.start()
    }
}

/// App delegate of Network Sentinel.
///
/// The app has no Dock icon and no menus of its own until a window opens, so the
/// delegate decides which window the app starts with and gives the app its own
/// main menu (`MainMenu`).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Window state, set by `NetworkSentinelApp` at launch.
    static weak var appState: AppState?

    /// The language subscription: the main menu follows 界面 → 语言.
    private var languageSubscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let state = Self.appState else { return }

        // The only SwiftUI scene is the menu bar icon, so the app builds its own
        // main menu instead of waiting for SwiftUI to write one.
        MainMenu.shared.windows = state.windows
        MainMenu.shared.install()
        // SwiftUI writes the default menu while the app finishes launching, so
        // the app's menus go in once more after that.
        DispatchQueue.main.async {
            MainMenu.shared.install()
        }
        // `language` publishes before its `didSet` applies the new language, so
        // the rebuild waits for the next turn of the main run loop.
        languageSubscription = state.configuration.$language
            .dropFirst()
            .sink { _ in
                Task { @MainActor in
                    MainMenu.shared.install()
                }
            }

        // A configured app is a menu bar app: it starts with the icon alone,
        // opens the 主窗口 only on 「打开主窗口」 and queries in the background.
        guard !state.configuration.isConfigured else { return }
        state.windows.showFirstLaunchWindow()
    }

    /// 退出: the engine stops before the process goes away.
    /// A click on the Dock icon while no window is open brings the 主窗口 back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard let state = Self.appState, state.configuration.isConfigured, !flag else { return true }
        state.windows.showMainWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        Self.appState?.monitor.stop()
    }
}

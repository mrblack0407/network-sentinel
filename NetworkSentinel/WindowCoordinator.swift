import AppKit
import SwiftUI

/// Creates and shows the two windows of the app.
///
/// Network Sentinel is an `LSUIElement` app whose only SwiftUI scene is the menu
/// bar icon. SwiftUI does not open a `Window` scene at launch when the first
/// scene is a `MenuBarExtra`, so both windows are `NSWindow`s here, each hosting
/// the SwiftUI view that draws its content.
@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    /// Size of the 首次启动窗口.
    static let firstLaunchSize = NSSize(width: 520, height: 440)
    /// Smallest content size of the 主窗口.
    static let mainWindowMinimumSize = NSSize(width: 900, height: 600)
    /// Content size the 主窗口 opens with.
    static let mainWindowSize = NSSize(width: 1040, height: 700)

    /// Settings of the app, used by the content of both windows.
    let configuration: AppConfiguration
    /// The monitoring engine of the app, used by 设置.
    let monitor: MonitorService
    /// Window state of the app; weak, because the app state owns this object.
    weak var state: AppState?

    /// The 首次启动窗口, while it is up.
    private var firstLaunchWindow: NSWindow?
    /// The 主窗口, kept for the next 「打开主窗口」 after the user closed it.
    private var mainWindow: NSWindow?
    /// `true` once 「开始使用」 ran: closing that window then keeps the app alive.
    private var isFirstLaunchFinished = false

    init(configuration: AppConfiguration, monitor: MonitorService) {
        self.configuration = configuration
        self.monitor = monitor
        super.init()
    }

    // MARK: - 首次启动窗口

    /// Shows the 首次启动窗口: fixed at 520 × 440, and the window the app starts with.
    ///
    /// Closing this window quits the app: without a UniFi gateway the app cannot
    /// monitor anything, so there is nothing to keep running.
    func showFirstLaunchWindow() {
        if let firstLaunchWindow {
            bringToFront(firstLaunchWindow)
            return
        }

        let window = makeWindow(
            content: FirstLaunchWindow(configuration: configuration) { [weak self] in
                self?.completeFirstLaunch()
            },
            contentSize: Self.firstLaunchSize,
            minimumContentSize: Self.firstLaunchSize,
            isFixedSize: true
        )
        firstLaunchWindow = window
        bringToFront(window)
    }

    /// 「开始使用」: the app is configured now, so the 首次启动窗口 closes without
    /// quitting, the menu bar icon appears and the 主窗口 opens.
    private func completeFirstLaunch() {
        // The close is deferred: the button that asked for it lives in the view
        // hierarchy of that very window, so it has to finish first.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isFirstLaunchFinished = true
            self.firstLaunchWindow?.close()
            self.firstLaunchWindow = nil
            self.state?.finishFirstLaunch()
        }
    }

    // MARK: - 主窗口

    /// Shows the 主窗口, creating it the first time.
    ///
    /// Closing the 主窗口 does not quit the app; the next call reuses the window.
    func showMainWindow() {
        if mainWindow == nil {
            mainWindow = makeWindow(
                content: MainWindow(configuration: configuration, monitor: monitor),
                contentSize: Self.mainWindowSize,
                minimumContentSize: Self.mainWindowMinimumSize,
                isFixedSize: false
            )
        }
        if let mainWindow {
            bringToFront(mainWindow)
        }
    }

    /// `true` while the 主窗口 is on screen. For the later steps.
    var isMainWindowVisible: Bool {
        mainWindow?.isVisible ?? false
    }

    // MARK: - NSWindowDelegate

    /// Closing the 首次启动窗口 quits the app; closing the 主窗口 does not.
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === firstLaunchWindow else { return }

        firstLaunchWindow = nil
        guard !isFirstLaunchFinished else { return }
        NSApp.terminate(nil)
    }

    // MARK: - Pieces

    private func makeWindow<Content: View>(
        content: Content,
        contentSize: NSSize,
        minimumContentSize: NSSize,
        isFixedSize: Bool
    ) -> NSWindow {
        let hosting = NSHostingController(rootView: content)
        // The window sets its own size below; the SwiftUI content only fills it.
        hosting.sizingOptions = []

        let window = SentinelWindow(contentViewController: hosting)
        window.title = "Network Sentinel"
        // The window stays alive after a close, so 「打开主窗口」 can reuse it.
        window.isReleasedWhenClosed = false
        // Two windows of one app are never meant to be tabs.
        window.tabbingMode = .disallowed
        window.delegate = self

        if isFixedSize {
            window.styleMask.remove(.resizable)
            window.contentMinSize = contentSize
            window.contentMaxSize = contentSize
        } else {
            window.styleMask.insert(.resizable)
            window.contentMinSize = minimumContentSize
            window.contentMaxSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
        }

        window.setContentSize(contentSize)
        window.center()
        return window
    }

    /// Brings a window to the front and makes it the key window.
    private func bringToFront(_ window: NSWindow) {
        // The app has no Dock icon, so it has to ask for the front itself.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        // The 首次启动窗口 is created while the app is still launching, and the
        // launch sequence can take the focus away again; ask once more.
        DispatchQueue.main.async {
            guard window.isVisible else { return }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }
}

/// A window of an `LSUIElement` app.
///
/// The app is an accessory, so AppKit does not hand it a key window by itself:
/// without this the text fields of the 首次启动窗口 would not accept typing.
final class SentinelWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

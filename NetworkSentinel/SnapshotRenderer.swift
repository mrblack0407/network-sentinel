#if DEBUG
import AppKit
import SentinelCore
import SwiftUI

/// Debug-only: renders the menu bar panel and every 主窗口 page to PNG files and
/// quits, so the UI can be compared with `Design/Mockups.html` without screen
/// recording. Run the app with the environment variable `NS_SNAPSHOT_DIR` set.
///
/// It never touches the keychain: the configuration uses an in-memory key store
/// and a separate defaults suite, and the engine is not started.
@MainActor
enum SnapshotRenderer {
    static func runIfRequested() -> Bool {
        guard let path = ProcessInfo.processInfo.environment["NS_SNAPSHOT_DIR"] else { return false }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let withWAN2 = ProcessInfo.processInfo.environment["NS_SNAPSHOT_WAN2"] == "1"
        let appearance = NSAppearance(named: ProcessInfo.processInfo.environment["NS_SNAPSHOT_LIGHT"] == "1" ? .aqua : .darkAqua)

        let defaults = UserDefaults(suiteName: "NetworkSentinel.snapshot")!
        defaults.removePersistentDomain(forName: "NetworkSentinel.snapshot")
        let configuration = AppConfiguration(defaults: defaults, keyStore: APIKeyStoreInMemory())
        if let address = try? GatewayAddress("192.168.8.254"),
           let site = try? JSONDecoder().decode(Site.self, from: Data(#"{"id":"s","internalReference":"default","name":"Default"}"#.utf8)) {
            let result = ConnectionTestResult(
                address: address,
                site: site,
                gatewayName: "Dream Machine Pro Max",
                certificate: PinnedCertificate(host: address.host, sha256: String(repeating: "0", count: 64))
            )
            try? configuration.saveConnection(result: result, apiKey: "snapshot")
        }

        // NS_SNAPSHOT_EMPTY=1 renders with an empty local log (empty states).
        let isEmpty = ProcessInfo.processInfo.environment["NS_SNAPSHOT_EMPTY"] == "1"
        let monitor = isEmpty
            ? MonitorService(configuration: configuration, sender: SilentSender(),
                             logStore: MonitorLogStore(directory: directory.appendingPathComponent("empty-store", isDirectory: true)))
            : MonitorService(configuration: configuration, sender: SilentSender())
        monitor.loadSnapshotState(gatewayStatus: gatewayStatus(withWAN2: withWAN2), now: Date())

        let state = AppState(configuration: configuration, monitor: monitor)
        render(MenuBarPanel(state: state, configuration: configuration, monitor: monitor),
               width: 480, appearance: appearance, to: directory.appendingPathComponent("popover.png"))

        for page in SidebarItem.allCases {
            let windowState = MainWindowState()
            windowState.selection = page
            let view = MainWindow(configuration: configuration, monitor: monitor, windowState: windowState)
            render(view, size: NSSize(width: 1180, height: 920),
                   appearance: appearance, to: directory.appendingPathComponent("main-\(page.rawValue).png"))
        }
        return true
    }

    private static func gatewayStatus(withWAN2: Bool) -> GatewayStatus? {
        let wan2 = withWAN2 ? #","wan2":{"up":true,"enable":true,"ip":"203.0.113.200","port_idx":9,"media":"GE","speed":1000}"# : ""
        let json = #"{"name":"Dream Machine Pro Max","model":"UDMPROMAX","version":"5.1.33","type":"udm","last_wan_status":{"WAN":"online"},"wan1":{"up":true,"enable":true,"ip":"203.0.113.1","port_idx":10,"media":"SFP+","speed":10000}"# + wan2 + "}"
        return (try? JSONDecoder().decode(GatewayDevice.self, from: Data(json.utf8)))?.status
    }

    private static func render<V: View>(_ view: V, width: CGFloat, appearance: NSAppearance?, to url: URL) {
        let host = NSHostingView(rootView: view.frame(width: width).background(backdrop(appearance)))
        host.appearance = appearance
        let size = host.fittingSize
        render(host: host, size: NSSize(width: width, height: size.height), to: url)
    }

    private static func render<V: View>(_ view: V, size: NSSize, appearance: NSAppearance?, to url: URL) {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height).background(backdrop(appearance)))
        host.appearance = appearance
        render(host: host, size: size, to: url)
    }

    /// The mockup's backdrop: dark plum for dark mode, light gray for light mode.
    private static func backdrop(_ appearance: NSAppearance?) -> Color {
        appearance?.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? Color(red: 0.13, green: 0.11, blue: 0.14)
            : Color(red: 0.93, green: 0.93, blue: 0.95)
    }

    private static func render(host: NSView, size: NSSize, to url: URL) {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = host.appearance
        window.backgroundColor = host.appearance?.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.09, green: 0.08, blue: 0.11, alpha: 1)
            : .windowBackgroundColor
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

private struct SilentSender: UserNotificationSending {
    func requestAuthorizationIfNeeded() async {}
    func send(title: String, body: String) async {}
}
#endif

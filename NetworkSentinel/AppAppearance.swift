import AppKit

/// The appearance setting of 设置 → 通用 → 外观.
enum AppAppearance: String, CaseIterable {
    /// Light or dark as macOS is set.
    case system
    case light
    case dark

    /// The `NSApp.appearance` for this setting; `nil` follows macOS.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    /// Applies the setting to every window of the app, the menu bar panel included.
    @MainActor
    func apply() {
        // `NSApp` is still nil while the app struct is created; `shared` is not.
        NSApplication.shared.appearance = nsAppearance
    }
}

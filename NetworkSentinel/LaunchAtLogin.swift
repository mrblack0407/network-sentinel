import ServiceManagement
import SwiftUI

/// 开机自启: registers and unregisters the app as a login item.
///
/// `SMAppService.mainApp` is the only supported way to do this on macOS 13; the
/// registration can fail (an unsigned build, or a copy of the app that the
/// system does not trust), and the failure text is what the settings page shows.
@MainActor
final class LaunchAtLogin: ObservableObject {
    /// `true` while the app is registered as a login item.
    @Published private(set) var isEnabled: Bool
    /// Why the last register or unregister failed.
    @Published private(set) var errorMessage: String?

    init() {
        isEnabled = Self.isRegistered()
        errorMessage = Self.approvalMessage()
    }

    /// Registers or unregisters the app. A failure leaves the switch where the
    /// system says it is, so the user sees the real state.
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }

        isEnabled = Self.isRegistered()
        if errorMessage == nil {
            errorMessage = Self.approvalMessage()
        }
    }

    private static func isRegistered() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// macOS asks the user to allow the login item the first time; until then
    /// the app is registered but not enabled.
    private static func approvalMessage() -> String? {
        SMAppService.mainApp.status == .requiresApproval
            ? "需要在「系统设置 → 通用 → 登录项」里允许 Network Sentinel"
            : nil
    }
}

import ServiceManagement
import SwiftUI

/// 开机自启: registers and unregisters the app as a login item.
///
/// `SMAppService.mainApp` is the only supported way to do this since macOS 13; the
/// registration can fail (an unsigned build, or a copy of the app that the
/// system does not trust), and the failure text is what the settings page shows.
@MainActor
final class LaunchAtLogin: ObservableObject {
    /// `true` while the app is registered as a login item.
    @Published private(set) var isEnabled: Bool
    /// Why the last register or unregister failed. The system's own text.
    @Published private(set) var errorMessage: String?
    /// `true` while macOS still waits for the user to allow the login item.
    ///
    /// Kept as a flag rather than as a text, so the card follows a language
    /// change without a new register attempt.
    @Published private(set) var requiresApproval: Bool

    init() {
        isEnabled = Self.isRegistered()
        errorMessage = nil
        requiresApproval = Self.needsApproval()
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
        requiresApproval = Self.needsApproval()
    }

    private static func isRegistered() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// macOS asks the user to allow the login item the first time; until then
    /// the app is registered but not enabled.
    private static func needsApproval() -> Bool {
        SMAppService.mainApp.status == .requiresApproval
    }
}

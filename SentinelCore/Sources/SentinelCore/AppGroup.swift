import Foundation

/// The App Group shared by the app and the future desktop widget.
///
/// The widget is deferred, but the group identifier and the status file live here
/// from the start so a widget can be added later without touching the app.
///
/// The entitlement is not declared yet: an App Group needs a signing team and a
/// provisioning profile, and the app is signed ad hoc for now. Add
/// `com.apple.security.application-groups` back when the widget is built.
public enum AppGroup {
    /// App Group identifier, to be declared in the app entitlements with the widget.
    public static let identifier = "group.com.mrblack0407.NetworkSentinel"

    /// The App Group container directory, or `nil` when the group is not available.
    ///
    /// Returns `nil` when the process has no entitlement for the group, for example
    /// in unit tests or when the app is not signed with the matching entitlements.
    ///
    /// On macOS `containerURL(forSecurityApplicationGroupIdentifier:)` returns a
    /// path even without the entitlement, and a sandboxed app then cannot write
    /// there. So the directory only counts when it exists or can be created.
    public static var containerURL: URL? {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            return nil
        }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        return FileManager.default.isWritableFile(atPath: url.path) ? url : nil
    }
}

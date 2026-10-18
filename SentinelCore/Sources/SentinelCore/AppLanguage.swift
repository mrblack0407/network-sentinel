import Foundation

/// The language setting of 界面 → 语言.
public enum AppLanguage: String, CaseIterable, Codable {
    /// Chinese when the Mac prefers Chinese, English otherwise.
    case system
    case chinese
    case english

    /// The language the app shows for this setting.
    ///
    /// - Parameter preferredLanguages: the Mac's languages, most preferred
    ///   first, as `Locale.preferredLanguages` gives them (`zh-Hans-CN`, `en-US`).
    public func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> ResolvedLanguage {
        switch self {
        case .chinese:
            return .chinese
        case .english:
            return .english
        case .system:
            let first = preferredLanguages.first?.lowercased() ?? ""
            return first.hasPrefix("zh") ? .chinese : .english
        }
    }
}

/// A language the app has texts for.
public enum ResolvedLanguage: String, Codable {
    case chinese
    case english
}

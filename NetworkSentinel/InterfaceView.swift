import AppKit
import SentinelCore
import SwiftUI

/// 界面: 语言 and 外观, one card each, saved on every change.
struct InterfacePage: View {
    @ObservedObject var configuration: AppConfiguration

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SentinelMetrics.contentSpacing) {
                Text(T(.pageInterface))
                    .font(.system(size: SentinelMetrics.pageTitleFontSize, weight: .bold))
                    .tracking(SentinelMetrics.pageTitleTracking)
                    .accessibilityAddTraits(.isHeader)

                GroupHeader(title: T(.interfaceGroup), color: SentinelColor.groupPink)
                LazyVGrid(columns: SettingsGridLayout.twoColumns, alignment: .leading, spacing: SentinelMetrics.cardSpacing) {
                    languageCard
                    appearanceCard
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var languageCard: some View {
        SettingsCard(
            title: T(.interfaceLanguage),
            description: T(.interfaceLanguageDescription),
            statusTone: .ok,
            statusText: T(
                .interfaceLanguageStatus,
                configuration.language.resolved() == .chinese
                    ? T(.interfaceLanguageChinese)
                    : T(.interfaceLanguageEnglish)
            ),
            control: SegmentedPills(
                options: [
                    .init(value: AppLanguage.system, title: T(.interfaceLanguageSystem)),
                    .init(value: AppLanguage.chinese, title: T(.interfaceLanguageChinese)),
                    .init(value: AppLanguage.english, title: T(.interfaceLanguageEnglish)),
                ],
                selection: configuration.language,
                onSelect: { configuration.language = $0 },
                accessibilityLabel: T(.interfaceLanguage)
            )
        )
    }

    private var appearanceCard: some View {
        SettingsCard(
            title: T(.interfaceAppearance),
            description: T(.interfaceAppearanceDescription),
            statusTone: .ok,
            statusText: Self.appearanceStatus(configuration.appearance),
            control: SegmentedPills(
                options: [
                    .init(value: AppAppearance.system, title: T(.interfaceAppearanceSystem)),
                    .init(value: AppAppearance.light, title: T(.interfaceAppearanceLight)),
                    .init(value: AppAppearance.dark, title: T(.interfaceAppearanceDark)),
                ],
                selection: configuration.appearance,
                onSelect: { configuration.appearance = $0 },
                accessibilityLabel: T(.interfaceAppearance)
            )
        )
    }

    private static func appearanceStatus(_ appearance: AppAppearance) -> String {
        switch appearance {
        case .light: return T(.interfaceAppearanceLightCurrent)
        case .dark: return T(.interfaceAppearanceDarkCurrent)
        case .system:
            let isDark = NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? T(.interfaceAppearanceDarkSystem) : T(.interfaceAppearanceLightSystem)
        }
    }
}

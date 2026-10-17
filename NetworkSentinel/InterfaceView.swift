import AppKit
import SentinelCore
import SwiftUI

/// 界面: 语言 and 外观, one card each with a pop-up menu, saved on every change.
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
            keepsControlBeside: true,
            control: Picker(T(.interfaceLanguage), selection: Binding(
                get: { configuration.language },
                set: { configuration.language = $0 }
            )) {
                Text(T(.interfaceLanguageSystem)).tag(AppLanguage.system)
                Text(T(.interfaceLanguageChinese)).tag(AppLanguage.chinese)
                Text(T(.interfaceLanguageEnglish)).tag(AppLanguage.english)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
        )
    }

    private var appearanceCard: some View {
        SettingsCard(
            title: T(.interfaceAppearance),
            description: T(.interfaceAppearanceDescription),
            statusTone: .ok,
            statusText: Self.appearanceStatus(configuration.appearance),
            keepsControlBeside: true,
            control: Picker(T(.interfaceAppearance), selection: Binding(
                get: { configuration.appearance },
                set: { configuration.appearance = $0 }
            )) {
                Text(T(.interfaceAppearanceSystem)).tag(AppAppearance.system)
                Text(T(.interfaceAppearanceLight)).tag(AppAppearance.light)
                Text(T(.interfaceAppearanceDark)).tag(AppAppearance.dark)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
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

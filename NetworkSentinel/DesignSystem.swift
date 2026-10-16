import SwiftUI

/// Version of the running app, read from the bundle so no number is written twice.
enum AppInfo {
    /// `CFBundleShortVersionString`, for example `0.1`.
    static var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
    }

    /// GitHub repository of the project.
    static let repositoryURL = URL(string: "https://github.com/mrblack0407/network-sentinel")!
}

/// Colors shared by the windows.
///
/// The severity colors come from the system palette, so the app follows the
/// light and dark appearance instead of forcing one. The group titles keep the
/// colors of `Design/Mockups.html` in both appearances.
enum SentinelColor {
    /// 监控中, 已连上.
    static let ok = Color(nsColor: .systemGreen)
    /// 未监控, a warning the user can act on.
    static let warn = Color(nsColor: .systemOrange)
    /// 测试连接 failed.
    static let failure = Color(nsColor: .systemRed)
    /// Nothing known yet, for example 还没测试连接.
    static let neutral = Color(nsColor: .secondaryLabelColor)

    /// 「UniFi 网关」 group title.
    static let groupGateway = Color(red: 0.835, green: 0.361, blue: 0.941)
    /// 「监控事件」 group title.
    static let groupEvents = Color(red: 0.557, green: 0.549, blue: 0.973)
    /// 「通知」 group title.
    static let groupNotifications = Color(red: 0.310, green: 0.639, blue: 1.000)
    /// 「通用」 group title.
    static let groupGeneral = Color(red: 0.310, green: 0.820, blue: 0.773)

    /// Hairline around a card or an input field.
    static let border = Color.primary.opacity(0.09)
    /// Background of a selected sidebar row: light gray, never the accent color.
    static let selection = Color.primary.opacity(0.09)
}

/// The meaning of one status dot.
enum StatusTone {
    case ok
    case warn
    case failure
    case neutral

    var color: Color {
        switch self {
        case .ok: return SentinelColor.ok
        case .warn: return SentinelColor.warn
        case .failure: return SentinelColor.failure
        case .neutral: return SentinelColor.neutral
        }
    }
}

/// A colored group title above a grid of cards.
struct GroupHeader: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(color)
            .padding(.top, 6)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One settings card: title and control on one line, description, status line.
///
/// The card uses a material background with a hairline border and a 20 pt
/// corner radius, like the mockup.
struct SettingsCard<Control: View, Accessory: View>: View {
    let title: String
    let description: String
    let statusTone: StatusTone
    let statusText: String
    let control: Control
    let accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // A narrow column stacks the control under the title, so the
            // segmented control is never squeezed.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    titleLabel
                    Spacer(minLength: 8)
                    control
                }
                VStack(alignment: .leading, spacing: 6) {
                    titleLabel
                    control
                }
            }

            Text(description)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack(spacing: 7) {
                Circle()
                    .fill(statusTone.color)
                    .frame(width: 7, height: 7)
                Text(statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                accessory
            }
            .padding(.top, 2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title)：\(statusText)")
        }
        .padding(EdgeInsets(top: 16, leading: 18, bottom: 14, trailing: 18))
        .frame(maxWidth: .infinity, minHeight: 128, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(SentinelColor.border, lineWidth: 1)
        )
    }

    /// Card title, shared by both layouts of the header.
    private var titleLabel: some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension SettingsCard where Accessory == EmptyView {
    init(title: String, description: String, statusTone: StatusTone, statusText: String, control: Control) {
        self.init(
            title: title,
            description: description,
            statusTone: statusTone,
            statusText: statusText,
            control: control,
            accessory: EmptyView()
        )
    }
}

/// Small segmented control: the selection is white on the accent color, the
/// other options are transparent on a faint track.
struct SegmentedPills<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let title: String
        var id: Value { value }
    }

    let options: [Option]
    let selection: Value
    let onSelect: (Value) -> Void
    let accessibilityLabel: String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let isSelected = option.value == selection
                Button {
                    onSelect(option.value)
                } label: {
                    Text(option.title)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isSelected ? Color.accentColor : Color.clear)
                        )
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(accessibilityLabel) \(option.title)")
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.06))
        )
    }
}

/// Grid columns of the settings page: three columns, two on a narrow window.
enum SettingsGridLayout {
    /// Width below which the cards drop to two columns.
    static let threeColumnMinimumWidth: CGFloat = 620

    static func columns(forWidth width: CGFloat) -> [GridItem] {
        let count = width >= threeColumnMinimumWidth ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 14), count: count)
    }
}

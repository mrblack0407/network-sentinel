import AppKit
import SentinelCore
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
    /// A bar of a severity bar the entry did not reach.
    static let severityOff = Color.primary.opacity(0.16)

    /// Color of one severity: 低 green, 中 yellow, 高 orange, 非常高 red.
    ///
    /// The colors come from the system palette, like the status colors above, so
    /// the bars follow the light and dark appearance.
    static func severity(_ severity: LogSeverity) -> Color {
        switch severity {
        case .low: return Color(nsColor: .systemGreen)
        case .medium: return Color(nsColor: .systemYellow)
        case .high: return Color(nsColor: .systemOrange)
        case .veryHigh: return Color(nsColor: .systemRed)
        }
    }
}

/// The meaning of the dot of the 菜单栏图标.
extension MenuBarIndicatorState {
    /// Color of the dot; `nil` while the icon shows the shield alone.
    ///
    /// Fixed colors: the dot never follows the appearance, only the shield does.
    var dotColor: NSColor? {
        switch self {
        case .quiet: return nil
        case .warning: return .systemYellow
        case .critical: return .systemRed
        case .disconnected: return .systemGray
        }
    }
}

/// The meaning of a WAN line, for the dots of the 菜单栏弹出面板 and the 主窗口.
extension SnapshotWANState {
    /// 在线 green, 已断开 red, 未启用 and 备用 gray.
    var tone: StatusTone {
        switch self {
        case .online: return .ok
        case .offline: return .failure
        case .disabled, .standby: return .neutral
        }
    }
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

/// A status dot with the soft halo of the mockup.
///
/// The halo is drawn behind the dot and grows outside its layout frame, so a row
/// of dots keeps the spacing the mockup shows.
struct GlowDot: View {
    let tone: StatusTone
    /// Diameter of the solid dot; the halo adds 8 pt around it.
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(tone.color)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(tone.color.opacity(0.22))
                    .frame(width: size + 8, height: size + 8)
            )
            .accessibilityHidden(true)
    }
}

/// The four small bars that show the severity of one log entry.
///
/// Every bar up to the rank of the entry is filled with the severity color, the
/// rest stay gray. A severity this version does not know fills no bar at all.
struct SeverityBar: View {
    /// `nil` when the gateway sent a severity this version does not know.
    let severity: LogSeverity?

    /// Bars of the mockup: 低 one, 中 two, 高 three, 非常高 four.
    private static let barCount = 4

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...Self.barCount, id: \.self) { rank in
                RoundedRectangle(cornerRadius: 1)
                    .fill(rank <= filledBars ? SentinelColor.severity(severity ?? .low) : SentinelColor.severityOff)
                    .frame(width: 7, height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("严重性：\(severity?.displayName ?? "未知")")
    }

    private var filledBars: Int { severity?.rank ?? 0 }
}

/// One 线路标签 of the 主窗口: a small dot and a short text.
struct StatusChip: View {
    let tone: StatusTone
    let text: String
    let accessibilityLabel: String

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(tone.color)
                .frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 12))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.primary.opacity(0.05)))
        .overlay(Capsule().stroke(SentinelColor.border, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }
}

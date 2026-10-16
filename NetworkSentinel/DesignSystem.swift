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

/// Date and time texts of a log entry, in the formats the app uses everywhere.
///
/// The 菜单栏弹出面板, 概览 and 全部日志 share these, so a row never shows two
/// different spellings of the same moment. All of them are in the local time
/// zone.
enum LogTimestampText {
    /// `10/16`.
    static func date(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    /// `9:44:20`.
    static func clock(_ date: Date) -> String {
        clockFormatter.string(from: date)
    }

    /// `10/16 9:44:20`.
    static func stamp(_ moment: Date) -> String {
        "\(date(moment)) \(clock(moment))"
    }

    /// `9:44`, for the tick labels of the 过去 24 小时 色条.
    static func shortClock(_ date: Date) -> String {
        shortClockFormatter.string(from: date)
    }

    /// `昨天 10:45`, the left tick of the 色条.
    static func yesterdayClock(_ date: Date) -> String {
        "昨天 \(shortClock(date))"
    }

    private static let dateFormatter = makeFormatter("M/d")
    private static let clockFormatter = makeFormatter("H:mm:ss")
    private static let shortClockFormatter = makeFormatter("H:mm")

    private static func makeFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = format
        return formatter
    }
}

/// The date and the time of one log entry in two right-aligned columns.
///
/// Two columns keep the rows of a list in line whatever the number of digits in
/// the month, the day or the hour.
struct LogTimestampColumns: View {
    let date: Date

    var body: some View {
        HStack(spacing: 4) {
            Text(LogTimestampText.date(date))
                .frame(width: 44, alignment: .trailing)
            Text(LogTimestampText.clock(date))
                .frame(width: 64, alignment: .trailing)
        }
        .font(.system(size: 12, design: .monospaced))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("时间 \(LogTimestampText.stamp(date))")
    }
}

/// A card of 概览 and 全部日志: material, hairline border and a 20 pt corner
/// radius, like the cards of 设置.
struct SentinelCard<Content: View>: View {
    /// `false` for a card that keeps its own height inside a scroll view.
    private let fillsHeight: Bool
    private let content: Content

    init(fillsHeight: Bool = true, @ViewBuilder content: () -> Content) {
        self.fillsHeight = fillsHeight
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
            .padding(EdgeInsets(top: 16, leading: 18, bottom: 14, trailing: 18))
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(SentinelColor.border, lineWidth: 1)
            )
    }
}

/// The small label at the top of a card, for example 「WAN1 · CHINA TELECOM」.
struct CardLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

/// The big state of a card: 在线, 断网中, 备用, 未启用 or a count.
struct BigStat: View {
    let text: String
    /// Small unit behind the number, for example 「条」.
    var unit: String?
    /// Color of the state; the counts keep the primary color.
    var color: Color = .primary

    init(text: String, unit: String? = nil, color: Color = .primary) {
        self.text = text
        self.unit = unit
        self.color = color
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(text)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(color)
            if let unit {
                Text(unit)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// One column of the three statistics at the bottom of a 概览 card.
struct SubStatistic: Identifiable {
    let id: String
    let value: String
    /// Small unit behind the value, for example 「次」.
    let unit: String?
    let caption: String

    init(id: String, value: String, unit: String? = nil, caption: String) {
        self.id = id
        self.value = value
        self.unit = unit
        self.caption = caption
    }
}

/// Three small statistics side by side, separated by hairlines.
struct SubStatistics: View {
    let items: [SubStatistic]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(items) { item in
                if item.id != items.first?.id {
                    Divider()
                }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(item.value)
                            .font(.system(size: 18, weight: .bold))
                            .monospacedDigit()
                        if let unit = item.unit {
                            Text(unit)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(item.caption)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, item.id == items.first?.id ? 0 : 10)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(item.caption) \(item.value)\(item.unit ?? "")")
            }
        }
        .padding(.top, 6)
    }
}

/// The 过去 24 小时 色条 of a 概览 线路卡片: 48 cells of half an hour.
///
/// 正常 is a short pale green bar, 临时中断 and 断网 are tall and colored, and
/// the last cell, 「现在」, is brighter.
struct OutageStripView: View {
    let strip: OutageStrip

    /// Height of the whole strip, so every cell aligns on one line.
    private static let stripHeight: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: 2) {
                ForEach(strip.cells) { cell in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(color(of: cell))
                        .frame(height: height(of: cell))
                        .shadow(color: glow(of: cell), radius: 4)
                }
            }
            .frame(height: Self.stripHeight)

            HStack(spacing: 0) {
                Text(LogTimestampText.yesterdayClock(strip.start))
                Spacer(minLength: 8)
                Text(LogTimestampText.shortClock(middleDate))
                Spacer(minLength: 8)
                Text("现在")
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(strip.accessibilityText)
    }

    /// Start of the middle cell, the 「HH:mm」 tick of the strip.
    private var middleDate: Date {
        let index = strip.cells.count / 2
        guard strip.cells.indices.contains(index) else { return strip.start }
        return strip.cells[index].start
    }

    /// 中断 red, 临时中断 yellow, 正常 pale green.
    private func color(of cell: OutageStripCell) -> Color {
        switch cell.state {
        case .normal:
            return SentinelColor.severity(.low).opacity(cell.isCurrent ? 1 : 0.45)
        case .temporary:
            return SentinelColor.severity(.medium)
        case .down:
            return SentinelColor.severity(.veryHigh)
        }
    }

    /// A problem cell is taller than a quiet one, 「现在」 a little taller again.
    private func height(of cell: OutageStripCell) -> CGFloat {
        guard cell.state == .normal else { return Self.stripHeight }
        return cell.isCurrent ? 16 : 12
    }

    /// The soft halo of a problem cell and of 「现在」.
    private func glow(of cell: OutageStripCell) -> Color {
        guard cell.state != .normal || cell.isCurrent else { return .clear }
        return color(of: cell).opacity(0.5)
    }
}

/// One page number of the pager of 全部日志: the current page is filled blue.
struct PagerButton: View {
    let title: String
    let isCurrent: Bool
    let isEnabled: Bool
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12))
                .monospacedDigit()
                .lineLimit(1)
                .frame(minWidth: 22)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isCurrent ? Color.accentColor : Color.clear)
                )
                .foregroundStyle(isCurrent ? Color.white : Color.primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    }
}

/// A small bordered button of a page toolbar, for example 「导出 CSV」.
struct ToolbarButton: View {
    let title: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(SentinelColor.border, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
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

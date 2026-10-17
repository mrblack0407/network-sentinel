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

/// Sizes of the 主窗口 and the 菜单栏弹出面板, taken from the CSS of
/// `Design/Mockups.html`.
///
/// One CSS pixel of the mockup is one point here, so a view and the mockup can
/// be compared without a scale factor. Every size of the interface lives here;
/// a view never writes a number of its own.
enum SentinelMetrics {
    // MARK: - Text

    /// Body text of a page (`.app`).
    static let bodyFontSize: CGFloat = 13
    /// Page title (`.mainhead h3`).
    static let pageTitleFontSize: CGFloat = 28
    /// Tracking of the page title (`letter-spacing: -.01em`).
    static let pageTitleTracking: CGFloat = -0.28
    /// Small statistics row: value (`.hstats b`).
    static let statisticValueFontSize: CGFloat = 15
    /// Small statistics row: label (`.hstats span`).
    static let statisticLabelFontSize: CGFloat = 12
    /// Colored group title (`.gh`).
    static let groupHeaderFontSize: CGFloat = 14
    /// Space above a group title (`.gh`, `padding-top`).
    static let groupHeaderTopPadding: CGFloat = 6

    // MARK: - Cards

    /// Title of a card (`.fch b`).
    static let cardTitleFontSize: CGFloat = 14
    /// Description of a settings card (`.fc p`).
    static let cardBodyFontSize: CGFloat = 12
    /// Small label at the top of a card (`.cl`).
    static let cardLabelFontSize: CGFloat = 11
    /// Letter spacing of that label (`.cl`, `letter-spacing: .04em`).
    static let cardLabelTracking: CGFloat = 0.44
    /// Big state of a card (`.big`).
    static let bigNumberFontSize: CGFloat = 30
    /// Unit behind the big state (`.big small`).
    static let bigNumberUnitFontSize: CGFloat = 13
    /// Number of the three small statistics (`.subs b`).
    static let subNumberFontSize: CGFloat = 18
    /// Caption of the three small statistics (`.subs span`).
    static let subCaptionFontSize: CGFloat = 11
    /// Muted line of a card (`.hint`).
    static let hintFontSize: CGFloat = 12
    /// Monospaced timestamp of a list row (`.lr em`, `.wan em`).
    static let timestampFontSize: CGFloat = 12
    /// Small footnote under an input field (`.fh`).
    static let footnoteFontSize: CGFloat = 11
    /// Text typed into an input field (`.inp`).
    static let inputFontSize: CGFloat = 13
    /// Title of the 连接设置窗口 (`.shh b`).
    static let sheetTitleFontSize: CGFloat = 17
    /// Title of a page of the 首次启动窗口 (`.wtitle b`).
    static let welcomeTitleFontSize: CGFloat = 20
    /// Description of a page of the 首次启动窗口 (`.wdesc`).
    static let welcomeBodyFontSize: CGFloat = 12.5

    /// Corner radius of a card (`.sc`, `.fc`).
    static let cardCornerRadius: CGFloat = 20
    /// Room for the traffic lights above the first sidebar row (`.side .lights`).
    static let trafficLightsInset: CGFloat = 28
    /// Space between two cards (`.cgrid`, `.fgrid`).
    static let cardSpacing: CGFloat = 14
    /// Space between the rows inside a card (`.sc` gap).
    static let cardContentSpacing: CGFloat = 11
    /// Padding of a card of 概览 and 日志 (`.sc`).
    static let cardPadding = EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18)
    /// Padding of a settings card (`.fc`, bottom is 14).
    static let settingsCardPadding = EdgeInsets(top: 16, leading: 18, bottom: 14, trailing: 18)
    /// Space between the rows of a settings card (`.fc` gap).
    static let settingsCardSpacing: CGFloat = 6
    /// Padding of the table card of 日志 (`.tbl`).
    static let tableCardPadding = EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
    /// The three small statistics (`.subs`), separated by hairlines.
    static let subStatisticsTopPadding: CGFloat = 6
    static let subStatisticsInnerPadding: CGFloat = 10

    // MARK: - Lists

    /// Corner radius of a grouped list (`.sc.tight`).
    static let tightGroupCornerRadius: CGFloat = 14
    /// Padding above and below the rows of a grouped list (`.sc.tight`).
    static let tightGroupVerticalPadding: CGFloat = 4
    /// Padding of one row of a grouped list (`.sc.tight .lr`).
    static let tightRowPadding = EdgeInsets(top: 9.5, leading: 12, bottom: 9.5, trailing: 12)
    /// Padding of one 最近事件 row (`.lr`).
    static let listRowPadding = EdgeInsets(top: 10.5, leading: 2, bottom: 10.5, trailing: 2)
    /// Padding of one row of the 日志 table (`.desk table td`).
    static let tableRowPadding = EdgeInsets(top: 11.5, leading: 10, bottom: 11.5, trailing: 10)
    /// Header of the 日志 table (`th`).
    static let tableHeaderFontSize: CGFloat = 12
    /// Letter spacing of that header (`th`, `letter-spacing: .04em`).
    static let tableHeaderTracking: CGFloat = 0.48
    /// Rows of the 日志 table (`.tbl table`).
    static let tableFontSize: CGFloat = 12.5
    /// Width of the 严重性 column of a list row (`.lr` first column).
    static let severityColumnWidth: CGFloat = 34
    /// Width of the 事件 column of a 最近事件 row (`.lr` second column).
    static let eventNameColumnWidth: CGFloat = 120
    /// Width of the 严重性 column of the 日志 table.
    static let logsSeverityColumnWidth: CGFloat = 90
    /// Width of the 事件 column of the 日志 table.
    static let logsEventNameColumnWidth: CGFloat = 190
    /// Width of the 日期 and 时间 columns of a row.
    static let dateColumnWidth: CGFloat = 44
    static let timeColumnWidth: CGFloat = 64

    // MARK: - 过去 24 小时 色条

    /// Cell size and spacing of the 色条 (`.strip`).
    static let stripHeight: CGFloat = 22
    static let stripQuietHeight: CGFloat = 12
    static let stripCurrentHeight: CGFloat = 16
    static let stripCellSpacing: CGFloat = 2
    static let stripCornerRadius: CGFloat = 2
    /// Tick labels of the 色条 (`.stripx`).
    static let stripTickFontSize: CGFloat = 10

    // MARK: - Small controls

    /// Chip (`.chip`): 30 秒查一次, 线路标签.
    static let chipFontSize: CGFloat = 12
    static let chipHorizontalPadding: CGFloat = 12
    static let chipVerticalPadding: CGFloat = 5.5
    // The mockup sets `line-height: 1.65` on the page, so its rows, pills and
    // buttons are taller than SwiftUI text alone; the vertical paddings below
    // add that difference back.
    /// Segmented control (`.pills`).
    static let pillFontSize: CGFloat = 12
    static let pillHorizontalPadding: CGFloat = 12
    static let pillVerticalPadding: CGFloat = 4.5
    static let pillTrackCornerRadius: CGFloat = 10
    static let pillTrackPadding: CGFloat = 2
    static let pillCornerRadius: CGFloat = 8
    /// Bordered button of a page toolbar (`.pbtn`).
    static let smallButtonFontSize: CGFloat = 12
    static let smallButtonHorizontalPadding: CGFloat = 14
    static let smallButtonVerticalPadding: CGFloat = 5.5
    static let smallButtonCornerRadius: CGFloat = 9
    /// Page number of the pager (`.pg`).
    static let pagerButtonSize: CGFloat = 28
    static let pagerButtonCornerRadius: CGFloat = 8
    /// Status dot of a row (`.dot`).
    static let statusDotSize: CGFloat = 10
    /// Status dot of a status line (`.sd`).
    static let statusLineDotSize: CGFloat = 7

    // MARK: - 主窗口

    /// Sidebar (`.app` first column, `.side`).
    static let sidebarWidth: CGFloat = 200
    static let sidebarPadding = EdgeInsets(top: 14, leading: 10, bottom: 14, trailing: 10)
    static let sidebarSpacing: CGFloat = 3
    static let sidebarRowPadding = EdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10)
    static let sidebarRowSpacing: CGFloat = 10
    static let sidebarRowCornerRadius: CGFloat = 10
    static let sidebarIconSize: CGFloat = 16
    /// Group title of the sidebar (`.sh`).
    static let sidebarSectionFontSize: CGFloat = 12
    static let sidebarSectionPadding = EdgeInsets(top: 12, leading: 10, bottom: 4, trailing: 10)
    /// GitHub row (`.ghub`, `.gt`).
    static let githubRowPadding: CGFloat = 8
    static let githubRowSpacing: CGFloat = 10
    static let githubRowCornerRadius: CGFloat = 10
    static let githubIconSize: CGFloat = 30
    static let githubNameFontSize: CGFloat = 12
    static let githubDetailFontSize: CGFloat = 11
    /// Content column of a page (`.main`).
    static let contentPadding = EdgeInsets(top: 14, leading: 8, bottom: 24, trailing: 22)
    static let contentSpacing: CGFloat = 12

    // MARK: - 连接设置窗口 and 首次启动窗口

    /// Width and padding of the 连接设置窗口 (`.sheet`).
    static let sheetWidth: CGFloat = 520
    static let sheetPadding = EdgeInsets(top: 22, leading: 24, bottom: 18, trailing: 24)
    /// Padding of a page of the 首次启动窗口 (`.welcome`).
    static let welcomePadding = EdgeInsets(top: 16, leading: 28, bottom: 22, trailing: 28)
    /// Input field (`.inp`).
    static let inputCornerRadius: CGFloat = 10
    static let inputHorizontalPadding: CGFloat = 12
    static let inputVerticalPadding: CGFloat = 8

    // MARK: - 菜单栏弹出面板

    /// Panel (`.desk .pop`). The rounded frosted window itself is drawn by
    /// `MenuBarExtra`, so only these numbers are set here.
    static let panelWidth: CGFloat = 480
    static let panelPadding: CGFloat = 14
    static let panelSpacing: CGFloat = 10
    /// Gateway name of the panel (`.gwrow b`).
    static let panelTitleFontSize: CGFloat = 15
    /// One event of the panel (`.pop .lr`).
    static let panelRowFontSize: CGFloat = 13
    /// Width of the `WAN1` column of a line row (`.wan` second column).
    static let panelLineIDColumnWidth: CGFloat = 44
    /// Space above the footer links (`.pop .foot`).
    static let panelFooterTopPadding: CGFloat = 10
}

/// The frosted window background of the mockup (`.glass`): a behind-window
/// blur with a faint plum tint in dark mode.
struct GlassBackground: View {
    var body: some View {
        ZStack {
            VisualEffectBackground()
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(red: 0.125, green: 0.118, blue: 0.149, alpha: 0.55)
                    : NSColor(white: 1, alpha: 0.25)
            })
        }
        .ignoresSafeArea()
    }
}

/// `NSVisualEffectView` blending with what is behind the window.
struct VisualEffectBackground: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = material
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }

    /// The HUD material is always dark, so light mode takes the sidebar one.
    private var material: NSVisualEffectView.Material {
        colorScheme == .dark ? .hudWindow : .sidebar
    }
}

/// The description column of a log list: the notification body without its
/// closing 「。」, as the mockup lists it.
enum LogDescription {
    static func text(for event: MonitoredLogEvent) -> String {
        let body = NotificationPlanner().notificationBody(for: event)
        return body.hasSuffix("。") ? String(body.dropLast()) : body
    }
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

    /// First group title of a page (`#d55cf0`): 设置 「通用」, 通知 「权限」.
    static let groupPink = Color(red: 0.835, green: 0.361, blue: 0.941)
    /// Second group title (`#8e8cf8`): 设置 「UniFi 网关」, 通知 「通知」.
    static let groupPurple = Color(red: 0.557, green: 0.549, blue: 0.973)
    /// Third group title (`#4fd1c5`): 设置 「监控事件」, 通知 「Bark 推送」.
    static let groupTeal = Color(red: 0.310, green: 0.820, blue: 0.773)

    /// Hairline around a card or an input field.
    static let border = Color.primary.opacity(0.09)
    /// Hairline around a small bordered button (`.pbtn`) and an input (`.inp`),
    /// a little stronger than the one of a card.
    static let controlBorder = Color.primary.opacity(0.14)
    /// Background of a selected sidebar row: light gray, never the accent color.
    static let selection = Color.primary.opacity(0.09)
    /// A bar of a severity bar the entry did not reach.
    static let severityOff = Color.primary.opacity(0.16)
    /// Background of a card, a chip and a grouped list (`--card`): darker than
    /// the frosted window in dark mode, lighter in light mode.
    static let card = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.black.withAlphaComponent(0.30)
            : NSColor.white.withAlphaComponent(0.55)
    })

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

/// A colored group title above a grid of cards (`.gh`).
struct GroupHeader: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.system(size: SentinelMetrics.groupHeaderFontSize, weight: .semibold))
            .foregroundStyle(color)
            .padding(.top, SentinelMetrics.groupHeaderTopPadding)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One settings card: title and control on one line, description, status line.
///
/// The card has the padding, the 20 pt corner radius and the hairline border of
/// `.fc` of the mockup.
struct SettingsCard<Control: View, Accessory: View>: View {
    let title: String
    let description: String
    let statusTone: StatusTone
    let statusText: String
    let control: Control
    let accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: SentinelMetrics.settingsCardSpacing) {
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
                .font(.system(size: SentinelMetrics.cardBodyFontSize))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack(spacing: 7) {
                Circle()
                    .fill(statusTone.color)
                    .frame(width: SentinelMetrics.statusLineDotSize, height: SentinelMetrics.statusLineDotSize)
                Text(statusText)
                    .font(.system(size: SentinelMetrics.cardBodyFontSize))
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
        .padding(SentinelMetrics.settingsCardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SentinelColor.card, in: RoundedRectangle(cornerRadius: SentinelMetrics.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: SentinelMetrics.cardCornerRadius)
                .stroke(SentinelColor.border, lineWidth: 1)
        )
    }

    /// Card title, shared by both layouts of the header (`.fch b`).
    private var titleLabel: some View {
        Text(title)
            .font(.system(size: SentinelMetrics.cardTitleFontSize, weight: .semibold))
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

/// Small segmented control (`.pills`): the selection is white on the accent
/// color, the other options are transparent on a faint track.
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
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                let isSelected = option.value == selection
                // A hairline between two options that are both unselected
                // (`.pills span + span::before`), as in the mockup.
                if index > 0, !isSelected, options[index - 1].value != selection {
                    Rectangle()
                        .fill(SentinelColor.controlBorder)
                        .frame(width: 1, height: SentinelMetrics.pillFontSize)
                }
                Button {
                    onSelect(option.value)
                } label: {
                    Text(option.title)
                        .font(.system(size: SentinelMetrics.pillFontSize))
                        .lineLimit(1)
                        .padding(.horizontal, SentinelMetrics.pillHorizontalPadding)
                        .padding(.vertical, SentinelMetrics.pillVerticalPadding)
                        .background(
                            RoundedRectangle(cornerRadius: SentinelMetrics.pillCornerRadius)
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
        .padding(SentinelMetrics.pillTrackPadding)
        .background(
            RoundedRectangle(cornerRadius: SentinelMetrics.pillTrackCornerRadius)
                .fill(SentinelColor.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SentinelMetrics.pillTrackCornerRadius)
                .stroke(SentinelColor.border, lineWidth: 1)
        )
    }
}

/// Grid columns of the pages that lay their cards out in a grid.
enum SettingsGridLayout {
    /// Two wide columns (`.fgrid`): the groups 「UniFi 网关」 and 「通用」.
    static let twoColumns = Array(repeating: GridItem(.flexible(), spacing: SentinelMetrics.cardSpacing), count: 2)

    /// Width below which the cards drop to two columns.
    static let threeColumnMinimumWidth: CGFloat = 620

    /// Three columns, two on a narrow window.
    static func columns(forWidth width: CGFloat) -> [GridItem] {
        let count = width >= threeColumnMinimumWidth ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: SentinelMetrics.cardSpacing), count: count)
    }

    /// One column per card, at most three, so two cards share the whole row
    /// instead of leaving the third column empty.
    ///
    /// Used by the 概览 card row: a gateway without WAN2 shows two cards, and
    /// they are as wide as the 最近事件 card below them.
    static func cardColumns(cardCount: Int, width: CGFloat) -> [GridItem] {
        var count = max(1, min(cardCount, 3))
        if width < threeColumnMinimumWidth {
            count = min(count, 2)
        }
        return Array(repeating: GridItem(.flexible(), spacing: SentinelMetrics.cardSpacing), count: count)
    }
}

/// Date and time texts of a log entry, in the formats the app uses everywhere.
///
/// The 菜单栏弹出面板, 概览 and 日志 share these, so a row never shows two
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
                .frame(width: SentinelMetrics.dateColumnWidth, alignment: .trailing)
            Text(LogTimestampText.clock(date))
                .frame(width: SentinelMetrics.timeColumnWidth, alignment: .trailing)
        }
        .font(.system(size: SentinelMetrics.timestampFontSize, design: .monospaced))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("时间 \(LogTimestampText.stamp(date))")
    }
}

/// A card of 概览 and 日志 (`.sc`): material, hairline border and a 20 pt
/// corner radius, like the cards of 设置.
struct SentinelCard<Content: View>: View {
    /// `false` for a card that keeps its own height inside a scroll view.
    private let fillsHeight: Bool
    /// Padding of the card; the table of 日志 passes `.tbl`.
    private let padding: EdgeInsets
    private let content: Content

    init(
        fillsHeight: Bool = true,
        padding: EdgeInsets = SentinelMetrics.cardPadding,
        @ViewBuilder content: () -> Content
    ) {
        self.fillsHeight = fillsHeight
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
            .padding(padding)
            .background(SentinelColor.card, in: RoundedRectangle(cornerRadius: SentinelMetrics.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: SentinelMetrics.cardCornerRadius)
                    .stroke(SentinelColor.border, lineWidth: 1)
            )
    }
}

/// The small label at the top of a card (`.cl`), for example 「WAN1 · CHINA TELECOM」.
struct CardLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: SentinelMetrics.cardLabelFontSize, weight: .semibold))
            .tracking(SentinelMetrics.cardLabelTracking)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

/// The big state of a card (`.big`): 在线, 断网中, 备用, 未启用 or a count.
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
                .font(.system(size: SentinelMetrics.bigNumberFontSize, weight: .bold))
                .foregroundStyle(color)
            if let unit {
                Text(unit)
                    .font(.system(size: SentinelMetrics.bigNumberUnitFontSize, weight: .semibold))
                    .foregroundStyle(color)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// One column of the three statistics at the bottom of a 概览 card (`.subs div`).
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

/// Three small statistics side by side, separated by hairlines (`.subs`).
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
                            .font(.system(size: SentinelMetrics.subNumberFontSize, weight: .bold))
                            .monospacedDigit()
                        if let unit = item.unit {
                            Text(unit)
                                .font(.system(size: SentinelMetrics.subCaptionFontSize))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(item.caption)
                        .font(.system(size: SentinelMetrics.subCaptionFontSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, item.id == items.first?.id ? 0 : SentinelMetrics.subStatisticsInnerPadding)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(item.caption) \(item.value)\(item.unit ?? "")")
            }
        }
        .padding(.top, SentinelMetrics.subStatisticsTopPadding)
    }
}

/// The 过去 24 小时 色条 of a 概览 线路卡片: 48 cells of half an hour (`.strip`).
///
/// 正常 is a short pale green bar, 临时中断 and 断网 are tall and colored, and
/// the last cell, 「现在」, is brighter.
struct OutageStripView: View {
    let strip: OutageStrip

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: SentinelMetrics.stripCellSpacing) {
                ForEach(strip.cells) { cell in
                    RoundedRectangle(cornerRadius: SentinelMetrics.stripCornerRadius)
                        .fill(color(of: cell))
                        .frame(height: height(of: cell))
                        .shadow(color: glow(of: cell), radius: 4)
                }
            }
            .frame(height: SentinelMetrics.stripHeight)

            HStack(spacing: 0) {
                Text(LogTimestampText.yesterdayClock(strip.start))
                Spacer(minLength: 8)
                Text(LogTimestampText.shortClock(middleDate))
                Spacer(minLength: 8)
                Text("现在")
            }
            .font(.system(size: SentinelMetrics.stripTickFontSize, design: .monospaced))
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
        guard cell.state == .normal else { return SentinelMetrics.stripHeight }
        return cell.isCurrent ? SentinelMetrics.stripCurrentHeight : SentinelMetrics.stripQuietHeight
    }

    /// The soft halo of a problem cell and of 「现在」.
    private func glow(of cell: OutageStripCell) -> Color {
        guard cell.state != .normal || cell.isCurrent else { return .clear }
        return color(of: cell).opacity(0.5)
    }
}

/// One page number of the pager of 日志 (`.pg`): the current page is blue.
struct PagerButton: View {
    let title: String
    let isCurrent: Bool
    let isEnabled: Bool
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: SentinelMetrics.smallButtonFontSize))
                .monospacedDigit()
                .lineLimit(1)
                .frame(minWidth: SentinelMetrics.pagerButtonSize, minHeight: SentinelMetrics.pagerButtonSize)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: SentinelMetrics.pagerButtonCornerRadius)
                        .fill(isCurrent ? Color.accentColor : SentinelColor.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SentinelMetrics.pagerButtonCornerRadius)
                        .stroke(isCurrent ? Color.accentColor : SentinelColor.border, lineWidth: 1)
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

/// A small bordered button of a page toolbar (`.pbtn`), for example 「导出 CSV」.
struct ToolbarButton: View {
    let title: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: SentinelMetrics.smallButtonFontSize))
                .lineLimit(1)
                .padding(.horizontal, SentinelMetrics.smallButtonHorizontalPadding)
                .padding(.vertical, SentinelMetrics.smallButtonVerticalPadding)
                .background(
                    RoundedRectangle(cornerRadius: SentinelMetrics.smallButtonCornerRadius)
                        .fill(SentinelColor.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SentinelMetrics.smallButtonCornerRadius)
                        .stroke(SentinelColor.controlBorder, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// A status dot with the soft halo of the mockup (`.dot`).
///
/// The halo is drawn behind the dot and grows outside its layout frame, so a row
/// of dots keeps the spacing the mockup shows.
struct GlowDot: View {
    let tone: StatusTone
    /// Diameter of the solid dot; the halo adds 8 pt around it.
    var size: CGFloat = SentinelMetrics.statusDotSize

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

/// The four small bars that show the severity of one log entry (`.sev`).
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

/// One 线路标签 of the 主窗口 (`.chip`): a small dot and a short text.
struct StatusChip: View {
    let tone: StatusTone
    let text: String
    let accessibilityLabel: String

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(tone.color)
                .frame(width: SentinelMetrics.statusLineDotSize, height: SentinelMetrics.statusLineDotSize)
            Text(text)
                .font(.system(size: SentinelMetrics.chipFontSize))
                .lineLimit(1)
        }
        .padding(.horizontal, SentinelMetrics.chipHorizontalPadding)
        .padding(.vertical, SentinelMetrics.chipVerticalPadding)
        .background(Capsule().fill(SentinelColor.card))
        .overlay(Capsule().stroke(SentinelColor.border, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }
}

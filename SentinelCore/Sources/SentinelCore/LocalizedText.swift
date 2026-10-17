import Foundation

// MARK: - Language source

/// The one language the whole app reads its texts in.
///
/// The app writes it whenever 设置 → 通用 → 语言 changes, so a new language
/// takes effect at once: no view, no notification and no CSV export keeps the
/// old text. `SentinelCore` and the app both read this value, so the two never
/// disagree.
///
/// The start value is Chinese: a test that never touches the language sees the
/// Chinese texts, and the app sets the stored language at launch before it reads
/// any text.
public enum AppText {
    /// The language the texts come back in.
    public static var language: ResolvedLanguage {
        get {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }
        set {
            lock.lock()
            stored = newValue
            lock.unlock()
        }
    }

    /// Applies the setting of 设置 → 通用 → 语言.
    ///
    /// - Parameter preferredLanguages: the Mac's languages, for `.system`.
    public static func use(
        _ language: AppLanguage,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) {
        self.language = language.resolved(preferredLanguages: preferredLanguages)
    }

    /// Runs `body` in a language and puts the previous one back afterwards.
    ///
    /// A test uses it, so a check of the English texts can never leak the
    /// language into the next check.
    @discardableResult
    public static func withLanguage<T>(_ language: ResolvedLanguage, _ body: () throws -> T) rethrows -> T {
        let previous = self.language
        self.language = language
        defer { self.language = previous }
        return try body()
    }

    /// Locale of the texts, for `DateFormatter` and every other locale-aware text.
    public static var locale: Locale {
        Locale(identifier: localeIdentifier)
    }

    /// Identifier of `locale`: `zh_Hans_CN` or `en_US`.
    public static var localeIdentifier: String {
        language == .chinese ? "zh_Hans_CN" : "en_US"
    }

    /// The text of one key in the current language.
    public static func string(_ key: TextKey) -> String {
        TextTable.string(key, language: language)
    }

    private static let lock = NSLock()
    private static var stored: ResolvedLanguage = .chinese
}

/// The text of one key: the current language, with the arguments filled in.
///
/// Every template holds `%@` (a text) or `%d` (a whole number); a key without an
/// argument is used with none. The two languages of a key live together in
/// `TextTable`, so a change of wording touches one line.
public func T(_ key: TextKey, _ arguments: CVarArg...) -> String {
    let template = AppText.string(key)
    guard !arguments.isEmpty else { return template }
    return String(format: template, arguments: arguments)
}

// MARK: - Table

/// The two texts of one key.
struct Translation: Equatable {
    let chinese: String
    let english: String

    subscript(_ language: ResolvedLanguage) -> String {
        language == .chinese ? chinese : english
    }
}

private func t(_ chinese: String, _ english: String) -> Translation {
    Translation(chinese: chinese, english: english)
}

/// The texts of the app, Chinese and English, one line per key.
enum TextTable {
    static let all: [TextKey: Translation] = [
        // MARK: Common
        .commonUnknown: t("未知", "Unknown"),
        .commonUnknownLower: t("未知", "unknown"),
        .commonUnknownSeverity: t("严重性未知", "Unknown severity"),
        .commonUnknownLine: t("未知线路", "Unknown line"),
        .commonListSeparator: t("，", ", "),
        .commonNow: t("现在", "Now"),
        .commonYesterday: t("昨天 %@", "Yesterday %@"),
        // English drops the unit: the caption next to the number says what it
        // counts, and 「1 times」 would read wrong.
        .commonUnitTimes: t("次", ""),
        .commonUnitItems: t("条", ""),
        .commonLabelValue: t("%@：%@", "%@: %@"),

        // MARK: Events
        .eventInternetDown: t("互联网中断", "Internet Down"),
        .eventInternetRestored: t("互联网已恢复", "Internet Restored"),
        .eventInternetDownMultipleTimes: t("多次互联网中断", "Multiple Internet Disconnections"),
        .eventInternetDownTemporary: t("临时互联网中断", "Temporary Internet Disconnection"),
        .eventPacketLoss: t("检测到丢包", "Packet Loss Detected"),
        .eventHighLatency: t("检测到高延迟", "High Latency Detected"),
        .eventThreatDetected: t("检测到威胁", "Threat Detected"),

        // MARK: Severity
        .severityLow: t("低", "Low"),
        .severityMedium: t("中", "Medium"),
        .severityHigh: t("高", "High"),
        .severityVeryHigh: t("非常高", "Very High"),

        // MARK: WAN state of the gateway
        .wanStateOnline: t("在线", "Online"),
        .wanStateOffline: t("离线", "Offline"),
        .wanStateDisabled: t("未启用", "Disabled"),
        .wanStateStandby: t("备用", "Standby"),

        // MARK: WAN line of the window
        .lineStateOnline: t("在线", "Online"),
        .lineStateDown: t("已断开", "Down"),
        .lineStateDisabled: t("未启用", "Disabled"),
        .lineStateStandby: t("备用", "Standby"),
        .lineStateDownFor: t("已断开 %@", "Down %@"),

        // MARK: Big state of a line card of 概览
        .overviewStateOnline: t("在线", "Online"),
        .overviewStateDown: t("断网中", "Down"),
        .overviewStateDisabled: t("未启用", "Disabled"),
        .overviewStateStandby: t("备用", "Standby"),

        // MARK: 24-hour strip
        .stripStateNormal: t("正常", "Normal"),
        .stripStateTemporary: t("临时中断", "Temporary"),
        .stripStateDown: t("中断", "Down"),
        .stripOutageCount: t("过去 24 小时中断 %d 次", "Outages in the last 24 hours: %d"),
        .stripTemporaryCount: t("临时中断 %d 次", "Temporary interruptions: %d"),

        // MARK: Duration
        .durationSeconds: t("%d 秒", "%d s"),
        .durationMinutes: t("%d 分", "%d min"),
        .durationHours: t("%d 小时", "%d h"),
        .durationDays: t("%d 天", "%d d"),

        // MARK: Connection state
        .connectionStateConnected: t("已连接", "Connected"),
        .connectionStateReconnecting: t("网关连不上", "Gateway unreachable"),
        .connectionStateAPIKeyRejected: t("API Key 无效", "Invalid API Key"),
        .connectionStateCertificateChanged: t("证书变了", "Certificate changed"),

        // MARK: Status line of the 连接 card
        .monitorConnectedAgo: t("已连上，%d 秒前查过", "Connected, checked %d s ago"),
        .monitorNotQueried: t("已连上，还没查过", "Connected, not checked yet"),
        .monitorCertificateChanged: t(
            "UniFi 网关的证书变了，请在「连接」里重新测试连接",
            "The UniFi gateway certificate changed. Test the connection again in Connection."
        ),
        .monitorAPIKeyRejected: t(
            "API Key 无效，请在「连接」里重新填",
            "Invalid API Key. Enter it again in Connection."
        ),

        // MARK: 菜单栏图标
        .indicatorQuiet: t("近 24 小时没有中及以上的事件", "No Medium or higher events in the last 24 hours"),
        .indicatorWarning: t("近 24 小时有中或高的事件", "Medium or High events in the last 24 hours"),
        .indicatorCritical: t(
            "近 24 小时有非常高的事件，或有线路正在断网",
            "A Very High event in the last 24 hours, or a line is down"
        ),
        .indicatorDisconnected: t(
            "网关连不上，或 API Key、证书有问题",
            "Gateway unreachable, or a problem with the API Key or certificate"
        ),
        .menuBarReadOut: t("Network Sentinel：%@", "Network Sentinel: %@"),
        .menuBarSeverityPhrase: t("近 24 小时有%@的事件", "%@ events in the last 24 hours"),
        .menuBarVeryHighPhrase: t("近 24 小时有非常高的事件", "Very High events in the last 24 hours"),
        .menuBarLineDownPhrase: t("有线路正在断网", "A line is down"),

        // MARK: Wake summary
        .wakeTitle: t("睡眠期间有 %d 条新日志", "New log entries while asleep: %d"),
        .wakeEntry: t("%@（%@）", "%@ (%@)"),
        .wakeMore: t("\n另外 %d 条在主窗口看。", "\n%d more in the main window."),

        // MARK: Notifications
        .notificationGatewayUnreachableTitle: t("UniFi 网关连不上", "UniFi gateway unreachable"),
        .notificationGatewayUnreachableBody: t(
            "%@\n请在「连接」里检查网关地址。",
            "%@\nCheck the gateway address in Connection."
        ),
        .notificationGatewayRestoredTitle: t("UniFi 网关已恢复连接", "UniFi gateway reconnected"),
        .notificationGatewayRestoredBody: t(
            "已经能读到 UniFi 网关的日志。",
            "The UniFi gateway log can be read again."
        ),
        .notificationAPIKeyRejectedTitle: t("API Key 无效", "Invalid API Key"),
        .notificationAPIKeyRejectedBody: t(
            "网关拒绝了 API Key，请在「连接」里重新填。",
            "The gateway rejected the API Key. Enter it again in Connection."
        ),
        .notificationCertificateChangedTitle: t("UniFi 网关的证书变了", "UniFi gateway certificate changed"),
        .notificationCertificateChangedBody: t(
            "网关的证书和记录的不一样，请在「连接」里重新测试连接。",
            "The gateway certificate does not match the saved one. Test the connection again in Connection."
        ),
        .notificationUnreachableTarget: t("无法连接到 %@", "Cannot reach %@"),
        .notificationUnreachableGateway: t("无法连接到 UniFi 网关", "Cannot reach the UniFi gateway"),
        .notificationReasonSuffix: t("：%@", ": %@"),
        .notificationTestTitle: t("Network Sentinel 测试推送", "Network Sentinel test push"),
        .notificationTestBody: t(
            "Bark 推送已连通，断网和威胁通知会同步发到这台设备。",
            "Bark is connected. Outage and threat notifications will be sent to this device too."
        ),

        // MARK: Notification bodies
        .bodyInternetDown: t("%@ 已断开。", "%@ is down."),
        .bodyInternetRestored: t("%@ 已恢复，断网 %@。", "%@ is back, down for %@."),
        .bodyInternetDownMultipleTimes: t(
            "%@ 在过去 24 小时内多次中断。",
            "%@ disconnected several times in the last 24 hours."
        ),
        .bodyInternetDownTemporary: t(
            "%@ 临时中断后已恢复，断开 %@。",
            "%@ recovered after a brief disconnection, down for %@."
        ),
        .bodyPacketLoss: t("%@ 检测到丢包。", "Packet loss detected on %@."),
        .bodyHighLatency: t("%@ 延迟升高到 %@ ms。", "Latency on %@ rose to %@ ms."),
        .bodyThreat: t("来自 %@ 到 %@ 的入侵尝试。", "Intrusion attempt from %@ to %@."),
        .bodyMergedCount: t("10 分钟内同类 %d 条。", "%d more of the same kind within 10 minutes."),

        // MARK: 日志 page
        .logRangeDay1: t("1 天", "1 day"),
        .logRangeDay7: t("7 天", "7 days"),
        .logRangeDay30: t("30 天", "30 days"),
        .logCategoryAll: t("全部", "All"),
        .logCategoryNetwork: t("网络", "Network"),
        .logCategoryThreat: t("威胁", "Threats"),
        .logFilterTimeRange: t("时间范围", "Time range"),
        .logFilterEventType: t("事件类型", "Event type"),
        .logFilterSeverity: t("严重性", "Severity"),
        .logPagerEmpty: t("共 0 条", "No entries"),
        .logPagerRange: t("第 %d–%d 条，共 %d 条", "%d–%d of %d"),
        .logPagerFirst: t("第一页", "First page"),
        .logPagerPrevious: t("上一页", "Previous page"),
        .logPagerPage: t("第 %d 页", "Page %d"),
        .logPagerNext: t("下一页", "Next page"),
        .logPagerLast: t("最后一页", "Last page"),

        // MARK: CSV
        .csvHeaderTime: t("时间", "Time"),
        .csvHeaderEvent: t("事件", "Event"),
        .csvHeaderSeverity: t("严重性", "Severity"),
        .csvHeaderLine: t("线路", "Line"),
        .csvHeaderDescription: t("描述", "Description"),
        .csvFileName: t("NetworkSentinel-日志-%@.csv", "NetworkSentinel-log-%@.csv"),

        // MARK: Pages and sidebar
        .pageOverview: t("概览", "Overview"),
        .pageLogs: t("日志", "Log"),
        .pageNotifications: t("通知", "Notifications"),
        .pageSettings: t("设置", "Settings"),
        .sidebarConfiguration: t("配置", "Configuration"),
        .sidebarGitHubHelp: t("在 GitHub 上查看源代码", "View the source on GitHub"),

        // MARK: 概览
        .overviewOpenSettings: t("去设置", "Open Settings"),
        .overviewGateway: t("网关", "Gateway"),
        .overviewQueryInterval: t("查询间隔", "Query interval"),
        .overviewLastQuery: t("上次查询", "Last query"),
        .overviewLoading: t("正在读取 UniFi 网关的日志…", "Reading the UniFi gateway log…"),
        .overviewLoadingReadOut: t("正在读取 UniFi 网关的日志", "Reading the UniFi gateway log"),
        .overviewThreatCardLabel: t("检测到威胁 · 24 小时", "Threat Detected · 24 hours"),
        .overviewNoThreats: t("近 24 小时没有威胁", "No threats in the last 24 hours"),
        .overviewThreatHint: t("UniFi 入侵防护记下的尝试", "Intrusion attempts logged by UniFi"),
        .overviewRecentEvents: t("最近事件", "Recent events"),
        .overviewNoEvents: t("近 24 小时没有监控事件", "No monitored events in the last 24 hours"),
        .overviewEventFilter: t("事件筛选", "Event filter"),
        .overviewSubOutages24h: t("24 小时中断", "Outages (24 h)"),
        .overviewSubTotalOutage: t("累计断网", "Total downtime"),
        .overviewSubLongest: t("最长一次", "Longest"),
        .overviewSubVeryHigh: t("非常高", "Very High"),
        .overviewSubHigh: t("高", "High"),
        .overviewSubMediumAndBelow: t("中及以下", "Medium and below"),
        .overviewIntervalSeconds: t("%d 秒", "%d s"),
        .statsLineReadOut: t(
            "24 小时中断 %d 次，累计断网 %@，最长一次 %@",
            "Outages in 24 hours: %d, total downtime %@, longest %@"
        ),
        .statsThreatReadOut: t(
            "24 小时威胁 %d 条，非常高 %d 条，高 %d 条，中及以下 %d 条",
            "Threats in 24 hours: %d, Very High %d, High %d, Medium and below %d"
        ),

        // MARK: 菜单栏弹出面板
        .panelConnectionProblem: t("连接问题：%@", "Connection problem: %@"),
        .panelSummary: t("24 小时：中断 %d 次 · 威胁 %d 条", "24 h: outages %d · threats %d"),
        .panelSummaryReadOut: t(
            "近 24 小时中断 %d 次，威胁 %d 条",
            "Last 24 hours: outages %d, threats %d"
        ),
        .panelOpenMainWindow: t("打开主窗口", "Open main window"),
        .panelOpenSettings: t("设置…", "Settings…"),
        .panelOpenSettingsReadOut: t("打开设置", "Open Settings"),
        .panelQuit: t("退出", "Quit"),
        .panelQuitReadOut: t("退出 Network Sentinel", "Quit Network Sentinel"),

        // MARK: 日志 page controls
        .logsExport: t("导出 CSV", "Export CSV"),
        .logsExportFailed: t("导出失败", "Export failed"),
        .logsOK: t("好", "OK"),
        .logsEmpty: t("这段时间没有符合条件的日志", "No log entries match this filter"),
        .logsWriteFailed: t("无法写入 %@：%@", "Cannot write %@: %@"),
        .logsTableSeverity: t("严重性", "Severity"),
        .logsTableEvent: t("事件", "Event"),
        .logsTableDescription: t("描述", "Description"),
        .logsTableDate: t("日期", "Date"),
        .logsTableTime: t("时间", "Time"),
        .logsTimeReadOut: t("时间 %@", "Time %@"),

        // MARK: 设置
        .settingsGroupGeneral: t("通用", "General"),
        .settingsGroupGateway: t("UniFi 网关", "UniFi Gateway"),
        .settingsGroupEvents: t("监控事件", "Monitored Events"),
        .settingsConnection: t("连接", "Connection"),
        .settingsConnectionNoAddress: t("还没填 UniFi 网关地址", "No UniFi gateway address yet"),
        .settingsConnectionAddress: t("%@\nAPI Key 存在钥匙串里", "%@\nAPI Key is in the keychain"),
        .settingsConnectionTesting: t("正在测试连接…", "Testing the connection…"),
        .settingsConnectionSuccess: t(
            "已连上 %@，能读到网络和威胁日志",
            "Connected to %@, network and threat logs readable"
        ),
        .settingsConnectionNotConnected: t("还没连上 UniFi 网关", "Not connected to the UniFi gateway yet"),
        .settingsConnectionNotRunning: t("监控没在运行", "Monitoring is not running"),
        .settingsConnectionTest: t("测试连接", "Test connection"),
        .settingsConnectionSettings: t("连接设置", "Connection settings"),
        .settingsConnectionNoKey: t(
            "钥匙串里没有 API Key，请打开连接设置重新填",
            "No API Key in the keychain. Open Connection settings and enter it again."
        ),
        .settingsQueryInterval: t("查询间隔", "Query interval"),
        .settingsQueryIntervalDescription: t(
            "多久向网关查一次新日志。间隔越短通知越快。",
            "How often the app reads new log entries from the gateway. A shorter interval means faster notifications."
        ),
        .settingsQueryIntervalStatus: t("每 %d 秒查一次", "Every %d s"),
        .settingsQueryIntervalOption: t("%d 秒", "%d s"),
        .settingsEventsMonitored: t("监控中", "Monitored"),
        .settingsEventsNotMonitored: t("未监控", "Not monitored"),
        .settingsEventsToggle: t("监控%@", "Monitor %@"),
        .settingsEventInternetDownDescription: t(
            "WAN 线路断开时记录。UniFi 一般标为非常高。",
            "Logged when a WAN line drops. UniFi usually marks it Very High."
        ),
        .settingsEventInternetRestoredDescription: t(
            "断开的线路恢复时记录，并算出断了多久。",
            "Logged when a dropped line comes back, with how long it was down."
        ),
        .settingsEventMultipleDescription: t(
            "同一条线路 24 小时内多次中断时，UniFi 发出的提醒。",
            "A notice from UniFi when one line dropped several times in 24 hours."
        ),
        .settingsEventThreatDescription: t(
            "UniFi 的入侵防护发现可疑流量时记录。",
            "Logged when UniFi intrusion prevention sees suspicious traffic."
        ),
        .settingsEventTemporaryDescription: t(
            "断开后很快自己恢复的闪断。",
            "A brief drop that recovered by itself."
        ),
        .settingsEventPacketLossDescription: t(
            "WAN 线路有丢包，但没有断网。",
            "Packet loss on a WAN line, without a disconnection."
        ),
        .settingsEventHighLatencyDescription: t(
            "WAN 线路延迟变高。",
            "Higher latency on a WAN line."
        ),
        .settingsLaunch: t("开机自启", "Launch at login"),
        .settingsLaunchDescription: t(
            "登录 Mac 后自动在菜单栏运行。",
            "Run in the menu bar after you log in to the Mac."
        ),
        .settingsLaunchApproval: t(
            "需要在「系统设置 → 通用 → 登录项」里允许 Network Sentinel",
            "Allow Network Sentinel in System Settings → General → Login Items"
        ),
        .settingsRetention: t("日志保留", "Log retention"),
        .settingsRetentionDescription: t(
            "超过这个时间的日志自动删除。",
            "Log entries older than this are deleted."
        ),
        .settingsRetentionStatus: t("保留 %d 天", "Keep %d days"),
        .settingsRetentionOption: t("%d 天", "%d days"),
        .settingsLanguage: t("语言", "Language"),
        .settingsLanguageDescription: t(
            "界面、系统通知和 Bark 推送用的语言。",
            "Language of the interface, the system notifications and the Bark pushes."
        ),
        .settingsLanguageStatus: t("当前：%@", "Current: %@"),
        .settingsLanguageSystem: t("跟随系统", "System"),
        .settingsLanguageChinese: t("中文", "Chinese"),
        .settingsLanguageEnglish: t("English", "English"),
        .settingsAppearance: t("外观", "Appearance"),
        .settingsAppearanceDescription: t(
            "主窗口和菜单栏面板的颜色。",
            "Colors of the main window and the menu bar panel."
        ),
        .settingsAppearanceSystem: t("跟随系统", "System"),
        .settingsAppearanceLight: t("浅色", "Light"),
        .settingsAppearanceDark: t("深色", "Dark"),
        .settingsAppearanceLightCurrent: t("当前：浅色", "Current: Light"),
        .settingsAppearanceDarkCurrent: t("当前：深色", "Current: Dark"),
        .settingsAppearanceLightSystem: t("当前：浅色（跟随系统）", "Current: Light (System)"),
        .settingsAppearanceDarkSystem: t("当前：深色（跟随系统）", "Current: Dark (System)"),
        .settingsOn: t("已开启", "On"),
        .settingsOff: t("已关闭", "Off"),

        // MARK: 通知
        .notificationsGroupPermission: t("权限", "Permission"),
        .notificationsGroupNotifications: t("通知", "Notifications"),
        .notificationsGroupBark: t("Bark 推送", "Bark Push"),
        .notificationsPermissionTitle: t("系统通知权限", "System notification permission"),
        .notificationsPermissionDescription: t(
            "在系统设置里允许后，断网和威胁的通知才会弹出来。",
            "Allow it in System Settings to get outage and threat notifications."
        ),
        .notificationsPermissionAllowed: t("已允许", "Allowed"),
        .notificationsPermissionOff: t("已关闭", "Off"),
        .notificationsPermissionOpen: t("打开系统设置", "Open System Settings"),
        .notificationsPermissionOpenReadOut: t(
            "打开系统设置的通知面板",
            "Open the Notifications pane of System Settings"
        ),
        .notificationsThreshold: t("弹通知", "Notify me"),
        .notificationsThresholdDescription: t(
            "选哪一级，就通知这一级及以上。",
            "The selected level and above send a notification."
        ),
        .notificationsThresholdQuoted: t("「%@」", "%@"),
        .notificationsThresholdPair: t("和", " and "),
        .notificationsThresholdList: t("、", ", "),
        .notificationsThresholdSuffix: t("会弹通知", " notifications"),
        .notificationsThresholdReadOut: t("弹通知的严重性", "Notification severity"),
        .notificationsRestoreTitle: t("恢复时总是通知", "Always notify on restore"),
        .notificationsRestoreDescription: t(
            "线路恢复时不管严重性都弹一条，写明断了多久。",
            "Send a notification on a restore whatever its severity, with how long the line was down."
        ),
        .notificationsMergeTitle: t("同类事件合并", "Merge same-kind events"),
        .notificationsMergeDescription: t(
            "%d 分钟内同类的事件合成一条通知。",
            "Same-kind events within %d minutes become one notification."
        ),
        .notificationsBarkTitle: t("Bark 推送", "Bark Push"),
        .notificationsBarkDescription: t(
            "把同样的通知同步推到装了 Bark 的 iPhone。网关连不上和「非常高」的事件用时效性通知，专注模式下也能收到。",
            "Send the same notifications to an iPhone with Bark. Gateway failures and Very High events are time sensitive, so they arrive even in Focus mode."
        ),
        .notificationsBarkNoKey: t("还没填 Bark Key", "No Bark Key yet"),
        .notificationsBarkOn: t("已开启", "On"),
        .notificationsBarkLastPush: t("已开启，上次推送 %@", "On, last push %@"),
        .notificationsBarkLastFailed: t("上次推送失败：%@", "Last push failed: %@"),
        .notificationsBarkUnknownReason: t("原因不明", "Unknown reason"),
        .notificationsBarkSettings: t("Bark 设置", "Bark settings"),
        .notificationsBarkServer: t(
            "服务器（用自建服务器时才改）",
            "Server (change it only for your own Bark server)"
        ),
        .notificationsBarkServerReadOut: t("Bark 服务器地址", "Bark server address"),
        .notificationsBarkKeySaved: t("Bark Key（存在钥匙串里）", "Bark Key (stored in the keychain)"),
        .notificationsBarkKeyEmpty: t(
            "Bark Key（在 Bark App 首页复制推送链接或 Key）",
            "Bark Key (copy the push link or Key from the Bark app)"
        ),
        .notificationsBarkKeyPlaceholder: t("粘贴 Bark Key 或推送链接", "Paste a Bark Key or push link"),
        .notificationsBarkShow: t("显示", "Show"),
        .notificationsBarkHide: t("隐藏", "Hide"),
        .notificationsBarkShowReadOut: t("显示 Bark Key", "Show Bark Key"),
        .notificationsBarkHideReadOut: t("隐藏 Bark Key", "Hide Bark Key"),
        .notificationsBarkRingtone: t(
            "自定义铃声（不填用 Bark 默认铃声）",
            "Custom ringtone (empty keeps the Bark default)"
        ),
        .notificationsBarkRingtonePlaceholder: t("例如 minuet", "e.g. minuet"),
        .notificationsBarkDeleteKey: t("删除 Key", "Delete key"),
        .notificationsBarkDeleteKeyReadOut: t("删除 Bark Key", "Delete the Bark Key"),
        .notificationsBarkSendTest: t("发送测试", "Send test"),
        .notificationsBarkSending: t("发送中…", "Sending…"),
        .notificationsBarkSendTestReadOut: t("发送一条 Bark 测试推送", "Send a Bark test push"),
        .notificationsBarkSave: t("保存", "Save"),
        .notificationsBarkSaveReadOut: t("保存 Bark Key", "Save the Bark Key"),
        .notificationsBarkSaved: t("已保存，可以点「发送测试」试一下", "Saved. You can try Send test."),
        .notificationsBarkDeleted: t("已删除 Bark Key", "Bark Key deleted"),
        .notificationsBarkTestSent: t("测试推送已发出，看看手机收到没有", "Test push sent. Check your phone."),
        .notificationsBarkSendFailed: t("发送失败", "Push failed"),

        // MARK: Connection form
        .connectionTitle: t("连接 UniFi 网关", "Connect the UniFi gateway"),
        .connectionIdle: t("填好后点「测试连接」", "Fill in both fields, then test the connection"),
        .connectionTesting: t("正在测试连接…", "Testing the connection…"),
        .connectionSuccess: t(
            "已连上 %@，能读到网络和威胁日志",
            "Connected to %@, network and threat logs readable"
        ),
        .connectionFailed: t("测试连接失败", "Connection test failed"),
        .connectionAddress: t("UniFi 网关地址", "UniFi gateway address"),
        .connectionAddressPlaceholder: t("例如 https://192.168.1.1", "e.g. https://192.168.1.1"),
        .connectionAPIKeyPlaceholder: t("粘贴 API Key", "Paste the API Key"),
        .connectionShow: t("显示", "Show"),
        .connectionHide: t("隐藏", "Hide"),
        .connectionShowAPIKey: t("显示 API Key", "Show API Key"),
        .connectionHideAPIKey: t("隐藏 API Key", "Hide API Key"),
        .connectionAPIKeyHint: t(
            "在 UniFi 网页左侧边栏点「Integrations → Create New API Key」生成",
            "In the UniFi web UI, open Integrations → Create New API Key"
        ),
        .connectionAPIKeyHintLong: t(
            "在 UniFi 网页左侧边栏点「Integrations → Create New API Key」生成，复制过来。",
            "In the UniFi web UI, open Integrations → Create New API Key, then copy it here."
        ),
        .connectionStatusReadOut: t("连接状态：%@", "Connection status: %@"),
        .connectionTest: t("测试连接", "Test connection"),
        .connectionCancel: t("取消", "Cancel"),
        .connectionCancelReadOut: t(
            "取消，不改动连接设置",
            "Cancel without changing the connection settings"
        ),
        .connectionSave: t("保存", "Save"),
        .connectionSaveReadOut: t("保存连接设置", "Save the connection settings"),

        // MARK: 首次启动窗口
        .firstLaunchIconReadOut: t("Network Sentinel App 图标", "Network Sentinel app icon"),
        .firstLaunchWelcome: t("欢迎使用 Network Sentinel", "Welcome to Network Sentinel"),
        .firstLaunchIntro: t(
            "先连上你的 UniFi 网关，才能开始监控断网和威胁日志。",
            "Connect your UniFi gateway first to monitor outage and threat logs."
        ),
        .firstLaunchQuit: t("退出", "Quit"),
        .firstLaunchNext: t("下一步", "Next"),
        .firstLaunchNextReadOut: t(
            "下一步：填写 UniFi 网关地址和 API Key",
            "Next: enter the UniFi gateway address and the API Key"
        ),
        .firstLaunchBack: t("上一步", "Back"),
        .firstLaunchBackReadOut: t("上一步：回到欢迎页", "Back: return to the welcome page"),
        .firstLaunchStart: t("开始使用", "Get started"),
        .firstLaunchStartReadOut: t(
            "开始使用，保存配置并打开主窗口",
            "Get started: save the configuration and open the main window"
        ),
        .firstLaunchPageDots: t("第 %d 页，共 2 页", "Page %d of 2"),

        // MARK: Severity read-out
        .severityReadOut: t("严重性：%@", "Severity: %@"),

        // MARK: Errors of the gateway
        .errorNetwork: t(
            "无法连接到 UniFi 网关，请检查网关地址和网络。",
            "Cannot reach the UniFi gateway. Check the gateway address and the network."
        ),
        .errorUnauthorized: t(
            "API Key 无效或没有权限（HTTP %d）。",
            "The API Key is invalid or has no permission (HTTP %d)."
        ),
        .errorNotFound: t(
            "网关没有这个接口（HTTP 404），可能固件版本不支持。",
            "The gateway has no such endpoint (HTTP 404). The firmware may not support it."
        ),
        .errorInvalidResponse: t(
            "网关返回了意外的状态码（HTTP %d）。",
            "The gateway returned an unexpected status code (HTTP %d)."
        ),
        .errorDecodingFailed: t("无法解析网关返回的内容（%@）。", "Cannot read the gateway response (%@)."),
        .errorGatewayDeviceNotFound: t(
            "网关状态里没有找到 UniFi 网关设备。",
            "No UniFi gateway device in the gateway status."
        ),
        .errorGatewayError: t("网关返回错误：%@", "The gateway returned an error: %@"),
        .errorTooManyPages: t(
            "日志页数超过安全上限（%d 页），已停止读取。",
            "Too many log pages (limit %d). Reading stopped."
        ),
        .errorInvalidURL: t("网关地址无效。", "The gateway address is invalid."),
        .errorCertificateChanged: t(
            "UniFi 网关的证书变了，请在连接设置里重新测试连接。",
            "The UniFi gateway certificate changed. Test the connection again in Connection settings."
        ),
        .errorQueryFailed: t("查询失败", "Query failed"),

        // MARK: Errors of 测试连接
        .connectionErrorEmptyAddress: t("请输入 UniFi 网关地址", "Enter the UniFi gateway address"),
        .connectionErrorInvalidAddress: t(
            "地址格式不对，请输入网关的 IP 地址或主机名，例如 192.168.8.254",
            "The address is not valid. Enter the gateway IP address or host name, for example 192.168.8.254"
        ),
        .connectionErrorCannotConnect: t(
            "连不上 UniFi 网关 %@，请检查地址和网络是否正常",
            "Cannot reach the UniFi gateway %@. Check the address and the network."
        ),
        .connectionErrorUnauthorized: t(
            "API Key 不对或没有权限读取日志",
            "The API Key is wrong, or it may not read the log"
        ),
        .connectionErrorNotSupported: t(
            "网关没有这个接口，固件版本可能不支持",
            "The gateway has no such endpoint. The firmware may not support it."
        ),
        .connectionErrorLogNotSupported: t(
            "网关没有读取日志的接口，固件版本可能不支持",
            "The gateway has no log endpoint. The firmware may not support it."
        ),
        .connectionErrorUnreadableResponse: t("看不懂网关返回的内容（%@）", "Cannot read the gateway response (%@)"),
        .connectionErrorGatewayRejected: t("网关拒绝了这次请求：%@", "The gateway refused the request: %@"),
        .connectionErrorGatewayNotFound: t(
            "网关状态里没有找到 UniFi 网关设备",
            "No UniFi gateway device in the gateway status"
        ),
        .connectionErrorCertificateUnavailable: t(
            "没有读到 UniFi 网关的证书，请重新测试连接",
            "The UniFi gateway certificate was not read. Test the connection again."
        ),
        .connectionErrorCertificateChanged: t(
            "UniFi 网关的证书变了，请在连接设置里重新测试连接",
            "The UniFi gateway certificate changed. Test the connection again in Connection settings."
        ),
        .connectionErrorPageLimit: t("日志页数超过上限 %d", "too many log pages: limit %d"),

        // MARK: Errors of the address field
        .addressErrorEmpty: t("请输入 UniFi 网关地址", "Enter the UniFi gateway address"),
        .addressErrorInvalid: t(
            "地址格式不对，请输入网关的 IP 地址或主机名，例如 192.168.8.254",
            "The address is not valid. Enter the gateway IP address or host name, for example 192.168.8.254"
        ),

        // MARK: Errors of Bark
        .barkErrorMissingKey: t("请输入 Bark Key", "Enter the Bark Key"),
        .barkErrorInvalidKey: t(
            "Bark Key 格式不对，请粘贴 Bark 里的推送地址或 Key",
            "The Bark Key is not valid. Paste the push link or the Key from Bark."
        ),
        .barkErrorInvalidServer: t("服务器地址格式不对", "The server address is not valid"),
        .barkErrorNetwork: t(
            "连不上 Bark 服务器，请检查服务器地址和网络。",
            "Cannot reach the Bark server. Check the server address and the network."
        ),
        .barkErrorRejectedKey: t(
            "Bark Key 不对，请在「通知」里重新填。",
            "The Bark Key is wrong. Enter it again in Notifications."
        ),
        .barkErrorServer: t("Bark 服务器返回错误：%@", "The Bark server returned an error: %@"),
        .barkErrorUnreadableResponse: t(
            "看不懂 Bark 服务器返回的内容。",
            "Cannot read the Bark server response."
        ),

        // MARK: Errors of the keychain
        .keychainErrorReadWrite: t(
            "无法读写钥匙串（%d：%@）。",
            "Cannot read or write the keychain (%d: %@)."
        ),
        .keychainErrorUnknown: t("未知错误", "Unknown error"),
        .keychainErrorUnreadableValue: t(
            "钥匙串里保存的 API Key 无法读取。",
            "The API Key stored in the keychain cannot be read."
        )
    ]

    /// The text of a key; the key itself for a key that has no text yet.
    static func string(_ key: TextKey, language: ResolvedLanguage) -> String {
        all[key]?[language] ?? key.rawValue
    }
}

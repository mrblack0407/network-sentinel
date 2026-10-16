import Foundation

/// One entry of the UniFi system log.
///
/// The gateway adds fields over time and parameter values vary in shape, so
/// decoding is deliberately tolerant: only `id` and `timestamp` are read
/// strictly, the rest falls back to safe defaults. A new field in the response
/// or an unknown severity never fails a page.
public struct SystemLogEntry: Decodable, Equatable, Identifiable {
    public let id: String
    /// Milliseconds since 1970, exactly as the gateway sends it.
    public let timestampMilliseconds: Int64
    public let category: String
    public let subcategory: String?
    public let key: String
    /// `nil` when the gateway sends a severity this version does not know.
    public let severity: LogSeverity?
    /// Title template as sent by the gateway, placeholders not filled.
    public let titleRaw: String
    /// Message template as sent by the gateway, placeholders not filled.
    public let messageRaw: String
    /// Parameter name to value. Only `id` and `name` of each value are kept.
    public let parameters: [String: LogParameter]
    public let status: String?
    public let target: String?
    public let type: String?
    /// The gateway `event` field, for example `NETWORK_WAN_FAILED`.
    public let eventName: String?
    public let showOnDashboard: Bool

    /// The entry timestamp as a `Date`.
    public var timestamp: Date {
        Date(timeIntervalSince1970: Double(timestampMilliseconds) / 1_000)
    }

    /// Title with `{PLACEHOLDER}` tokens filled from `parameters`.
    public var title: String {
        LogTemplate.render(titleRaw, parameters: parameters)
    }

    /// Message with `{PLACEHOLDER}` tokens filled from `parameters`.
    public var message: String {
        LogTemplate.render(messageRaw, parameters: parameters)
    }

    /// The monitored event of this entry, or `nil` when it is not monitored.
    public var monitoredEvent: MonitoredEvent? {
        MonitoredEvent.detect(category: category, key: key)
    }

    /// This entry as a monitored event with its extracted fields, or `nil` when
    /// the entry is not monitored.
    public var monitoredLogEvent: MonitoredLogEvent? {
        MonitoredLogEvent(entry: self)
    }

    /// Value of a parameter, using `name` first and `id` as the fallback.
    public func parameterValue(_ name: String) -> String? {
        parameters[name]?.substitutionValue
    }

    /// `WAN_ID` as shown by the gateway, for example `WAN1`.
    public var wanID: String? { parameterValue("WAN_ID") }

    /// `ISP_NAME`, for example `China Telecom`.
    public var ispName: String? { parameterValue("ISP_NAME") }

    /// `DURATION` as text, for example `1m 25s`.
    public var durationText: String? { parameterValue("DURATION") }

    /// `DURATION` in seconds, or `nil` when it is missing or unreadable.
    public var durationSeconds: Int? {
        durationText.flatMap(DurationParser.seconds(from:))
    }

    /// `LATENCY` in milliseconds, or `nil` when it is missing or unreadable.
    public var latencyMilliseconds: Int? {
        guard let text = parameterValue("LATENCY") else { return nil }
        return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Threat source: `SRC_CLIENT` when present, otherwise `SRC_IP`.
    public var sourceEndpoint: ThreatEndpoint? {
        Self.endpoint(clientKey: "SRC_CLIENT", ipKey: "SRC_IP", parameters: parameters)
    }

    /// Threat destination: `DST_CLIENT` when present, otherwise `DST_IP`.
    public var destinationEndpoint: ThreatEndpoint? {
        Self.endpoint(clientKey: "DST_CLIENT", ipKey: "DST_IP", parameters: parameters)
    }

    /// The events of the monitored entries of a log page, in order.
    public static func monitoredLogEvents(in entries: [SystemLogEntry]) -> [MonitoredLogEvent] {
        entries.compactMap { $0.monitoredLogEvent }
    }

    private static func endpoint(
        clientKey: String,
        ipKey: String,
        parameters: [String: LogParameter]
    ) -> ThreatEndpoint? {
        if let client = parameters[clientKey]?.substitutionValue {
            return ThreatEndpoint(value: client, isClient: true)
        }
        if let ip = parameters[ipKey]?.substitutionValue {
            return ThreatEndpoint(value: ip, isClient: false)
        }
        return nil
    }
}

extension SystemLogEntry {
    private enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case category
        case subcategory
        case key
        case severity
        case titleRaw = "title_raw"
        case messageRaw = "message_raw"
        case parameters
        case status
        case target
        case type
        case eventName = "event"
        case showOnDashboard = "show_on_dashboard"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = (try? container.decode(String.self, forKey: .id)) ?? ""
        timestampMilliseconds = (try? container.decode(Int64.self, forKey: .timestamp)) ?? 0
        category = (try? container.decode(String.self, forKey: .category)) ?? ""
        key = (try? container.decode(String.self, forKey: .key)) ?? ""
        titleRaw = (try? container.decode(String.self, forKey: .titleRaw)) ?? ""
        messageRaw = (try? container.decode(String.self, forKey: .messageRaw)) ?? ""
        showOnDashboard = (try? container.decode(Bool.self, forKey: .showOnDashboard)) ?? false

        // The optional annotations force the flattening of `try?` on the
        // optional-returning `decodeIfPresent`.
        let subcategory: String? = (try? container.decodeIfPresent(String.self, forKey: .subcategory)) ?? nil
        let status: String? = (try? container.decodeIfPresent(String.self, forKey: .status)) ?? nil
        let target: String? = (try? container.decodeIfPresent(String.self, forKey: .target)) ?? nil
        let type: String? = (try? container.decodeIfPresent(String.self, forKey: .type)) ?? nil
        let eventName: String? = (try? container.decodeIfPresent(String.self, forKey: .eventName)) ?? nil
        self.subcategory = subcategory
        self.status = status
        self.target = target
        self.type = type
        self.eventName = eventName

        // An unknown severity must not fail the page.
        let severityString: String? = (try? container.decodeIfPresent(String.self, forKey: .severity)) ?? nil
        severity = severityString.flatMap(LogSeverity.init(rawValueString:))

        // Optional parameter values keep a `null` value from failing the page.
        let parameterValues: [String: LogParameter?]? = (try? container.decodeIfPresent(
            [String: LogParameter?].self,
            forKey: .parameters
        )) ?? nil
        parameters = (parameterValues ?? [:]).compactMapValues { $0 }
    }
}

/// One side of a detected threat: a client or a raw IP address.
public struct ThreatEndpoint: Equatable {
    public let value: String
    /// `true` when the gateway reported a client instead of a raw IP address.
    public let isClient: Bool

    public init(value: String, isClient: Bool) {
        self.value = value
        self.isClient = isClient
    }
}

/// A monitored log entry with the fields the alert rules need.
public struct MonitoredLogEvent: Equatable, Identifiable {
    public let id: String
    public let event: MonitoredEvent
    public let timestamp: Date
    public let severity: LogSeverity?
    /// Title with placeholders filled.
    public let title: String
    /// Message with placeholders filled.
    public let message: String
    public let wanID: String?
    public let ispName: String?
    /// `DURATION` as sent by the gateway, for example `1m 25s`.
    public let durationText: String?
    /// `DURATION` in seconds.
    public let durationSeconds: Int?
    /// `LATENCY` in milliseconds.
    public let latencyMilliseconds: Int?
    public let source: ThreatEndpoint?
    public let destination: ThreatEndpoint?
    /// The original log entry, for the rules and the status file.
    public let entry: SystemLogEntry

    /// Builds a monitored event, or returns `nil` when the entry is not monitored.
    public init?(entry: SystemLogEntry) {
        guard let event = entry.monitoredEvent else { return nil }

        id = entry.id
        self.event = event
        timestamp = entry.timestamp
        severity = entry.severity
        title = entry.title
        message = entry.message
        wanID = entry.wanID
        ispName = entry.ispName
        durationText = entry.durationText
        durationSeconds = entry.durationSeconds
        latencyMilliseconds = entry.latencyMilliseconds
        source = entry.sourceEndpoint
        destination = entry.destinationEndpoint
        self.entry = entry
    }
}

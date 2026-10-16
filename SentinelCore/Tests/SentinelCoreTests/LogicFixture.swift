import Foundation
@testable import SentinelCore

/// Test data for the pure logic: log entries, monitored events and a fixed clock.
///
/// Nothing here reads the real clock, so the result of a test never depends on
/// the time the suite runs.
enum LogicFixture {
    /// Fixed "now" used by the merge and status tests: 2026-10-13 12:00:00 UTC.
    static let now = Date(timeIntervalSince1970: 1_792_075_200)

    /// A date `seconds` away from `now`, negative for the past.
    static func time(_ seconds: TimeInterval) -> Date {
        now.addingTimeInterval(seconds)
    }

    /// A moment 40 minutes before `now`, old enough to be outside a merge window.
    static func staleTime(_ seconds: TimeInterval = 0) -> Date {
        now.addingTimeInterval(-2_400 + seconds)
    }

    // MARK: - Log entries

    /// Builds one log entry of the given event, with the parameters the app reads.
    static func entry(
        id: String,
        event: MonitoredEvent,
        at date: Date,
        wanID: String? = "WAN1",
        ispName: String? = "China Telecom",
        severity: LogSeverity? = .high,
        duration: String? = nil,
        latency: String? = nil,
        source: String? = nil,
        destination: String? = nil,
        sourceIsClient: Bool = true,
        destinationIsClient: Bool = true
    ) throws -> SystemLogEntry {
        var parameters: [String: Any] = [:]

        if let wanID {
            parameters["WAN_ID"] = ["id": wanID, "name": wanID]
        }
        if let ispName {
            parameters["ISP_NAME"] = ["id": ispName, "name": ispName]
        }
        if let duration {
            parameters["DURATION"] = ["id": duration, "name": duration]
        }
        if let latency {
            parameters["LATENCY"] = ["name": latency]
        }
        if let source {
            parameters[sourceIsClient ? "SRC_CLIENT" : "SRC_IP"] = ["name": source]
        }
        if let destination {
            parameters[destinationIsClient ? "DST_CLIENT" : "DST_IP"] = ["name": destination]
        }

        return try SystemLogEntry.json([
            "id": id,
            "timestamp": Int64((date.timeIntervalSince1970 * 1_000).rounded()),
            "category": category(of: event),
            "key": key(of: event),
            "severity": severity?.rawValue as Any,
            "title_raw": titleTemplate(of: event),
            "message_raw": messageTemplate(of: event),
            "parameters": parameters,
            "show_on_dashboard": false,
        ].compactMapValues { $0 })
    }

    /// Builds a monitored event directly, for cases the app builds by hand.
    static func monitoredEvent(
        id: String,
        event: MonitoredEvent,
        at date: Date,
        wanID: String? = "WAN1",
        ispName: String? = "China Telecom",
        severity: LogSeverity? = .high,
        duration: String? = nil,
        latency: String? = nil,
        source: ThreatEndpoint? = nil,
        destination: ThreatEndpoint? = nil
    ) throws -> MonitoredLogEvent {
        let entry = try entry(
            id: id,
            event: event,
            at: date,
            wanID: wanID,
            ispName: ispName,
            severity: severity,
            duration: duration,
            latency: latency,
            source: source?.value,
            destination: destination?.value,
            sourceIsClient: source?.isClient ?? true,
            destinationIsClient: destination?.isClient ?? true
        )
        guard let monitored = entry.monitoredLogEvent else {
            throw Fixture.FixtureError.missing("monitored event for \(event.rawValue)")
        }
        return monitored
    }

    /// The gateway category of an event.
    static func category(of event: MonitoredEvent) -> String {
        event == .threatDetected ? "SECURITY" : "INTERNET_AND_WAN"
    }

    /// The gateway key of an event, with the version suffix the fixture uses.
    static func key(of event: MonitoredEvent) -> String {
        switch event {
        case .internetDown: return "NETWORK_WAN_FAILED_2"
        case .internetRestored: return "NETWORK_WAN_RESTORED_2"
        case .internetDownMultipleTimes: return "NETWORK_WAN_FAILED_MULTIPLE_TIMES_2"
        case .internetDownTemporary: return "NETWORK_WAN_FAILED_TEMPORARY_2"
        case .packetLoss: return "ISP_PACKET_LOSS_2"
        case .highLatency: return "ISP_HIGH_LATENCY_2"
        case .threatDetected: return "THREAT_DETECTED_V3"
        }
    }

    static func titleTemplate(of event: MonitoredEvent) -> String {
        switch event {
        case .internetDown: return "{WAN_ID} Internet Down"
        case .internetRestored: return "{WAN_ID} Internet Restored"
        case .internetDownMultipleTimes: return "{WAN_ID} Multiple Internet Disconnections"
        case .internetDownTemporary: return "{WAN_ID} Temporary Internet Disconnection"
        case .packetLoss: return "{WAN_ID} Packet Loss Detected"
        case .highLatency: return "{WAN_ID} High Latency Detected"
        case .threatDetected: return "Threat Detected"
        }
    }

    static func messageTemplate(of event: MonitoredEvent) -> String {
        switch event {
        case .internetDown:
            return "Internet connection {WAN_ID} {ISP_NAME} on port {PORT} is down."
        case .internetRestored:
            return "Internet connection {WAN_ID} {ISP_NAME} on port {PORT} is restored."
        case .internetDownMultipleTimes:
            return "Internet connection {WAN_ID} {ISP_NAME} went down multiple times."
        case .internetDownTemporary:
            return "Internet connection {WAN_ID} {ISP_NAME} is restored after a temporary disconnection."
        case .packetLoss:
            return "Internet connection {WAN_ID} {ISP_NAME} is experiencing packet loss."
        case .highLatency:
            return "Internet connection {WAN_ID} {ISP_NAME} is experiencing high latency."
        case .threatDetected:
            return "A network intrusion attempt from {SRC_IP} to {DST_IP} has been detected."
        }
    }

    // MARK: - Gateway

    /// A gateway with WAN1 (or WAN1 + WAN2) for the status file tests.
    ///
    /// - Parameters:
    ///   - wan1: state of the first line, 在线 by default.
    ///   - wan2: state of the second line; `nil` leaves the line unassigned.
    static func gatewayStatus(wan1: WANState = .online, wan2: WANState? = nil) -> GatewayStatus {
        var interfaces = [
            WANStatus(
                id: "WAN1",
                interfaceName: "eth9",
                state: wan1,
                ipAddress: "10.20.0.1",
                portIndex: 10,
                media: "GE",
                speedMbps: 1_000
            )
        ]
        if let wan2 {
            interfaces.append(
                WANStatus(
                    id: "WAN2",
                    interfaceName: "eth10",
                    state: wan2,
                    ipAddress: nil,
                    portIndex: 11,
                    media: "GE",
                    speedMbps: 1_000
                )
            )
        }

        return GatewayStatus(
            name: "Dream Machine Pro Max",
            model: "UDM-Pro-Max",
            firmwareVersion: "5.1.33",
            deviceType: "udm",
            wanInterfaces: interfaces
        )
    }

    // MARK: - Temporary directories

    /// A unique temporary directory that the test cleans up itself.
    ///
    /// It lives under `/tmp`, so the repository never gets a temporary folder.
    static func makeTemporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("network-sentinel-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Removes a temporary directory created by `makeTemporaryDirectory`.
    static func removeTemporaryDirectory(_ url: URL) {
        // Guard against a mistaken path: only touch our own /tmp folders.
        guard url.path.hasPrefix("/tmp/network-sentinel-tests-") else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

/// Counts `refresh()` calls of the status file store.
final class RecordingWidgetRefresher: WidgetRefreshing {
    private(set) var refreshCount = 0

    func refresh() {
        refreshCount += 1
    }
}

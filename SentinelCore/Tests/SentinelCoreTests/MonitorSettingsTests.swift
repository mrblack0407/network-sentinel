import XCTest
@testable import SentinelCore

final class MonitorSettingsTests: XCTestCase {
    // MARK: - Defaults

    func testDefaults() {
        let settings = MonitorSettings()

        XCTAssertEqual(settings.queryIntervalSeconds, 30)
        XCTAssertEqual(settings.logRetentionDays, 90)
        XCTAssertEqual(settings.notifications.minimumSeverity, .high)
        XCTAssertTrue(settings.notifications.alwaysNotifyOnRestore)
        XCTAssertTrue(settings.notifications.mergeSameKind)
        XCTAssertEqual(settings.notifications.mergeWindowSeconds, 600)
    }

    func testDefaultsMonitorTheExpectedEvents() {
        let settings = MonitorSettings()

        XCTAssertTrue(settings.isEnabled(.internetDown))
        XCTAssertTrue(settings.isEnabled(.internetRestored))
        XCTAssertTrue(settings.isEnabled(.internetDownMultipleTimes))
        XCTAssertTrue(settings.isEnabled(.threatDetected))
        XCTAssertTrue(settings.isEnabled(.internetDownTemporary))

        XCTAssertFalse(settings.isEnabled(.packetLoss))
        XCTAssertFalse(settings.isEnabled(.highLatency))
    }

    func testOptionsMatchTheSpecification() {
        XCTAssertEqual(MonitorSettings.queryIntervalOptions, [15, 30, 60])
        XCTAssertEqual(MonitorSettings.logRetentionOptions, [30, 90, 180])
        XCTAssertTrue(MonitorSettings.queryIntervalOptions.contains(MonitorSettings().queryIntervalSeconds))
        XCTAssertTrue(MonitorSettings.logRetentionOptions.contains(MonitorSettings().logRetentionDays))
        XCTAssertEqual(
            MonitorSettings.disabledByDefault.sorted { $0.rawValue < $1.rawValue },
            [.packetLoss, .highLatency].sorted { $0.rawValue < $1.rawValue }
        )
    }

    // MARK: - Encoding

    func testCodableRoundTripKeepsEveryValue() throws {
        var settings = MonitorSettings()
        settings.monitoredEvents = [.internetDown, .highLatency]
        settings.notifications.minimumSeverity = .veryHigh
        settings.notifications.alwaysNotifyOnRestore = false
        settings.notifications.mergeSameKind = false
        settings.notifications.mergeWindowSeconds = 120
        settings.queryIntervalSeconds = 60
        settings.logRetentionDays = 30

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(MonitorSettings.self, from: data)

        XCTAssertEqual(decoded, settings)
    }

    func testDecodingAMissingStoredValueFallsBackToDefaults() throws {
        let data = try JSONSerialization.data(withJSONObject: ["monitoredEvents": ["internetDown"]])

        let settings = try JSONDecoder().decode(MonitorSettings.self, from: data)

        XCTAssertEqual(settings.monitoredEvents, [.internetDown])
        XCTAssertEqual(settings.notifications, NotificationSettings())
        XCTAssertEqual(settings.queryIntervalSeconds, 30)
        XCTAssertEqual(settings.logRetentionDays, 90)
    }

    func testDecodingAnEmptyObjectGivesTheDefaults() throws {
        let data = try JSONSerialization.data(withJSONObject: [String: Any]())

        let settings = try JSONDecoder().decode(MonitorSettings.self, from: data)

        XCTAssertEqual(settings, MonitorSettings())
    }

    // MARK: - Threshold

    func testUnknownSeverityCountsAsLow() {
        XCTAssertEqual(NotificationSettings.effectiveSeverity(nil), .low)
        XCTAssertEqual(NotificationSettings.effectiveSeverity(.low), .low)
        XCTAssertEqual(NotificationSettings.effectiveSeverity(.veryHigh), .veryHigh)
    }

    func testThreshold() {
        let settings = NotificationSettings(minimumSeverity: .high, alwaysNotifyOnRestore: false)

        XCTAssertFalse(settings.passesThreshold(.low, for: .internetDown))
        XCTAssertFalse(settings.passesThreshold(.medium, for: .internetDown))
        XCTAssertTrue(settings.passesThreshold(.high, for: .internetDown))
        XCTAssertTrue(settings.passesThreshold(.veryHigh, for: .internetDown))
        // An unknown severity is treated as 低.
        XCTAssertFalse(settings.passesThreshold(nil, for: .internetDown))
    }

    func testRestoreBypassesTheThresholdOnlyWhileTheSettingIsOn() {
        let restoring = NotificationSettings(minimumSeverity: .veryHigh, alwaysNotifyOnRestore: true)
        XCTAssertTrue(restoring.passesThreshold(.low, for: .internetRestored))

        let strict = NotificationSettings(minimumSeverity: .veryHigh, alwaysNotifyOnRestore: false)
        XCTAssertFalse(strict.passesThreshold(.low, for: .internetRestored))
        XCTAssertTrue(strict.passesThreshold(.veryHigh, for: .internetRestored))
    }
}

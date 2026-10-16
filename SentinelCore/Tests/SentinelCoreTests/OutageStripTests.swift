import XCTest
@testable import SentinelCore

/// The 过去 24 小时 色条 of a 概览 线路卡片.
final class OutageStripTests: XCTestCase {
    private let now = LogicFixture.now

    /// The strip of WAN1, with the outages paired from the same events.
    private func strip(events: [MonitoredLogEvent] = [], wanID: String? = "WAN1") -> OutageStrip {
        OutageStripBuilder.strip(
            events: events,
            outages: OutagePairer.outages(in: events),
            wanID: wanID,
            now: now
        )
    }

    // MARK: - Geometry

    func testTheStripCoversTwentyFourHoursInHalfHours() {
        let result = strip()

        XCTAssertEqual(result.cells.count, 48)
        XCTAssertEqual(result.start, now.addingTimeInterval(-24 * 60 * 60))
        XCTAssertEqual(result.end, now)
        XCTAssertEqual(result.cells.first?.start, result.start)
        XCTAssertEqual(result.cells.last?.end, now)

        for cell in result.cells {
            XCTAssertEqual(cell.end.timeIntervalSince(cell.start), 30 * 60, "cell \(cell.index)")
            XCTAssertEqual(cell.state, .normal, "cell \(cell.index)")
        }
    }

    func testTheLastCellIsNow() {
        let result = strip()

        XCTAssertTrue(result.cells[47].isCurrent)
        XCTAssertEqual(result.cells[47].end, now)
        XCTAssertFalse(result.cells[46].isCurrent)
    }

    func testTheCellOfADateIsWhereTheStripFindsIt() throws {
        // A date in the middle of the window lands in the middle cell.
        let events = try [LogicFixture.monitoredEvent(id: "down", event: .internetDown, at: now.addingTimeInterval(-12 * 3_600))]

        let result = strip(events: events)

        XCTAssertEqual(result.cells[24].state, .down)
    }

    // MARK: - Cell boundaries

    /// A 临时互联网中断 is used for the boundary cases: unlike 互联网中断 it
    /// paints one cell only, so the test sees the cell boundary alone.
    func testAnEntryAtACellBoundaryBelongsToTheNewerCell() throws {
        // The start of cell 46 is half an hour before the newest full cell.
        let boundary = now.addingTimeInterval(-3_600)
        let events = try [LogicFixture.monitoredEvent(id: "temp", event: .internetDownTemporary, at: boundary)]

        let result = strip(events: events)

        XCTAssertEqual(result.cells[46].state, .temporary)
        XCTAssertEqual(result.cells[45].state, .normal)
    }

    func testAnEntryJustBeforeACellBoundaryStaysInTheOlderCell() throws {
        let events = try [LogicFixture.monitoredEvent(id: "temp", event: .internetDownTemporary, at: now.addingTimeInterval(-3_601))]

        let result = strip(events: events)

        XCTAssertEqual(result.cells[45].state, .temporary)
        XCTAssertEqual(result.cells[46].state, .normal)
    }

    func testAnEntryStampedNowColorsTheLastCell() throws {
        let events = try [LogicFixture.monitoredEvent(id: "temp", event: .internetDownTemporary, at: now)]

        let result = strip(events: events)

        XCTAssertEqual(result.cells[47].state, .temporary)
        XCTAssertEqual(result.cells[46].state, .normal)
    }

    // MARK: - Outages

    func testAnOutagePaintsEveryCellItCovers() throws {
        let events = try [
            LogicFixture.monitoredEvent(id: "down", event: .internetDown, at: now.addingTimeInterval(-7_200)),
            LogicFixture.monitoredEvent(id: "up", event: .internetRestored, at: now.addingTimeInterval(-3_000), duration: "1m 10s"),
        ]

        let result = strip(events: events)

        XCTAssertEqual(result.cells[43].state, .normal)
        XCTAssertEqual(result.cells[44].state, .down)
        XCTAssertEqual(result.cells[45].state, .down)
        XCTAssertEqual(result.cells[46].state, .down)
        XCTAssertEqual(result.cells[47].state, .normal)
        XCTAssertEqual(result.outageCount, 1)
    }

    func testAnOutageWithoutARestorePaintsUpToNow() throws {
        let events = try [LogicFixture.monitoredEvent(id: "down", event: .internetDown, at: now.addingTimeInterval(-4_000))]

        let result = strip(events: events)

        XCTAssertEqual(result.cells[44].state, .normal)
        XCTAssertEqual(result.cells[45].state, .down)
        XCTAssertEqual(result.cells[46].state, .down)
        XCTAssertEqual(result.cells[47].state, .down)
    }

    func testAnOpenOutageOlderThanTheWindowPaintsTheWholeStrip() throws {
        // The app last knew the line was down 25 hours ago and never saw a
        // restore, so the whole window counts as 断网.
        let events = try [LogicFixture.monitoredEvent(id: "down", event: .internetDown, at: now.addingTimeInterval(-25 * 3_600))]

        let result = strip(events: events)

        XCTAssertEqual(result.outageCount, 1)
        XCTAssertTrue(result.cells.allSatisfy { $0.state == .down })
    }

    func testAnOutageThatEndedBeforeTheWindowPaintsNothing() throws {
        let events = try [
            LogicFixture.monitoredEvent(id: "down", event: .internetDown, at: now.addingTimeInterval(-25 * 3_600)),
            LogicFixture.monitoredEvent(id: "up", event: .internetRestored, at: now.addingTimeInterval(-24.5 * 3_600)),
        ]

        let result = strip(events: events)

        XCTAssertEqual(result.outageCount, 0)
        XCTAssertTrue(result.cells.allSatisfy { $0.state == .normal })
    }

    // MARK: - Temporary disconnections

    func testATemporaryDisconnectionPaintsYellow() throws {
        let events = try [LogicFixture.monitoredEvent(id: "temp", event: .internetDownTemporary, at: now.addingTimeInterval(-3_000))]

        let result = strip(events: events)

        XCTAssertEqual(result.cells[46].state, .temporary)
        XCTAssertEqual(result.cells[45].state, .normal)
        XCTAssertEqual(result.outageCount, 0)
        XCTAssertEqual(result.temporaryCount, 1)
    }

    func testAnOutageWinsOverATemporaryDisconnectionInTheSameCell() throws {
        let events = try [
            LogicFixture.monitoredEvent(id: "temp", event: .internetDownTemporary, at: now.addingTimeInterval(-3_000)),
            LogicFixture.monitoredEvent(id: "down", event: .internetDown, at: now.addingTimeInterval(-2_000)),
        ]

        let result = strip(events: events)

        XCTAssertEqual(result.cells[46].state, .down)
    }

    // MARK: - Lines

    func testOnlyTheLineOfTheStripPaintsIt() throws {
        let events = try [
            LogicFixture.monitoredEvent(id: "wan2-down", event: .internetDown, at: now.addingTimeInterval(-3_000), wanID: "WAN2")
        ]

        XCTAssertEqual(strip(events: events, wanID: "WAN2").cells[46].state, .down)
        XCTAssertEqual(strip(events: events, wanID: "WAN1").cells[46].state, .normal)
        XCTAssertEqual(strip(events: events, wanID: "WAN1").outageCount, 0)
    }

    // MARK: - Read-out

    func testTheReadOutCountsTheOutagesOfTheWindow() throws {
        let events = try [
            LogicFixture.monitoredEvent(id: "down-1", event: .internetDown, at: now.addingTimeInterval(-7_200)),
            LogicFixture.monitoredEvent(id: "up-1", event: .internetRestored, at: now.addingTimeInterval(-7_100), duration: "1m 40s"),
            LogicFixture.monitoredEvent(id: "down-2", event: .internetDown, at: now.addingTimeInterval(-3_600)),
            LogicFixture.monitoredEvent(id: "up-2", event: .internetRestored, at: now.addingTimeInterval(-3_500), duration: "1m 40s"),
        ]

        let result = strip(events: events)

        XCTAssertEqual(result.outageCount, 2)
        XCTAssertEqual(result.accessibilityText, "过去 24 小时中断 2 次")
    }

    func testTheReadOutMentionsTemporaryDisconnections() throws {
        let events = try [LogicFixture.monitoredEvent(id: "temp", event: .internetDownTemporary, at: now.addingTimeInterval(-3_000))]

        XCTAssertEqual(strip(events: events).accessibilityText, "过去 24 小时中断 0 次，临时中断 1 次")
    }
}

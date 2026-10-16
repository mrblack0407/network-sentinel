import XCTest
@testable import SentinelCore

final class SeenLogIDsTests: XCTestCase {
    // MARK: - Deduplication

    func testTheSameIDIsOnlyNewOnce() {
        var seen = SeenLogIDs()

        XCTAssertTrue(seen.insertIfNew("a"))
        XCTAssertFalse(seen.insertIfNew("a"))
        XCTAssertTrue(seen.insertIfNew("b"))
        XCTAssertEqual(seen.count, 2)
        XCTAssertEqual(seen.ids, ["a", "b"])
    }

    func testAFullQueryOfDuplicatesReportsEachEntryOnce() throws {
        let first = try LogicFixture.entry(id: "a", event: .internetDown, at: LogicFixture.time(0))
        let second = try LogicFixture.entry(id: "a", event: .internetDown, at: LogicFixture.time(0))
        let third = try LogicFixture.entry(id: "b", event: .internetDown, at: LogicFixture.time(60))

        var seen = SeenLogIDs()
        let result = seen.filterNew([first, second, third])

        XCTAssertEqual(result.new.map(\.id), ["a", "b"])
        XCTAssertEqual(result.seen.map(\.id), ["a"])
        XCTAssertEqual(seen.count, 2)
    }

    func testReinsertingDoesNotMoveAnIDToTheEnd() {
        var seen = SeenLogIDs(capacity: 3)

        seen.insert(contentsOf: ["a", "b", "c"])
        seen.insert("a")

        XCTAssertEqual(seen.ids, ["a", "b", "c"])
        XCTAssertEqual(seen.mostRecentID, "c")
    }

    // MARK: - Capacity

    func testCapacityDropsTheOldestIDs() {
        var seen = SeenLogIDs(capacity: 3)

        seen.insert(contentsOf: ["a", "b", "c", "d", "e"])

        XCTAssertEqual(seen.count, 3)
        XCTAssertEqual(seen.ids, ["c", "d", "e"])
        XCTAssertFalse(seen.contains("a"))
        XCTAssertFalse(seen.contains("b"))
        XCTAssertTrue(seen.contains("e"))
    }

    func testCapacityOfOneIsAllowedAndKeepsTheNewest() {
        var seen = SeenLogIDs(capacity: 1)

        seen.insert(contentsOf: ["a", "b"])

        XCTAssertEqual(seen.ids, ["b"])
    }

    func testCapacityBelowOneIsRaisedToOne() {
        var seen = SeenLogIDs(capacity: 0)

        seen.insert("a")
        seen.insert("b")

        XCTAssertEqual(seen.capacity, 1)
        XCTAssertEqual(seen.ids, ["b"])
    }

    func testTheDefaultCapacityIsBounded() {
        XCTAssertEqual(SeenLogIDs().capacity, 5_000)
        XCTAssertEqual(SeenLogIDs.defaultCapacity, 5_000)
    }

    // MARK: - Persistence

    func testEncodingAndDecodingRemembersTheIDs() throws {
        var seen = SeenLogIDs(capacity: 4)
        seen.insert(contentsOf: ["a", "b", "c"])

        let data = try JSONEncoder().encode(seen)
        let restored = try JSONDecoder().decode(SeenLogIDs.self, from: data)

        XCTAssertEqual(restored, seen)
        XCTAssertTrue(restored.contains("a"))
        XCTAssertEqual(restored.count, 3)
        // After a restart the same entry is still not new.
        var afterRestart = restored
        XCTAssertFalse(afterRestart.insertIfNew("a"))
        XCTAssertTrue(afterRestart.insertIfNew("d"))
    }

    func testDecodingWithAMissingCapacityUsesTheDefault() throws {
        let data = try JSONSerialization.data(withJSONObject: ["ids": ["a", "b"]])

        let seen = try JSONDecoder().decode(SeenLogIDs.self, from: data)

        XCTAssertEqual(seen.capacity, SeenLogIDs.defaultCapacity)
        XCTAssertEqual(seen.ids, ["a", "b"])
    }

    func testDecodingTrimsAStoredValueOverCapacity() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "ids": ["a", "b", "c", "d"],
            "capacity": 2,
        ])

        let seen = try JSONDecoder().decode(SeenLogIDs.self, from: data)

        XCTAssertEqual(seen.ids, ["c", "d"])
        XCTAssertEqual(seen.count, 2)
    }

    func testRemoveAllForgetsEverything() {
        var seen = SeenLogIDs()
        seen.insert(contentsOf: ["a", "b"])

        seen.removeAll()

        XCTAssertTrue(seen.isEmpty)
        XCTAssertTrue(seen.insertIfNew("a"))
    }
}

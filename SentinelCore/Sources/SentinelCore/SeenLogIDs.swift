import Foundation

/// Remembers which log entries have already been handled.
///
/// The gateway returns a whole time range on every query, so the same entry
/// shows up again and again. The set of seen `id`s is stored in the app
/// preferences, which is why it is `Codable`: after a restart an entry that was
/// already notified never notifies again.
///
/// The set has a capacity: past it the oldest ids are dropped, so the stored
/// value cannot grow forever. Insertion order is kept for that, and an `id`
/// that is seen again does not move to the end.
public struct SeenLogIDs: Codable, Equatable {
    /// Default capacity, large enough for a day of busy logs.
    public static let defaultCapacity = 5_000

    /// Ids in insertion order, oldest first.
    public private(set) var ids: [String]
    public let capacity: Int

    public init(capacity: Int = SeenLogIDs.defaultCapacity) {
        self.ids = []
        // A capacity below one would drop every id and notify forever.
        self.capacity = max(1, capacity)
    }

    public var count: Int { ids.count }

    public var isEmpty: Bool { ids.isEmpty }

    /// Most recently added id.
    public var mostRecentID: String? { ids.last }

    /// `true` when this entry was already handled.
    public func contains(_ id: String) -> Bool {
        index(of: id) != nil
    }

    /// Marks the entry as handled. A second call with the same `id` changes nothing.
    public mutating func insert(_ id: String) {
        guard index(of: id) == nil else { return }
        ids.append(id)
        dropOldestIfOverCapacity()
    }

    /// Marks several entries as handled, in order.
    public mutating func insert(contentsOf newIDs: [String]) {
        for id in newIDs {
            insert(id)
        }
    }

    /// Marks the entry as handled and returns `true` only the first time.
    @discardableResult
    public mutating func insertIfNew(_ id: String) -> Bool {
        guard index(of: id) == nil else { return false }
        insert(id)
        return true
    }

    /// Splits a batch into the entries that are new and the ones already handled.
    ///
    /// The ids of the new entries are remembered. Order is preserved.
    public mutating func filterNew(_ entries: [SystemLogEntry]) -> (new: [SystemLogEntry], seen: [SystemLogEntry]) {
        var new: [SystemLogEntry] = []
        var seen: [SystemLogEntry] = []

        for entry in entries {
            if insertIfNew(entry.id) {
                new.append(entry)
            } else {
                seen.append(entry)
            }
        }

        return (new, seen)
    }

    /// Forgets every id, for a "start over" action.
    public mutating func removeAll() {
        ids.removeAll()
    }

    private func index(of id: String) -> Int? {
        ids.firstIndex(of: id)
    }

    private mutating func dropOldestIfOverCapacity() {
        let excess = ids.count - capacity
        if excess > 0 {
            ids.removeFirst(excess)
        }
    }
}

extension SeenLogIDs {
    private enum CodingKeys: String, CodingKey {
        case ids
        case capacity
    }

    /// Tolerant decoding: a stored value from an older version still loads.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ids = (try? container.decode([String].self, forKey: .ids)) ?? []
        let storedCapacity = (try? container.decode(Int.self, forKey: .capacity)) ?? Self.defaultCapacity
        capacity = max(1, storedCapacity)

        // A hand-edited or older file could be over capacity.
        if ids.count > capacity {
            ids.removeFirst(ids.count - capacity)
        }
    }
}

import Foundation

/// Tells the desktop widget that the status file changed.
///
/// The widget is deferred, so the app only has the no-op implementation for
/// now. When the widget is built, the live implementation calls
/// `WidgetCenter.shared.reloadAllTimelines()` here.
public protocol WidgetRefreshing {
    func refresh()
}

/// The implementation used until the widget exists.
public struct NoOpWidgetRefresher: WidgetRefreshing {
    public init() {}

    /// Does nothing. Replace with `WidgetCenter.shared.reloadAllTimelines()`
    /// when the desktop widget is added, and inject that implementation instead.
    public func refresh() {}
}

/// Reads and writes the status file of the App Group.
///
/// The directory is injected: the app passes `AppGroup.containerURL`, and falls
/// back to its own Application Support directory when the App Group is not
/// available (unsigned build, unit tests). The file is written atomically, so a
/// widget never reads a half-written file.
///
/// The status file holds no API Key: `StatusSnapshot` has no such field, and
/// this store writes nothing but the encoded snapshot.
public struct StatusFileStore {
    /// File name inside the directory, as agreed with the future widget.
    public static let fileName = "status.json"

    public let directory: URL
    private let refresher: WidgetRefreshing

    public init(directory: URL, refresher: WidgetRefreshing = NoOpWidgetRefresher()) {
        self.directory = directory
        self.refresher = refresher
    }

    /// The status file URL, whether it exists or not.
    public var fileURL: URL {
        directory.appendingPathComponent(Self.fileName)
    }

    /// Writes the snapshot with an atomic write and refreshes the widget.
    public func write(_ snapshot: StatusSnapshot) throws {
        let data = try Self.encoder.encode(snapshot)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        refresher.refresh()
    }

    /// Reads the status file, or returns `nil` when it does not exist yet.
    public func read() throws -> StatusSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try Self.decoder.decode(StatusSnapshot.self, from: data)
    }

    /// Removes the status file, for a "reset" action.
    public func remove() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    /// ISO 8601 dates, so a widget written in another language can read the file.
    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

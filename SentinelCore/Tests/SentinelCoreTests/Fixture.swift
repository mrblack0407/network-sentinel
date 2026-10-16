import Foundation
import XCTest
@testable import SentinelCore

/// Reads the anonymized JSON samples that live next to the tests.
enum Fixture {
    /// The URL of a fixture such as `sites.json` inside the test bundle.
    static func url(_ name: String) -> URL? {
        let fileName = name as NSString
        let base = fileName.deletingPathExtension
        let fileExtension = fileName.pathExtension
        return Bundle.module.url(forResource: base, withExtension: fileExtension, subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: "Fixtures/\(base)", withExtension: fileExtension)
    }

    static func data(_ name: String) throws -> Data {
        guard let url = url(name) else {
            throw FixtureError.missing(name)
        }
        return try Data(contentsOf: url)
    }

    static func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try JSONDecoder().decode(type, from: try data(name))
    }

    static func logPage(_ name: String) throws -> SystemLogPageResponse {
        try decode(SystemLogPageResponse.self, name)
    }

    /// Both log pages, page 0 first, exactly as the client returns them.
    static func allLogEntries() throws -> [SystemLogEntry] {
        try logPage("system-log-page0.json").data + logPage("system-log-page1.json").data
    }

    enum FixtureError: Error {
        case missing(String)
    }
}

extension SystemLogEntry {
    /// Builds an entry from a JSON object, for cases the samples do not cover.
    static func json(_ object: [String: Any]) throws -> SystemLogEntry {
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(SystemLogEntry.self, from: data)
    }
}

extension GatewayDevice {
    /// Builds a device from a JSON object, for cases the samples do not cover.
    static func json(_ object: [String: Any]) throws -> GatewayDevice {
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(GatewayDevice.self, from: data)
    }
}

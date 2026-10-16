import Foundation

/// One value of a log entry `parameters` dictionary.
///
/// The gateway is inconsistent here. A parameter is usually an object with `id`
/// and `name`, but it can also carry many other fields (`not_actionable`,
/// `hostname`, `model`, ...) or be a bare string or number. Decoding keeps only
/// `id` and `name` and never throws, so an unexpected value cannot break a page.
public struct LogParameter: Equatable {
    public let id: String?
    public let name: String?

    public init(id: String? = nil, name: String? = nil) {
        self.id = id
        self.name = name
    }

    /// The value used to fill a `{PLACEHOLDER}`: `name` first, then `id`.
    public var substitutionValue: String? {
        if let name, !name.isEmpty { return name }
        if let id, !id.isEmpty { return id }
        return nil
    }
}

extension LogParameter: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
    }

    public init(from decoder: Decoder) throws {
        var id: String?
        var name: String?

        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            id = container.sentinelString(forKey: .id)
            name = container.sentinelString(forKey: .name)
        } else if let container = try? decoder.singleValueContainer() {
            // Some parameters are plain strings or numbers instead of objects.
            name = container.sentinelString()
        }

        self.init(id: id, name: name)
    }
}

private extension KeyedDecodingContainer {
    /// Reads a string, tolerating numbers and booleans, and never throws.
    func sentinelString(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return String(value) }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return String(value) }
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return String(value) }
        return nil
    }
}

private extension SingleValueDecodingContainer {
    /// Reads a string, tolerating numbers and booleans, and never throws.
    func sentinelString() -> String? {
        if let value = try? decode(String.self) { return value }
        if let value = try? decode(Int.self) { return String(value) }
        if let value = try? decode(Double.self) { return String(value) }
        return nil
    }
}

/// Fills `{PLACEHOLDER}` tokens in the English log templates.
public enum LogTemplate {
    /// Replaces every `{NAME}` token with `parameters[NAME].substitutionValue`.
    ///
    /// A token without a matching parameter is kept as it was written.
    public static func render(_ template: String, parameters: [String: LogParameter]) -> String {
        guard template.contains("{") else { return template }

        var result = ""
        result.reserveCapacity(template.count)
        var remainder = Substring(template)

        while let open = remainder.firstIndex(of: "{") {
            guard let close = remainder[open...].firstIndex(of: "}") else { break }

            let token = remainder[remainder.index(after: open)..<close]
            result += remainder[remainder.startIndex..<open]

            if let value = parameters[String(token)]?.substitutionValue {
                result += value
            } else {
                result += remainder[open...close]
            }

            remainder = remainder[remainder.index(after: close)...]
        }

        result += remainder
        return result
    }
}

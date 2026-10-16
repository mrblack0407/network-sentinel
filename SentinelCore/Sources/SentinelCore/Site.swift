import Foundation

/// One site of the gateway, from `GET /proxy/network/integration/v1/sites`.
public struct Site: Decodable, Equatable, Identifiable {
    public let id: String
    /// The short site name used in the other URLs, currently `default`.
    public let internalReference: String
    public let name: String
}

/// The paged response of the sites endpoint.
public struct SiteListResponse: Decodable, Equatable {
    public let offset: Int
    public let limit: Int
    public let count: Int
    public let totalCount: Int
    public let data: [Site]
}

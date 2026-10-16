import Foundation

/// State of one WAN interface of the gateway.
public enum WANState: String, Codable {
    case online
    case offline
    case disabled

    /// Chinese display name for the app.
    public var displayName: String {
        switch self {
        case .online: return "在线"
        case .offline: return "离线"
        case .disabled: return "未启用"
        }
    }
}

/// One WAN interface of the gateway, for example WAN1.
public struct WANStatus: Equatable {
    /// `WAN1` or `WAN2`, derived from the gateway field name.
    public let id: String
    /// Interface name such as `eth9`.
    public let interfaceName: String?
    public let state: WANState
    public let ipAddress: String?
    public let portIndex: Int?
    /// Port media such as `SFP+` or `GE`.
    public let media: String?
    public let speedMbps: Int?
}

/// What the app shows about the gateway's internet connections.
public struct GatewayStatus: Equatable {
    public let name: String
    public let model: String
    public let firmwareVersion: String
    /// Gateway `type` as sent by the gateway: `udm`, `ugw` or `uxg`.
    public let deviceType: String
    /// WAN interfaces in gateway order, so WAN1 before WAN2.
    public let wanInterfaces: [WANStatus]

    public var wan1: WANStatus? { wanInterfaces.first { $0.id == "WAN1" } }
    public var wan2: WANStatus? { wanInterfaces.first { $0.id == "WAN2" } }
}

/// One device of the `stat/device` response.
///
/// Only gateway devices (`udm` / `ugw` / `uxg`) are of interest, but every
/// device of the page decodes, so a mixed page never fails.
public struct GatewayDevice: Decodable, Equatable {
    public let name: String
    public let model: String
    public let version: String
    public let type: String
    /// `last_wan_status` keyed by `WAN` (WAN1) and `WAN2`.
    public let lastWANStatus: [String: String]?
    public let wan1: WANInterface?
    public let wan2: WANInterface?

    /// Device types that are a UniFi gateway.
    public static let gatewayTypes: Set<String> = ["udm", "ugw", "uxg"]

    public var isGateway: Bool {
        Self.gatewayTypes.contains(type.lowercased())
    }

    /// The gateway view of this device.
    public var status: GatewayStatus {
        GatewayStatus(
            name: name,
            model: model,
            firmwareVersion: version,
            deviceType: type,
            wanInterfaces: [
                wanStatus(id: "WAN1", statusKey: "WAN", interface: wan1),
                wanStatus(id: "WAN2", statusKey: "WAN2", interface: wan2),
            ].compactMap { $0 }
        )
    }

    private func wanStatus(id: String, statusKey: String, interface: WANInterface?) -> WANStatus? {
        guard let interface else { return nil }

        let state: WANState
        if interface.enable == false {
            state = .disabled
        } else if let raw = lastWANStatus?[statusKey]?.trimmingCharacters(in: .whitespaces).lowercased() {
            state = (raw == "online") ? .online : .offline
        } else if let up = interface.up {
            state = up ? .online : .offline
        } else {
            state = .offline
        }

        return WANStatus(
            id: id,
            interfaceName: interface.name,
            state: state,
            ipAddress: interface.ip,
            portIndex: interface.portIndex,
            media: interface.media,
            speedMbps: interface.speed
        )
    }
}

extension GatewayDevice {
    private enum CodingKeys: String, CodingKey {
        case name
        case model
        case version
        case type
        case lastWANStatus = "last_wan_status"
        case wan1
        case wan2
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        model = (try? container.decode(String.self, forKey: .model)) ?? ""
        version = (try? container.decode(String.self, forKey: .version)) ?? ""
        type = (try? container.decode(String.self, forKey: .type)) ?? ""
        lastWANStatus = (try? container.decodeIfPresent([String: String].self, forKey: .lastWANStatus)) ?? nil

        let wan1Value: WANInterface? = (try? container.decodeIfPresent(WANInterface.self, forKey: .wan1)) ?? nil
        let wan2Value: WANInterface? = (try? container.decodeIfPresent(WANInterface.self, forKey: .wan2)) ?? nil
        wan1 = wan1Value
        wan2 = wan2Value
    }
}

/// One `wan1` / `wan2` object of a gateway device.
public struct WANInterface: Decodable, Equatable {
    public let name: String?
    public let up: Bool?
    public let enable: Bool?
    public let ip: String?
    public let portIndex: Int?
    public let media: String?
    public let speed: Int?

    private enum CodingKeys: String, CodingKey {
        case name
        case up
        case enable
        case ip
        case portIndex = "port_idx"
        case media
        case speed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? nil
        up = (try? container.decodeIfPresent(Bool.self, forKey: .up)) ?? nil
        enable = (try? container.decodeIfPresent(Bool.self, forKey: .enable)) ?? nil
        ip = (try? container.decodeIfPresent(String.self, forKey: .ip)) ?? nil
        portIndex = (try? container.decodeIfPresent(Int.self, forKey: .portIndex)) ?? nil
        media = (try? container.decodeIfPresent(String.self, forKey: .media)) ?? nil
        speed = (try? container.decodeIfPresent(Int.self, forKey: .speed)) ?? nil
    }
}

/// The `stat/device` response envelope.
struct StatDeviceResponse: Decodable {
    struct Meta: Decodable {
        let rc: String?
        let msg: String?
    }

    let meta: Meta?
    let data: [GatewayDevice]
}

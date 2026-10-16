import XCTest
@testable import SentinelCore

final class GatewayStatusTests: XCTestCase {
    func testSingleWANFixture() throws {
        let response = try Fixture.decode(StatDeviceResponse.self, "stat-device.json")
        let device = try XCTUnwrap(response.data.first { $0.isGateway })
        let status = device.status

        XCTAssertEqual(status.name, "Dream Machine Pro Max")
        XCTAssertEqual(status.model, "UDMPROMAX")
        XCTAssertEqual(status.firmwareVersion, "5.1.33.34087")
        XCTAssertEqual(status.deviceType, "udm")

        XCTAssertEqual(status.wanInterfaces.count, 1)
        XCTAssertEqual(status.wanInterfaces.map(\.id), ["WAN1"])
        XCTAssertNil(status.wan2)

        let wan1 = try XCTUnwrap(status.wan1)
        XCTAssertEqual(wan1.state, .online)
        XCTAssertEqual(wan1.state.displayName, "在线")
        XCTAssertEqual(wan1.ipAddress, "203.0.113.1")
        XCTAssertEqual(wan1.portIndex, 10)
        XCTAssertEqual(wan1.interfaceName, "eth9")
        XCTAssertEqual(wan1.media, "SFP+")
        XCTAssertEqual(wan1.speedMbps, 10_000)
    }

    func testDualWANFixture() throws {
        let response = try Fixture.decode(StatDeviceResponse.self, "stat-device-wan2.json")
        let device = try XCTUnwrap(response.data.first { $0.isGateway })
        let status = device.status

        XCTAssertEqual(status.wanInterfaces.count, 2)
        XCTAssertEqual(status.wanInterfaces.map(\.id), ["WAN1", "WAN2"])

        let wan1 = try XCTUnwrap(status.wan1)
        XCTAssertEqual(wan1.state, .online)
        XCTAssertEqual(wan1.ipAddress, "203.0.113.1")
        XCTAssertEqual(wan1.portIndex, 10)

        let wan2 = try XCTUnwrap(status.wan2)
        XCTAssertEqual(wan2.state, .online)
        XCTAssertEqual(wan2.ipAddress, "203.0.113.200")
        XCTAssertEqual(wan2.portIndex, 9)
        XCTAssertEqual(wan2.interfaceName, "eth8")
        XCTAssertEqual(wan2.media, "GE")
        XCTAssertEqual(wan2.speedMbps, 1_000)
    }

    func testDisabledWAN() throws {
        let device = try GatewayDevice.json([
            "name": "Gateway",
            "type": "udm",
            "last_wan_status": ["WAN": "online"],
            "wan1": ["enable": false, "up": true, "ip": "203.0.113.9"],
        ])

        XCTAssertEqual(device.status.wan1?.state, .disabled)
        XCTAssertEqual(WANState.disabled.displayName, "未启用")
    }

    func testOfflineWAN() throws {
        let device = try GatewayDevice.json([
            "name": "Gateway",
            "type": "uxg",
            "last_wan_status": ["WAN": "offline"],
            "wan1": ["enable": true, "up": true],
        ])

        XCTAssertEqual(device.status.wan1?.state, .offline)
        XCTAssertEqual(WANState.offline.displayName, "离线")
    }

    func testMissingLastWANStatusFallsBackToUp() throws {
        let up = try GatewayDevice.json(["type": "ugw", "wan1": ["enable": true, "up": true]])
        let down = try GatewayDevice.json(["type": "ugw", "wan1": ["enable": true, "up": false]])

        XCTAssertEqual(up.status.wan1?.state, .online)
        XCTAssertEqual(down.status.wan1?.state, .offline)
    }

    func testAllGatewayTypesAreRecognized() throws {
        for type in ["udm", "ugw", "uxg", "UDM"] {
            let device = try GatewayDevice.json(["type": type, "wan1": ["enable": true, "up": true]])
            XCTAssertTrue(device.isGateway, "\(type) should be a gateway")
        }

        let switchDevice = try GatewayDevice.json(["type": "usw", "name": "Switch"])
        XCTAssertFalse(switchDevice.isGateway)
    }

    func testNonGatewayDeviceHasNoWANs() throws {
        let device = try GatewayDevice.json(["type": "usw", "name": "Switch", "version": "7.0.1"])

        XCTAssertTrue(device.status.wanInterfaces.isEmpty)
        XCTAssertNil(device.status.wan1)
    }

    func testEmptyResponseHasNoGateway() throws {
        let response = try Fixture.decode(StatDeviceResponse.self, "error-404.json")

        XCTAssertEqual(response.meta?.rc, "error")
        XCTAssertEqual(response.meta?.msg, "api.err.NotFound")
        XCTAssertTrue(response.data.isEmpty)
        XCTAssertNil(response.data.first { $0.isGateway })
    }
}

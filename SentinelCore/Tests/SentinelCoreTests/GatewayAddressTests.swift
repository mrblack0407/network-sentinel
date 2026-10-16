import XCTest
@testable import SentinelCore

/// Address normalization: what the user types, and what the client gets.
final class GatewayAddressTests: XCTestCase {
    // MARK: - Happy paths

    func testBareIPv4GetsHTTPS() throws {
        let address = try GatewayAddress("192.168.8.254")

        XCTAssertEqual(address.host, "192.168.8.254")
        XCTAssertNil(address.port)
        XCTAssertEqual(address.urlString, "https://192.168.8.254")
    }

    func testTrailingSlashIsDropped() throws {
        XCTAssertEqual(try GatewayAddress("https://192.168.8.254/").urlString, "https://192.168.8.254")
        XCTAssertEqual(try GatewayAddress("https://192.168.8.254:8443/").urlString, "https://192.168.8.254:8443")
    }

    func testDefaultPortIsDropped() throws {
        let address = try GatewayAddress("https://192.168.8.254:443")

        XCTAssertNil(address.port)
        XCTAssertEqual(address.urlString, "https://192.168.8.254")
    }

    func testHostNameIsKeptAndLowercased() throws {
        let address = try GatewayAddress("unifi.local")

        XCTAssertEqual(address.host, "unifi.local")
        XCTAssertEqual(address.urlString, "https://unifi.local")
    }

    func testUpperCaseHostIsLowercased() throws {
        XCTAssertEqual(try GatewayAddress("HTTPS://UNIFI.LOCAL").urlString, "https://unifi.local")
    }

    func testHTTPIsTurnedIntoHTTPS() throws {
        XCTAssertEqual(try GatewayAddress("http://192.168.8.254").urlString, "https://192.168.8.254")
        XCTAssertEqual(try GatewayAddress("http://192.168.8.254/").urlString, "https://192.168.8.254")
    }

    func testCustomPortIsKept() throws {
        let address = try GatewayAddress("https://192.168.8.254:8443/")

        XCTAssertEqual(address.port, 8443)
        XCTAssertEqual(address.urlString, "https://192.168.8.254:8443")
    }

    func testPathAndQueryAreDroppedTogetherWithTheAddress() throws {
        // A path never belongs to a gateway address, so the input is rejected
        // instead of silently normalized to something else.
        XCTAssertThrowsError(try GatewayAddress("https://192.168.8.254/proxy/network")) { error in
            XCTAssertEqual(error as? GatewayAddressError, .invalid)
        }
        XCTAssertThrowsError(try GatewayAddress("https://192.168.8.254//")) { error in
            XCTAssertEqual(error as? GatewayAddressError, .invalid)
        }
        XCTAssertThrowsError(try GatewayAddress("https://192.168.8.254?foo=1")) { error in
            XCTAssertEqual(error as? GatewayAddressError, .invalid)
        }
        XCTAssertThrowsError(try GatewayAddress("https://192.168.8.254#top")) { error in
            XCTAssertEqual(error as? GatewayAddressError, .invalid)
        }
    }

    func testWhitespaceAroundTheAddressIsIgnored() throws {
        XCTAssertEqual(try GatewayAddress("  192.168.8.254  ").urlString, "https://192.168.8.254")
    }

    func testIPv6AddressKeepsItsBrackets() throws {
        let address = try GatewayAddress("[fd00::1]:8443")

        XCTAssertEqual(address.host, "fd00::1")
        XCTAssertEqual(address.displayHost, "[fd00::1]")
        XCTAssertEqual(address.urlString, "https://[fd00::1]:8443")
    }

    func testURLIsBuiltFromTheNormalizedText() throws {
        let address = try GatewayAddress("192.168.8.254:8443")

        XCTAssertEqual(address.url.absoluteString, "https://192.168.8.254:8443")
        XCTAssertEqual(address.url.host, "192.168.8.254")
    }

    // MARK: - Error paths

    func testEmptyInputIsRejected() {
        for input in ["", "   ", "\n"] {
            XCTAssertThrowsError(try GatewayAddress(input)) { error in
                XCTAssertEqual(error as? GatewayAddressError, .empty, "input: \(input.debugDescription)")
            }
        }
    }

    func testInnerWhitespaceIsRejected() {
        XCTAssertThrowsError(try GatewayAddress("192.168.8. 254")) { error in
            XCTAssertEqual(error as? GatewayAddressError, .invalid)
        }
        XCTAssertThrowsError(try GatewayAddress("192.168.8.254 8443")) { error in
            XCTAssertEqual(error as? GatewayAddressError, .invalid)
        }
    }

    func testNonHostInputIsRejected() {
        let inputs = [
            "gateway",                 // one label: not routable
            "192.168.8",               // incomplete IPv4 address
            "192.168.8.999",           // IPv4 octet out of range
            "192.168.8.254:0",         // port out of range
            "192.168.8.254:70000",     // port out of range
            "192.168.8.254:abc",       // port is not a number
            "192.168.8.254:",          // port is missing
            "-unifi.local",            // label may not start with a dash
            "unifi..local",            // empty label
            "unifi.local.",            // trailing dot
        ]

        for input in inputs {
            XCTAssertThrowsError(try GatewayAddress(input), "input: \(input)") { error in
                XCTAssertEqual(error as? GatewayAddressError, .invalid, "input: \(input)")
            }
        }
    }

    func testUnsupportedSchemeIsRejected() {
        XCTAssertThrowsError(try GatewayAddress("ftp://192.168.8.254")) { error in
            XCTAssertEqual(error as? GatewayAddressError, .invalid)
        }
    }

    func testChineseErrorTexts() {
        XCTAssertEqual(GatewayAddressError.empty.errorDescription, "请输入 UniFi 网关地址")
        XCTAssertEqual(
            GatewayAddressError.invalid.errorDescription,
            "地址格式不对，请输入网关的 IP 地址或主机名，例如 192.168.8.254"
        )
    }

    // MARK: - Input helper for the connection settings window

    func testInputHelperReturnsTheNormalizedAddress() {
        let input = GatewayAddressInput("https://192.168.8.254:443/")

        XCTAssertEqual(input.urlString, "https://192.168.8.254")
        XCTAssertEqual(input.address?.host, "192.168.8.254")
        XCTAssertNil(input.message)
    }

    func testInputHelperReturnsTheChineseMessage() {
        XCTAssertEqual(GatewayAddressInput("").message, "请输入 UniFi 网关地址")
        XCTAssertEqual(GatewayAddressInput("not-a-host").message, GatewayAddressError.invalid.errorDescription)
        XCTAssertNil(GatewayAddressInput("").urlString)
    }
}

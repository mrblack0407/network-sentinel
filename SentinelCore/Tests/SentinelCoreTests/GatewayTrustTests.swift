import Foundation
import XCTest
@testable import SentinelCore

/// Certificate fingerprinting, pinning and the accept / reject rule.
final class GatewayTrustTests: XCTestCase {
    private let gatewayHost = "192.168.8.254"
    // printf 'network-sentinel-trust-test' | shasum -a 256
    private let pinnedFingerprint = "f7ba5c80d600a7dd98578b683287373716d9afc04875f2d60f05b426ef7a500b"
    // printf 'hello' | shasum -a 256
    private let otherFingerprint = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"

    // MARK: - Secure hash

    func testSHA256OfFixedDERBytes() {
        // A short DER prefix, hashed with: printf '\x30\x82\x01\x0a\x02\x82' | shasum -a 256
        let der = Data([0x30, 0x82, 0x01, 0x0a, 0x02, 0x82])

        XCTAssertEqual(
            CertificateFingerprint.sha256(ofDER: der),
            "a1d8cb05a1a84ae0557a1b3ca3b05aeeebeb8eced52375e5aad9213f2e53b5fa"
        )
    }

    func testSHA256OfTextBytes() {
        // Hashed with: printf 'hello' | shasum -a 256
        XCTAssertEqual(
            CertificateFingerprint.sha256(ofDER: Data("hello".utf8)),
            otherFingerprint
        )
    }

    func testSHA256OfThePinnedTestVector() {
        // Hashed with: printf 'network-sentinel-trust-test' | shasum -a 256
        XCTAssertEqual(
            CertificateFingerprint.sha256(ofDER: Data("network-sentinel-trust-test".utf8)),
            pinnedFingerprint
        )
    }

    func testFingerprintIsLowercaseHexOf64Characters() {
        let fingerprint = CertificateFingerprint.sha256(ofDER: Data(repeating: 0xAB, count: 32))

        XCTAssertEqual(fingerprint.count, 64)
        XCTAssertEqual(fingerprint, fingerprint.lowercased())
        XCTAssertTrue(fingerprint.allSatisfy { $0.isHexDigit })
    }

    func testEmptyDERStillHasAFingerprint() {
        XCTAssertEqual(
            CertificateFingerprint.sha256(ofDER: Data()),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
    }

    // MARK: - Pinning rule

    func testMatchingFingerprintIsAccepted() {
        let decision = GatewayTrustPolicy.decision(
            host: gatewayHost,
            gatewayHost: gatewayHost,
            mode: .pinned(PinnedCertificate(host: gatewayHost, sha256: pinnedFingerprint)),
            fingerprint: pinnedFingerprint
        )

        XCTAssertEqual(decision, .accept(pinning: PinnedCertificate(host: gatewayHost, sha256: pinnedFingerprint)))
    }

    func testChangedFingerprintIsRejected() {
        let decision = GatewayTrustPolicy.decision(
            host: gatewayHost,
            gatewayHost: gatewayHost,
            mode: .pinned(PinnedCertificate(host: gatewayHost, sha256: pinnedFingerprint)),
            fingerprint: otherFingerprint
        )

        XCTAssertEqual(decision, .reject)
    }

    func testFirstUseAcceptsAndPinsWhateverTheGatewayShows() {
        let decision = GatewayTrustPolicy.decision(
            host: gatewayHost,
            gatewayHost: gatewayHost,
            mode: .firstUse,
            fingerprint: otherFingerprint
        )

        XCTAssertEqual(decision, .accept(pinning: PinnedCertificate(host: gatewayHost, sha256: otherFingerprint)))
    }

    func testAnotherHostIsLeftToTheSystem() {
        for mode in [
            GatewayTrustMode.firstUse,
            .pinned(PinnedCertificate(host: gatewayHost, sha256: pinnedFingerprint)),
        ] {
            let decision = GatewayTrustPolicy.decision(
                host: "example.com",
                gatewayHost: gatewayHost,
                mode: mode,
                fingerprint: otherFingerprint
            )

            XCTAssertEqual(decision, .systemDefault, "mode: \(mode)")
        }
    }

    func testHostComparisonIgnoresCase() {
        let decision = GatewayTrustPolicy.decision(
            host: "UNIFI.Local",
            gatewayHost: "unifi.local",
            mode: .firstUse,
            fingerprint: otherFingerprint
        )

        XCTAssertEqual(decision, .accept(pinning: PinnedCertificate(host: "unifi.local", sha256: otherFingerprint)))
    }

    func testUnknownFingerprintIsRejected() {
        let decision = GatewayTrustPolicy.decision(
            host: gatewayHost,
            gatewayHost: gatewayHost,
            mode: .firstUse,
            fingerprint: nil
        )

        XCTAssertEqual(decision, .reject)
    }

    // MARK: - Fingerprint value

    func testPinnedCertificateRoundTripsThroughJSON() throws {
        let pinned = PinnedCertificate(host: gatewayHost, sha256: pinnedFingerprint)

        let data = try JSONEncoder().encode(pinned)
        let decoded = try JSONDecoder().decode(PinnedCertificate.self, from: data)

        XCTAssertEqual(decoded, pinned)
        XCTAssertEqual(decoded.host, gatewayHost)
        XCTAssertEqual(decoded.sha256, pinnedFingerprint)
    }

    // MARK: - Delegate

    func testFirstUseHandshakeRecordsTheFingerprint() {
        let delegate = GatewayTrustDelegate(gatewayHost: gatewayHost, mode: .firstUse)

        let decision = delegate.simulateServerTrust(host: gatewayHost, fingerprint: pinnedFingerprint)

        XCTAssertEqual(decision, .accept(pinning: PinnedCertificate(host: gatewayHost, sha256: pinnedFingerprint)))
        XCTAssertEqual(delegate.observedCertificate?.sha256, pinnedFingerprint)
        XCTAssertEqual(delegate.observedCertificate?.host, gatewayHost)
    }

    func testFirstUseHandshakeReportsTheFingerprintToTheObserver() {
        var reported: [PinnedCertificate] = []
        let delegate = GatewayTrustDelegate(
            gatewayHost: gatewayHost,
            mode: .firstUse,
            observer: { reported.append($0) }
        )

        delegate.simulateServerTrust(host: gatewayHost, fingerprint: pinnedFingerprint)

        XCTAssertEqual(reported, [PinnedCertificate(host: gatewayHost, sha256: pinnedFingerprint)])
    }

    func testPinnedHandshakeRejectsAChangedCertificateAndPinsNothing() {
        let delegate = GatewayTrustDelegate(
            gatewayHost: gatewayHost,
            mode: .pinned(PinnedCertificate(host: gatewayHost, sha256: pinnedFingerprint))
        )

        let decision = delegate.simulateServerTrust(host: gatewayHost, fingerprint: otherFingerprint)

        XCTAssertEqual(decision, .reject)
        XCTAssertNil(delegate.observedCertificate)
    }

    func testAnotherHostIsNotHandled() {
        let delegate = GatewayTrustDelegate(gatewayHost: gatewayHost, mode: .firstUse)

        let decision = delegate.simulateServerTrust(host: "example.com", fingerprint: otherFingerprint)

        XCTAssertEqual(decision, .systemDefault)
        XCTAssertNil(delegate.observedCertificate)
    }

    // MARK: - Session factory

    func testSessionFactoryBuildsASessionWithTheDelegate() {
        let delegate = GatewayTrustDelegate(gatewayHost: gatewayHost, mode: .firstUse)

        let session = GatewayTrust.session(delegate: delegate)

        XCTAssertEqual(session.configuration.timeoutIntervalForRequest, 15)
        XCTAssertFalse(session.configuration.waitsForConnectivity)
        session.invalidateAndCancel()
    }
}

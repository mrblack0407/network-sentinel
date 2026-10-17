import SentinelCore
import SwiftUI

/// Which input field of the connection form is wrong.
///
/// 「测试连接」 draws the matching field with a red border; `none` is used for a
/// failure that is not the user's typing, for example a firmware without the
/// log endpoint.
enum ConnectionField: Equatable {
    case address
    case apiKey
    case none
}

/// Why the connection form shows a red status line.
///
/// The reason is kept as a case, not as a finished text: a language change
/// rewrites the status line like every other text of the app.
enum ConnectionFailureReason: Equatable {
    /// 测试连接 refused the gateway or the API Key.
    case connection(ConnectionTestError)
    /// The keychain holds no API Key for the configured gateway.
    case noStoredKey
    /// A text that is already finished, for example the keychain's own error.
    case text(String)

    /// Text of the status line in the current language.
    var message: String {
        switch self {
        case .connection(let error): return error.reason
        case .noStoredKey: return T(.settingsConnectionNoKey)
        case .text(let text): return text
        }
    }
}

/// What the connection form shows below its two fields.
enum ConnectionTestState: Equatable {
    /// Nothing tested yet.
    case idle
    /// 「测试连接」 is running.
    case testing
    /// The gateway answered everything.
    case success(gatewayName: String)
    /// The gateway or the API Key refused.
    case failure(reason: ConnectionFailureReason, field: ConnectionField)

    /// Shown before the first test.
    static var idleMessage: String { T(.connectionIdle) }

    var message: String {
        switch self {
        case .idle:
            return Self.idleMessage
        case .testing:
            return T(.connectionTesting)
        case .success(let gatewayName):
            return T(.connectionSuccess, gatewayName)
        case .failure(let reason, _):
            return reason.message
        }
    }

    var tone: StatusTone {
        switch self {
        case .idle: return .neutral
        case .testing: return .neutral
        case .success: return .ok
        case .failure: return .failure
        }
    }

    /// The field to outline red, when the failure is about the input.
    var field: ConnectionField? {
        guard case .failure(_, let field) = self else { return nil }
        return field
    }
}

extension ConnectionTestError {
    /// Which field the user has to look at for this reason.
    var field: ConnectionField {
        switch self {
        case .emptyAddress, .invalidAddress, .cannotConnect:
            return .address
        case .unauthorized:
            return .apiKey
        case .notSupported, .logNotSupported, .unreadableResponse, .gatewayRejected,
             .gatewayNotFound, .certificateUnavailable, .certificateChanged:
            // Neither field is wrong: the gateway or its firmware is.
            return .none
        }
    }

    /// Text of the status line.
    var reason: String {
        errorDescription ?? T(.connectionFailed)
    }
}

/// Runs one 「测试连接」 for a window.
@MainActor
enum ConnectionTestRunner {
    /// - Returns: the result to remember, or the reason to show.
    static func run(addressText: String, apiKey: String) async -> Result<ConnectionTestResult, ConnectionTestError> {
        do {
            return .success(try await ConnectionTester().test(addressText: addressText, apiKey: apiKey))
        } catch let error as ConnectionTestError {
            return .failure(error)
        } catch {
            return .failure(.unreadableResponse("unexpected failure"))
        }
    }
}

/// A rounded input box with a hairline border, red while its field is wrong.
struct ConnectionFieldBox<Content: View>: View {
    let isError: Bool
    let content: Content

    init(isError: Bool, @ViewBuilder content: () -> Content) {
        self.isError = isError
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, SentinelMetrics.inputHorizontalPadding)
            .padding(.vertical, SentinelMetrics.inputVerticalPadding)
            .background(SentinelColor.card, in: RoundedRectangle(cornerRadius: SentinelMetrics.inputCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: SentinelMetrics.inputCornerRadius)
                    .stroke(isError ? SentinelColor.failure : SentinelColor.controlBorder, lineWidth: 1)
            )
    }
}

/// The 「UniFi 网关地址」 field.
struct ConnectionAddressField: View {
    @Binding var text: String
    let isError: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(T(.connectionAddress))
                .font(.system(size: SentinelMetrics.cardBodyFontSize))
                .foregroundStyle(.secondary)

            ConnectionFieldBox(isError: isError) {
                TextField(T(.connectionAddressPlaceholder), text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: SentinelMetrics.inputFontSize, design: .monospaced))
            }
            .accessibilityLabel(T(.connectionAddress))
        }
    }
}

/// The 「API Key」 field, with 「显示」 to reveal what was pasted.
struct ConnectionAPIKeyField: View {
    @Binding var text: String
    @Binding var isRevealed: Bool
    let isError: Bool
    /// Hint below the field; the connection settings window has none.
    var showsHint: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("API Key")
                .font(.system(size: SentinelMetrics.cardBodyFontSize))
                .foregroundStyle(.secondary)

            ConnectionFieldBox(isError: isError) {
                HStack(spacing: 8) {
                    if isRevealed {
                        TextField(T(.connectionAPIKeyPlaceholder), text: $text)
                            .textFieldStyle(.plain)
                            .font(.system(size: SentinelMetrics.inputFontSize, design: .monospaced))
                    } else {
                        SecureField(T(.connectionAPIKeyPlaceholder), text: $text)
                            .textFieldStyle(.plain)
                            .font(.system(size: SentinelMetrics.inputFontSize, design: .monospaced))
                    }

                    Button(isRevealed ? T(.connectionHide) : T(.connectionShow)) {
                        isRevealed.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: SentinelMetrics.cardBodyFontSize))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel(isRevealed ? T(.connectionHideAPIKey) : T(.connectionShowAPIKey))
                }
            }
            .accessibilityLabel("API Key")

            if showsHint {
                Text(T(.connectionAPIKeyHint))
                    .font(.system(size: SentinelMetrics.footnoteFontSize))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The status line of a connection form: dot or spinner, then the message.
struct ConnectionStatusRow: View {
    let state: ConnectionTestState

    var body: some View {
        HStack(spacing: 7) {
            if state == .testing {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
                    .frame(width: 7, height: 7)
            } else {
                Circle()
                    .fill(state.tone.color)
                    .frame(width: SentinelMetrics.statusLineDotSize, height: SentinelMetrics.statusLineDotSize)
            }

            Text(state.message)
                .font(.system(size: SentinelMetrics.cardBodyFontSize))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 16, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(T(.connectionStatusReadOut, state.message))
    }
}

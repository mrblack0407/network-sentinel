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

/// What the connection form shows below its two fields.
enum ConnectionTestState: Equatable {
    /// Nothing tested yet.
    case idle
    /// 「测试连接」 is running.
    case testing
    /// The gateway answered everything.
    case success(gatewayName: String)
    /// The gateway or the API Key refused; `reason` is Chinese text.
    case failure(reason: String, field: ConnectionField)

    /// Shown before the first test.
    static let idleMessage = "填好后点「测试连接」"

    var message: String {
        switch self {
        case .idle:
            return Self.idleMessage
        case .testing:
            return "正在测试连接…"
        case .success(let gatewayName):
            return "已连上 \(gatewayName)，能读到网络和威胁日志"
        case .failure(let reason, _):
            return reason
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

    /// Chinese text for the status line.
    var reason: String {
        errorDescription ?? "测试连接失败"
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
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isError ? SentinelColor.failure : SentinelColor.border, lineWidth: 1)
            )
    }
}

/// The 「UniFi 网关地址」 field.
struct ConnectionAddressField: View {
    @Binding var text: String
    let isError: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("UniFi 网关地址")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            ConnectionFieldBox(isError: isError) {
                TextField("例如 https://192.168.1.1", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
            }
            .accessibilityLabel("UniFi 网关地址")
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
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            ConnectionFieldBox(isError: isError) {
                HStack(spacing: 8) {
                    if isRevealed {
                        TextField("粘贴 API Key", text: $text)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, design: .monospaced))
                    } else {
                        SecureField("粘贴 API Key", text: $text)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, design: .monospaced))
                    }

                    Button(isRevealed ? "隐藏" : "显示") {
                        isRevealed.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel(isRevealed ? "隐藏 API Key" : "显示 API Key")
                }
            }
            .accessibilityLabel("API Key")

            if showsHint {
                Text("在 UniFi 网页左侧边栏点「Integrations → Create New API Key」生成")
                    .font(.system(size: 11))
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
                    .frame(width: 7, height: 7)
            }

            Text(state.message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 16, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("连接状态：\(state.message)")
    }
}

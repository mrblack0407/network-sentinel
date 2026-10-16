import SentinelCore
import SwiftUI

/// 连接设置窗口: changes the UniFi gateway address and the API Key.
///
/// The window is a `.sheet` of 设置. 「保存」 waits for a 「测试连接」 inside this
/// window: the status line may already show the current connection, but saving
/// the same address and key again would be a no-op, so the button stays dim
/// until the gateway answered the two fields as they are now.
struct ConnectionSettingsSheet: View {
    @ObservedObject var configuration: AppConfiguration

    @Environment(\.dismiss) private var dismiss

    @State private var addressText: String
    @State private var apiKeyText: String
    @State private var isKeyRevealed = false
    @State private var state: ConnectionTestState
    @State private var pendingResult: ConnectionTestResult?

    init(configuration: AppConfiguration) {
        self.configuration = configuration

        let storedAddress = configuration.gatewayAddress?.urlString
        let storedKey: String = ((try? configuration.apiKey()) ?? nil) ?? ""

        _addressText = State(initialValue: storedAddress ?? "")
        _apiKeyText = State(initialValue: storedKey)

        if configuration.isConfigured, let gatewayName = configuration.gatewayName {
            // The current connection, as information; 「保存」 still waits for a
            // 「测试连接」 inside this window.
            _state = State(initialValue: .success(gatewayName: gatewayName))
        } else {
            _state = State(initialValue: .idle)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("连接 UniFi 网关")
                    .font(.system(size: SentinelMetrics.sheetTitleFontSize, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("在 UniFi 网页左侧边栏点「Integrations → Create New API Key」生成，复制过来。")
                    .font(.system(size: SentinelMetrics.cardBodyFontSize))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ConnectionAddressField(text: $addressText, isError: state.field == .address)
                .onChange(of: addressText) { _ in inputChanged() }

            ConnectionAPIKeyField(text: $apiKeyText, isRevealed: $isKeyRevealed, isError: state.field == .apiKey, showsHint: false)
                .onChange(of: apiKeyText) { _ in inputChanged() }

            ConnectionStatusRow(state: state)

            HStack(spacing: 8) {
                Button("测试连接") {
                    test()
                }
                .disabled(!canTest)

                Spacer()

                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("取消，不改动连接设置")

                Button("保存") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel("保存连接设置")
            }
            .padding(.top, 4)
        }
        .padding(SentinelMetrics.sheetPadding)
        .frame(width: SentinelMetrics.sheetWidth)
    }

    // MARK: - State

    private var canTest: Bool {
        state != .testing
            && !addressText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 保存 only after a test inside this window that matches the fields.
    private var canSave: Bool {
        guard case .success = state else { return false }
        return pendingResult != nil
    }

    // MARK: - Actions

    private func test() {
        let testedAddressText = addressText
        let testedAPIKey = apiKeyText
        state = .testing
        pendingResult = nil

        Task { @MainActor in
            let result = await ConnectionTestRunner.run(addressText: testedAddressText, apiKey: testedAPIKey)
            guard testedAddressText == addressText, testedAPIKey == apiKeyText else { return }

            switch result {
            case .success(let value):
                pendingResult = value
                state = .success(gatewayName: value.gatewayName)
            case .failure(let error):
                state = .failure(reason: error.reason, field: error.field)
            }
        }
    }

    private func save() {
        guard let pendingResult else { return }
        do {
            try configuration.saveConnection(result: pendingResult, apiKey: apiKeyText)
        } catch {
            state = .failure(reason: error.localizedDescription, field: .none)
            return
        }
        dismiss()
    }

    /// 改了输入就要重新测试.
    private func inputChanged() {
        guard state != .idle else { return }
        state = .idle
        pendingResult = nil
    }
}

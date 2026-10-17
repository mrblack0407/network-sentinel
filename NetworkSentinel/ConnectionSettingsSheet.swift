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
                Text(T(.connectionTitle))
                    .font(.system(size: SentinelMetrics.sheetTitleFontSize, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(T(.connectionAPIKeyHintLong))
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
                Button(T(.connectionTest)) {
                    test()
                }
                .disabled(!canTest)

                Spacer()

                Button(T(.connectionCancel)) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel(T(.connectionCancelReadOut))

                Button(T(.connectionSave)) {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel(T(.connectionSaveReadOut))
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
                state = .failure(reason: .connection(error), field: error.field)
            }
        }
    }

    private func save() {
        guard let pendingResult else { return }
        do {
            try configuration.saveConnection(result: pendingResult, apiKey: apiKeyText)
        } catch {
            state = .failure(reason: .text(error.localizedDescription), field: .none)
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

import AppKit
import SentinelCore
import SwiftUI

/// 首次启动窗口: the two pages shown before the app can monitor anything.
///
/// The window is 520 × 440 and both pages use the whole area, so the buttons do
/// not move when the user goes back and forth. `WindowCoordinator` owns the
/// `NSWindow`; closing it, or 「退出」, quits the app.
struct FirstLaunchWindow: View {
    @ObservedObject var configuration: AppConfiguration
    /// Called after the configuration was saved; the window turns into the 主窗口.
    let onFinish: () -> Void

    @State private var page: Page = .welcome
    @State private var addressText = ""
    @State private var apiKeyText = ""
    @State private var isKeyRevealed = false
    @State private var state: ConnectionTestState = .idle
    @State private var pendingResult: ConnectionTestResult?

    private enum Page {
        case welcome
        case connect
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch page {
            case .welcome:
                welcomePage
            case .connect:
                connectPage
            }
        }
        .padding(SentinelMetrics.welcomePadding)
        .padding(.top, SentinelMetrics.trafficLightsInset - 8)
        .frame(width: WindowCoordinator.firstLaunchSize.width, height: WindowCoordinator.firstLaunchSize.height)
        .background(GlassBackground())
    }

    // MARK: - Page 1

    private var welcomePage: some View {
        VStack(spacing: 14) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 136, height: 136)
                .accessibilityLabel("Network Sentinel App 图标")

            VStack(spacing: 2) {
                Text("欢迎使用 Network Sentinel")
                    .font(.system(size: SentinelMetrics.welcomeTitleFontSize, weight: .semibold))
                Text("for UniFi")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Text("先连上你的 UniFi 网关，才能开始监控断网和威胁日志。")
                .font(.system(size: SentinelMetrics.welcomeBodyFontSize))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            pageDots(current: 1)

            HStack(spacing: 8) {
                Button("退出") {
                    NSApp.terminate(nil)
                }
                .accessibilityLabel("退出 Network Sentinel")

                Spacer()

                Button("下一步") {
                    page = .connect
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel("下一步：填写 UniFi 网关地址和 API Key")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Page 2

    private var connectPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("连接 UniFi 网关")
                .font(.system(size: SentinelMetrics.welcomeTitleFontSize, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .center)

            ConnectionAddressField(text: $addressText, isError: state.field == .address)
                .onChange(of: addressText) { _ in inputChanged() }

            ConnectionAPIKeyField(text: $apiKeyText, isRevealed: $isKeyRevealed, isError: state.field == .apiKey)
                .onChange(of: apiKeyText) { _ in inputChanged() }

            ConnectionStatusRow(state: state)

            Spacer(minLength: 0)

            pageDots(current: 2)

            HStack(spacing: 8) {
                Button("上一步") {
                    page = .welcome
                }
                .accessibilityLabel("上一步：回到欢迎页")

                Spacer()

                Button("测试连接") {
                    test()
                }
                .disabled(!canTest)

                Button("开始使用") {
                    finish()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canFinish)
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel("开始使用，保存配置并打开主窗口")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Actions

    private var canTest: Bool {
        state != .testing
            && !addressText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 开始使用 is available only for a test that still matches the input.
    private var canFinish: Bool {
        guard pendingResult != nil, case .success = state else { return false }
        return true
    }

    /// Runs 「测试连接」 with what is typed right now.
    private func test() {
        let testedAddressText = addressText
        let testedAPIKey = apiKeyText
        state = .testing
        pendingResult = nil

        Task { @MainActor in
            let result = await ConnectionTestRunner.run(addressText: testedAddressText, apiKey: testedAPIKey)

            // The user may have typed on: the answer of the old input is dropped.
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

    /// Saves the tested configuration and hands over to the menu bar icon.
    private func finish() {
        guard let pendingResult else { return }

        do {
            try configuration.saveConnection(result: pendingResult, apiKey: apiKeyText)
        } catch {
            self.pendingResult = nil
            state = .failure(reason: error.localizedDescription, field: .none)
            return
        }

        onFinish()
    }

    /// 改了输入就要重新测试.
    private func inputChanged() {
        guard state != .idle else { return }
        state = .idle
        pendingResult = nil
    }

    // MARK: - Pieces

    private var appIcon: NSImage {
        NSApplication.shared.applicationIconImage
            ?? NSImage(named: "AppIcon")
            ?? NSImage(size: NSSize(width: 136, height: 136))
    }

    /// Two page dots, the current one in the label color.
    private func pageDots(current: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(1...2, id: \.self) { index in
                Circle()
                    .fill(index == current ? Color.primary : Color.secondary.opacity(0.28))
                    .frame(width: 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("第 \(current) 页，共 2 页")
    }
}

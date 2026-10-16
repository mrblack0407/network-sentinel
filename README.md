# Network Sentinel

**中文** | [English](README.en.md)

给 UniFi 用的 macOS 菜单栏 App。它用 API Key 读取 UniFi 网关的系统日志，发现互联网中断和安全威胁时提醒你，严重性和 UniFi 一样分为低、中、高、非常高四级。

> 状态：开发中，还没有可以下载的版本。

## 功能

- **菜单栏**：盾牌图标带一个状态点。近 24 小时有「中」或「高」的事件显示黄点，有「非常高」的事件或某条线路正在断网显示红点，连不上网关显示灰点。点开可以看到网关名、WAN1 / WAN2 的状态和最近的事件。
- **系统通知**：从你选的严重性开始弹通知。10 分钟内的同类事件合并成一条；线路恢复时会告诉你断了多久。
- **Bark 推送**：用 [Bark](https://github.com/Finb/Bark) 把同样的通知推到 iPhone，可以设自定义铃声，也可以用自建服务器。
- **主窗口**：概览页每条线路有一条 24 小时断网色条；日志页可以筛选、翻页、导出 CSV；还有通知和设置两页。
- **睡眠后补查**：Mac 醒来后马上补查一次，睡眠期间发生的事汇总成一条通知。

## 监控哪些事件

| 事件 | UniFi 日志 key |
|---|---|
| 互联网中断 | `NETWORK_WAN_FAILED_2` |
| 互联网已恢复 | `NETWORK_WAN_RESTORED_2` |
| 多次互联网中断 | `NETWORK_WAN_FAILED_MULTIPLE_TIMES_2` |
| 临时互联网中断 | `NETWORK_WAN_FAILED_TEMPORARY_2` |
| 检测到丢包 | `ISP_PACKET_LOSS_2` |
| 检测到高延迟 | `ISP_HIGH_LATENCY_2` |
| 检测到威胁 | category 为 `SECURITY` 的日志 |

每一类都可以单独开关。客户端上下线、设备事件不监控。

## 使用要求

- macOS 13 或更新版本
- 运行 UniFi Network 的 UniFi 网关（在 Dream Machine Pro Max、UniFi OS 5.1.33 上测试过）
- 一个 UniFi API Key：在 UniFi 网页左侧边栏点「Integrations → Create New API Key」生成

UniFi API Key 和 Bark Key 只存在 macOS 钥匙串里。第一次「测试连接」时，App 会记住网关自签证书的指纹，之后只接受这一张证书。

## 编译

```bash
brew install xcodegen
xcodegen generate
open NetworkSentinel.xcodeproj
```

用命令行编译：

```bash
xcodegen generate
xcodebuild -project NetworkSentinel.xcodeproj -scheme NetworkSentinel -configuration Debug -derivedDataPath build build
swift test --package-path SentinelCore
```

如果装了 Xcode，但 `xcode-select` 还指向 Command Line Tools，在命令前加上
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`，不用执行 `sudo xcode-select`。

核心逻辑放在本地 Swift 包 `SentinelCore/` 里，不编译 App 也能跑测试。工程文件由 XcodeGen 根据 `project.yml` 生成，不提交到仓库。

### App 图标

`NetworkSentinel/Assets.xcassets/AppIcon.appiconset` 由 `Design/Icons/AppIcon-Dark.svg` 生成。改了图标后重新运行：

```bash
./scripts/make-app-icon.sh
```

脚本先把 SVG 渲染成 1024×1024，再用 `sips` 缩放出 macOS 需要的各种尺寸。

## 许可证

MIT，见 [LICENSE](LICENSE)。

Network Sentinel 与 Ubiquiti Inc. 无关，也未经其认可。UniFi 是 Ubiquiti Inc. 的商标。

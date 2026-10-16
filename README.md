# Network Sentinel

**中文** | [English](README.en.md)

给 UniFi 用的 macOS 菜单栏 App：用 API Key 读取 UniFi 网关的系统日志，出现互联网中断或安全威胁时提醒你。

> 开发中，还没有可以下载的版本。

## 功能

- 菜单栏图标用颜色显示网络状态，点开可以看线路状态和最近事件
- 断网、恢复、丢包、高延迟、威胁等事件按 UniFi 的严重性弹系统通知
- 可以用 [Bark](https://github.com/Finb/Bark) 同步推送到 iPhone
- 主窗口有概览、日志（筛选、导出 CSV）、通知和设置

## 使用要求

- macOS 13 或更新版本，只支持 Apple 芯片（M 系列）的 Mac
- UniFi 网关和一个 UniFi API Key（在 UniFi 网页左侧边栏「Integrations → Create New API Key」生成）

## 编译

```bash
brew install xcodegen
xcodegen generate
open NetworkSentinel.xcodeproj
```

## 许可证

MIT。Network Sentinel 与 Ubiquiti Inc. 无关，UniFi 是 Ubiquiti Inc. 的商标。

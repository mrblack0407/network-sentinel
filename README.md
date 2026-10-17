# Network Sentinel

**中文** | [English](README.en.md)

给 UniFi 用的 macOS 菜单栏 App：用 API Key 读取 UniFi 网关的系统日志，出现互联网中断或安全威胁时提醒你。

## 下载

在 [Releases](https://github.com/mrblack0407/network-sentinel/releases) 下载 DMG，打开后把 Network Sentinel 拖进「应用程序」。

这个 App 没有 Apple 公证，第一次打开会被系统拦下：到「系统设置 → 隐私与安全性」，点「仍要打开」。

## 功能

- 菜单栏图标用颜色显示网络状态，点开可以看线路状态和最近事件
- 断网、恢复、丢包、高延迟、威胁等事件按 UniFi 的严重性弹系统通知
- 可以用 [Bark](https://github.com/Finb/Bark) 同步推送到 iPhone
- 主窗口有概览、日志（筛选、导出 CSV）、通知、界面（中英文、浅色 / 深色）和设置

## 使用要求

- macOS 15 或更新版本，只支持 Apple 芯片（M 系列）的 Mac
- UniFi 网关和一个 UniFi API Key（在 UniFi 网页左侧边栏「Integrations → Create New API Key」生成）

## 钥匙串对话框

API Key 和 Bark Key 存在 macOS 钥匙串里。钥匙串按 App 的签名认人：签名变了，就会弹出对话框，要你输入 Mac 登录密码。点「始终允许」，之后就不再问。

- 新安装：App 自己存的 Key，读取时不会弹。
- 从 v0.1 升级：v0.1 用的是临时签名，升级后会问一次。
- 之后的版本都用同一张自签证书签名，升级不再问。

## 编译

```bash
brew install xcodegen
xcodegen generate
open NetworkSentinel.xcodeproj
```

工程用自签证书「Network Sentinel Code Signing」签名。你的电脑上没有这张证书时，有两个办法：

- 运行 `scripts/make-signing-cert.sh <存放 p12 的文件夹>` 建一张同名证书。以后每次重新编译签名都不变，钥匙串只问一次。
- 编译时加 `CODE_SIGN_IDENTITY=-` 用临时签名。每次重新编译，钥匙串都会再问一次。

## 许可证

MIT。Network Sentinel 与 Ubiquiti Inc. 无关，UniFi 是 Ubiquiti Inc. 的商标。

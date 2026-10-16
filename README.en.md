# Network Sentinel

[中文](README.md) | **English**

A macOS menu bar app for UniFi: it reads your UniFi gateway's system log with an API Key and alerts you about internet outages and security threats.

> In development. Nothing to download yet.

## Features

- A menu bar icon that shows the network state; click it for the lines and the latest events
- System notifications for outages, restores, packet loss, high latency and threats, by UniFi severity
- Optional push to your iPhone through [Bark](https://github.com/Finb/Bark)
- A main window with an overview, the log (filters, CSV export), notifications and settings

## Requirements

- macOS 13 or later
- A UniFi gateway and a UniFi API Key (UniFi web UI → **Integrations** → **Create New API Key**)

## Build

```bash
brew install xcodegen
xcodegen generate
open NetworkSentinel.xcodeproj
```

## License

MIT. Network Sentinel is not affiliated with Ubiquiti Inc. UniFi is a trademark of Ubiquiti Inc.

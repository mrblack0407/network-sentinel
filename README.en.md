# Network Sentinel

[中文](README.md) | **English**

A macOS menu bar app for UniFi: it reads your UniFi gateway's system log with an API Key and alerts you about internet outages and security threats.

## Download

Download the DMG from [Releases](https://github.com/mrblack0407/network-sentinel/releases), open it and drag Network Sentinel into Applications.

The app is not notarized by Apple, so macOS blocks the first launch: open System Settings → Privacy & Security and click **Open Anyway**.

## Features

- A menu bar icon that shows the network state; click it for the lines and the latest events
- System notifications for outages, restores, packet loss, high latency and threats, by UniFi severity
- Optional push to your iPhone through [Bark](https://github.com/Finb/Bark)
- A main window with an overview, the log (filters, CSV export), notifications, interface (Chinese or English, light or dark) and settings
- A daily check of GitHub for a new version, shown as a note at the bottom of the sidebar (it only links to the release page and never installs an update)

## Requirements

- macOS 15 or later, on a Mac with Apple silicon (M-series) only
- A UniFi gateway and a UniFi API Key (UniFi web UI → **Integrations** → **Create New API Key**)

## Keychain dialog

The API Key and the Bark Key are stored in the macOS Keychain. The Keychain recognizes an app by its signature: when the signature changes, a dialog asks for your Mac login password. Click **Always Allow** and it will not ask again.

- New install: the app stored the keys itself, so reading them asks nothing.
- Upgrading from v0.1: v0.1 was ad-hoc signed, so the first launch after the upgrade asks once.
- Later versions are all signed with the same self-signed certificate, so upgrades do not ask.

## Build

```bash
brew install xcodegen
xcodegen generate
open NetworkSentinel.xcodeproj
```

The project is signed with the self-signed certificate "Network Sentinel Code Signing". If your Mac does not have it, either:

- Run `scripts/make-signing-cert.sh <folder for the p12>` to create a certificate with that name. Every rebuild then keeps the same signature and the Keychain asks only once.
- Build with `CODE_SIGN_IDENTITY=-` for ad-hoc signing. The Keychain then asks again after every rebuild.

## License

MIT. Network Sentinel is not affiliated with Ubiquiti Inc. UniFi is a trademark of Ubiquiti Inc.

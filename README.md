# Network Sentinel

A macOS menu bar app for UniFi. It reads your UniFi gateway's system log with an API Key and alerts you about internet outages and security threats, using the same severity levels UniFi shows (Low, Medium, High, Very High).

> Status: in development. Nothing to download yet.

## What it watches

| Event | UniFi log key |
|---|---|
| Internet Down | `NETWORK_WAN_FAILED_2` |
| Internet Restored | `NETWORK_WAN_RESTORED_2` |
| Multiple Internet Disconnections | `NETWORK_WAN_FAILED_MULTIPLE_TIMES_2` |
| Temporary Internet Disconnection | `NETWORK_WAN_FAILED_TEMPORARY_2` |
| Packet Loss Detected | `ISP_PACKET_LOSS_2` |
| High Latency Detected | `ISP_HIGH_LATENCY_2` |
| Threat Detected | category `SECURITY` |

Each one can be turned on or off. Client and device events are ignored.

## Requirements

- macOS 13 or later
- A UniFi gateway running UniFi Network (tested on Dream Machine Pro Max, UniFi OS 5.1.33)
- A UniFi API Key: in the UniFi web UI, open **Integrations** in the left sidebar and click **Create New API Key**

The API Key is stored in the macOS Keychain only.

## Build

```bash
brew install xcodegen
xcodegen generate
open NetworkSentinel.xcodeproj
```

## License

MIT. See [LICENSE](LICENSE).

Network Sentinel is not affiliated with or endorsed by Ubiquiti Inc. UniFi is a trademark of Ubiquiti Inc.

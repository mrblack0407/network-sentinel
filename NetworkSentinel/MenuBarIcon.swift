import AppKit
import SentinelCore
import SwiftUI

/// Draws the 菜单栏图标: the shield with the status dot of the last 24 hours.
///
/// The icon is not a template, so the dot keeps its color. The shield is drawn
/// in `NSColor.labelColor` when the image is drawn, which follows the light and
/// the dark menu bar. Each state is built once and kept: a new image only
/// appears when the color of the dot changes.
@MainActor
enum MenuBarIconRenderer {
    /// Size of the icon in points: the size of the shield asset.
    static let size = NSSize(width: 18, height: 18)

    /// Center of the dot in the coordinates of the asset (SVG, origin top left).
    private static let dotCenter = NSPoint(x: 4, y: 3.6)
    /// Radius of the dot in the mockup.
    private static let dotRadius: CGFloat = 2.6

    /// One image per state, built on the first draw of that state.
    private static var images: [MenuBarIndicatorState: NSImage] = [:]

    /// The icon of a state, built once and reused.
    static func image(for indicator: MenuBarIndicatorState) -> NSImage {
        if let image = images[indicator] {
            return image
        }
        let image = makeImage(for: indicator)
        images[indicator] = image
        return image
    }

    private static func makeImage(for indicator: MenuBarIndicatorState) -> NSImage {
        // The drawing handler runs on every draw, so an appearance change
        // recolors the shield without a new image.
        let image = NSImage(size: size, flipped: false) { rect in
            drawShield(in: rect)
            if let color = indicator.dotColor {
                color.setFill()
                NSBezierPath(ovalIn: dotRect(in: rect)).fill()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Draws the shield in the color of the current appearance.
    private static func drawShield(in rect: NSRect) {
        guard let shield = NSImage(named: "MenuBarIcon") else { return }

        shield.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        // Fill the rect with the label color, but only where the shield is: the
        // outline and the dissolved corner keep their alpha.
        NSColor.labelColor.set()
        rect.fill(using: .sourceAtop)
    }

    /// The dot in the drawing coordinates, where the origin is bottom left.
    private static func dotRect(in rect: NSRect) -> NSRect {
        let center = NSPoint(
            x: rect.minX + dotCenter.x,
            y: rect.maxY - dotCenter.y
        )
        return NSRect(
            x: center.x - dotRadius,
            y: center.y - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2
        )
    }
}

/// The label of the 菜单栏图标: the shield with the dot, and the text a screen
/// reader reads.
struct MenuBarIconLabel: View {
    @ObservedObject var configuration: AppConfiguration
    @ObservedObject var monitor: MonitorService

    var body: some View {
        let status = MenuBarStatusBuilder.status(
            gatewayName: monitor.gatewayStatus?.name ?? configuration.gatewayName,
            queryIntervalSeconds: configuration.monitorSettings.queryIntervalSeconds,
            connectionState: monitor.connectionState,
            errorDescription: monitor.lastErrorDescription,
            gatewayStatus: monitor.gatewayStatus,
            events: monitor.events,
            now: Date()
        )

        Image(nsImage: MenuBarIconRenderer.image(for: status.indicator))
            .renderingMode(.original)
            .accessibilityLabel(status.accessibilityText)
    }
}

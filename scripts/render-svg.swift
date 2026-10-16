// Render an SVG file to a square PNG using WebKit.
//
// Used by scripts/make-app-icon.sh. This is a build helper only: it is not part
// of the app target and adds no dependency to the project.
//
// Usage: render-svg.swift <input.svg> <output.png> <pixels>

import AppKit
import WebKit

let arguments = CommandLine.arguments
guard arguments.count == 4,
      let pixels = Int(arguments[3]), pixels > 0 else {
    FileHandle.standardError.write(Data("usage: render-svg.swift <input.svg> <output.png> <pixels>\n".utf8))
    exit(2)
}

let inputURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])
let side = CGFloat(pixels)

let svg: String
do {
    svg = try String(contentsOf: inputURL, encoding: .utf8)
} catch {
    FileHandle.standardError.write(Data("error: cannot read \(inputURL.path): \(error)\n".utf8))
    exit(1)
}

// Pin the drawing to the requested square, whatever the viewBox of the document.
let html = """
<!DOCTYPE html>
<html><head><meta charset="utf-8"><style>
html, body { margin: 0; padding: 0; background: transparent; }
svg { display: block; width: \(pixels)px; height: \(pixels)px; }
</style></head><body>\(svg)</body></html>
"""

final class Renderer: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private let outputURL: URL
    private let side: CGFloat

    init(outputURL: URL, side: CGFloat, svg: String) {
        self.outputURL = outputURL
        self.side = side
        // In-memory only: the renderer must not touch ~/Library caches.
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        self.webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: side, height: side),
            configuration: configuration
        )
        super.init()
        webView.navigationDelegate = self
        webView.loadHTMLString(svg, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let configuration = WKSnapshotConfiguration()
        configuration.rect = NSRect(x: 0, y: 0, width: side, height: side)
        configuration.snapshotWidth = NSNumber(value: Double(side))
        configuration.afterScreenUpdates = true

        webView.takeSnapshot(with: configuration) { [outputURL] image, error in
            guard let image,
                  let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else {
                let reason = error.map { "\($0)" } ?? "no image returned"
                FileHandle.standardError.write(Data("error: snapshot failed: \(reason)\n".utf8))
                exit(1)
            }
            do {
                try png.write(to: outputURL)
            } catch {
                FileHandle.standardError.write(Data("error: cannot write \(outputURL.path): \(error)\n".utf8))
                exit(1)
            }
            exit(0)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        FileHandle.standardError.write(Data("error: load failed: \(error)\n".utf8))
        exit(1)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        FileHandle.standardError.write(Data("error: load failed: \(error)\n".utf8))
        exit(1)
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)

let renderer = Renderer(outputURL: outputURL, side: side, svg: html)

// Give up rather than hang a build script.
DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
    FileHandle.standardError.write(Data("error: timed out rendering \(inputURL.path)\n".utf8))
    exit(1)
}

application.run()

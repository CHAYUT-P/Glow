import AppKit
import WebKit

// Renders an SVG file to a transparent-background PNG.
// Usage: swift svg-to-png.swift <in.svg> <out.png> <size>
// The SVG is rendered 1:1 into a <size>x<size> viewport on a transparent page.

let args = CommandLine.arguments
guard args.count == 4,
      let size = Int(args[3]) else {
    print("usage: svg-to-png <in.svg> <out.png> <size>")
    exit(1)
}
let svgURL = URL(fileURLWithPath: args[1])
let outURL = URL(fileURLWithPath: args[2])

let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: size, height: size))
webView.setValue(false, forKey: "drawsBackground")

var done = false
var snapped = false
webView.loadFileURL(svgURL, allowingReadAccessTo: svgURL.deletingLastPathComponent())

let deadline = Date().addingTimeInterval(30)
while !done && Date() < deadline {
    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    guard !snapped, !webView.isLoading, webView.url != nil else { continue }
    snapped = true
    webView.takeSnapshot(with: nil) { image, _ in
        defer { done = true }
        guard let image,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            print("snapshot failed")
            return
        }
        guard let outRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: rep.pixelsWide,
            pixelsHigh: rep.pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0),
            let ctx = NSGraphicsContext(bitmapImageRep: outRep) else {
            print("bitmap failed")
            return
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        image.draw(in: NSRect(x: 0, y: 0, width: outRep.pixelsWide, height: outRep.pixelsHigh))
        ctx.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        if let png = outRep.representation(using: .png, properties: [:]) {
            do {
                try png.write(to: outURL)
                print("wrote \(outURL.path) \(outRep.pixelsWide)x\(outRep.pixelsHigh)")
            } catch {
                print("write failed: \(error)")
            }
        }
    }
}
if !done {
    print("timeout or failed")
    exit(1)
}

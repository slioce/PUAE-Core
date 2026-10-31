// Renders the Amiga system's sidebar icon: a small grayscale Amiga 500, in the style of the installed
// system icons (e.g. psx_library: 16x16 @1x, 32x32 @2x, gray with a touch of color).
//
//   swift tools/make-icon.swift Amiga   (writes Amiga/amiga_library.png and amiga_library@2x.png)
import AppKit

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(pixels) / 16  // drawing in 16-unit space

    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        NSRect(x: x * s, y: y * s, width: w * s, height: h * s)
    }

    // Body: the A500 wedge, seen from the front.
    let body = NSBezierPath(roundedRect: rect(0.5, 3.5, 15, 9), xRadius: 1.2 * s, yRadius: 1.2 * s)
    NSGradient(starting: NSColor(white: 0.88, alpha: 1), ending: NSColor(white: 0.62, alpha: 1))!.draw(in: body, angle: -90)
    NSColor(white: 0.35, alpha: 1).setStroke()
    body.lineWidth = max(1, s * 0.6)
    body.stroke()

    // Keyboard: three rows of keys on the left, function keys on top.
    NSColor(white: 0.30, alpha: 1).setFill()
    for row in 0..<3 {
        let y = 5.0 + CGFloat(row) * 1.6
        for col in 0..<5 {
            rect(1.8 + CGFloat(col) * 1.6, y, 1.1, 1.0).fill()
        }
    }
    for col in 0..<4 {
        rect(1.8 + CGFloat(col) * 2.0, 10.2, 1.5, 0.7).fill()
    }

    // Floppy drive slot on the right, and the red power LED.
    NSColor(white: 0.20, alpha: 1).setFill()
    rect(10.6, 7.6, 3.8, 0.8).fill()
    NSColor(calibratedRed: 0.85, green: 0.15, blue: 0.12, alpha: 1).setFill()
    rect(12.9, 5.2, 1.3, 0.9).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Amiga"
try! render(pixels: 16).write(to: URL(fileURLWithPath: "\(dir)/amiga_library.png"))
try! render(pixels: 32).write(to: URL(fileURLWithPath: "\(dir)/amiga_library@2x.png"))

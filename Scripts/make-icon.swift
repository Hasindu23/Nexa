import AppKit
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let sizes = [16, 32, 64, 128, 256, 512, 1024]
for size in sizes {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size)
    NSColor(calibratedRed: 0.055, green: 0.07, blue: 0.065, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: s * 0.05, y: s * 0.05, width: s * 0.90, height: s * 0.90), xRadius: s * 0.205, yRadius: s * 0.205).fill()
    NSColor(calibratedRed: 0.6, green: 0.94, blue: 0.79, alpha: 0.12).setStroke()
    let border = NSBezierPath(roundedRect: NSRect(x: s * 0.052, y: s * 0.052, width: s * 0.896, height: s * 0.896), xRadius: s * 0.2, yRadius: s * 0.2)
    border.lineWidth = s * 0.006; border.stroke()
    NSColor(calibratedRed: 0.60, green: 0.94, blue: 0.79, alpha: 1).setStroke()
    for (x, h) in [(0.32, 0.23), (0.50, 0.43), (0.68, 0.23)] {
        let p = NSBezierPath(); p.lineWidth = s * 0.072; p.lineCapStyle = .round
        p.move(to: NSPoint(x: s * (x - h * 0.17), y: s * (0.5 + h / 2)))
        p.line(to: NSPoint(x: s * (x + h * 0.17), y: s * (0.5 - h / 2))); p.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("icon_\(size).png"))
}

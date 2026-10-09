// Basit plak ikonu üretir: swift tools/make-icon.swift Resources/AppIcon.iconset
import AppKit
let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
func draw(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px), m = s * 0.1
    let bg = NSBezierPath(roundedRect: NSRect(x: m, y: m, width: s - 2*m, height: s - 2*m), xRadius: s*0.18, yRadius: s*0.18)
    NSGradient(colors: [NSColor(red: 0.16, green: 0.84, blue: 0.38, alpha: 1), NSColor(red: 0.05, green: 0.45, blue: 0.25, alpha: 1)])!.draw(in: bg, angle: -90)
    let c = NSPoint(x: s/2, y: s/2), r = s*0.3
    NSColor(white: 0.08, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: c.x-r, y: c.y-r, width: 2*r, height: 2*r)).fill()
    NSColor(white: 1, alpha: 0.08).setStroke()
    for i in 1...5 { let rr = r*(0.95 - CGFloat(i)*0.09); let p = NSBezierPath(ovalIn: NSRect(x: c.x-rr, y: c.y-rr, width: 2*rr, height: 2*rr)); p.lineWidth = max(1, s*0.004); p.stroke() }
    NSColor(red: 0.16, green: 0.84, blue: 0.38, alpha: 1).setFill()
    let l = r*0.36; NSBezierPath(ovalIn: NSRect(x: c.x-l, y: c.y-l, width: 2*l, height: 2*l)).fill()
    NSColor.white.setFill()
    let h = r*0.07; NSBezierPath(ovalIn: NSRect(x: c.x-h, y: c.y-h, width: 2*h, height: 2*h)).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
for (name, px) in [("16x16",16),("16x16@2x",32),("32x32",32),("32x32@2x",64),("128x128",128),("128x128@2x",256),("256x256",256),("256x256@2x",512),("512x512",512),("512x512@2x",1024)] {
    try! draw(px).write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}

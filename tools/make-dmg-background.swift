// DMG penceresinin arka planını üretir (1x ve 2x PNG).
// swift tools/make-dmg-background.swift <çıktı klasörü> [--gatekeeper-ipucu]
import AppKit

let out = CommandLine.arguments[1]
let hint = CommandLine.arguments.contains("--gatekeeper-ipucu")
let W: CGFloat = 600, H: CGFloat = 380

func draw(scale: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Orta koyulukta zemin: Finder'ın simge yazıları açık modda siyah, koyu modda beyaz; ikisi de okunur
    NSGradient(colors: [NSColor(red: 0.13, green: 0.52, blue: 0.33, alpha: 1),
                        NSColor(red: 0.07, green: 0.34, blue: 0.24, alpha: 1)])!
        .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)

    func text(_ s: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat, centerY: CGFloat) {
        let style = NSMutableParagraphStyle(); style.alignment = .center
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 3; shadow.shadowOffset = NSSize(width: 0, height: -1)
        let attr = NSAttributedString(string: s, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: NSColor.white.withAlphaComponent(alpha),
            .paragraphStyle: style, .shadow: shadow,
        ])
        let h = attr.boundingRect(with: NSSize(width: W - 60, height: 200), options: [.usesLineFragmentOrigin]).height
        attr.draw(with: NSRect(x: 30, y: centerY - h / 2, width: W - 60, height: h), options: [.usesLineFragmentOrigin])
    }

    // y: AppKit'te alttan. Simgeler pencerede üstten 175'te → alttan 205.
    text("Mate Lyrics'i Uygulamalar klasörüne sürükle", size: 19, weight: .bold, alpha: 1, centerY: 330)

    // Ok: uygulama simgesinden Uygulamalar klasörüne
    let y: CGFloat = 215
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 262, y: y)); arrow.line(to: NSPoint(x: 334, y: y))
    arrow.move(to: NSPoint(x: 322, y: y + 11)); arrow.line(to: NSPoint(x: 336, y: y)); arrow.line(to: NSPoint(x: 322, y: y - 11))
    arrow.lineWidth = 4; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
    NSColor.white.withAlphaComponent(0.85).setStroke()
    arrow.stroke()

    if hint {
        text("İlk açılışta macOS uyarı verirse:\nSistem Ayarları › Gizlilik ve Güvenlik › en altta \"Yine de Aç\"",
             size: 12, weight: .medium, alpha: 0.85, centerY: 52)
    } else {
        text("Sonra Uygulamalar klasöründen Mate Lyrics'i aç", size: 12, weight: .medium, alpha: 0.85, centerY: 52)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
try! draw(scale: 1).write(to: URL(fileURLWithPath: "\(out)/dmg-bg.png"))
try! draw(scale: 2).write(to: URL(fileURLWithPath: "\(out)/dmg-bg@2x.png"))

import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let iconset = root.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func png(width: Int, height: Int, draw: () -> Void) throws -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

func drawIcon(_ pixels: Int) {
    let c = NSGraphicsContext.current!.cgContext
    c.scaleBy(x: CGFloat(pixels)/1024, y: CGFloat(pixels)/1024)
    let outer = NSBezierPath(roundedRect: NSRect(x: 68, y: 68, width: 888, height: 888), xRadius: 195, yRadius: 195)
    NSGradient(colors: [NSColor(red: 0.10, green: 0.48, blue: 0.58, alpha: 1),
                       NSColor(red: 0.55, green: 0.86, blue: 0.84, alpha: 1)])!.draw(in: outer, angle: 65)
    func card(_ rect: NSRect, _ glyph: String, alpha: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.14)
        shadow.shadowBlurRadius = 35; shadow.shadowOffset = NSSize(width: 0, height: -16); shadow.set()
        let path = NSBezierPath(roundedRect: rect, xRadius: 75, yRadius: 75)
        NSColor.white.withAlphaComponent(alpha).setFill(); path.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.8).setStroke(); path.lineWidth = 4; path.stroke()
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 210, weight: .medium),
                                                 .foregroundColor: NSColor(red: 0.08, green: 0.29, blue: 0.34, alpha: 0.85)]
        let text = glyph as NSString; let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: rect.midX-size.width/2, y: rect.midY-size.height/2), withAttributes: attrs)
    }
    card(NSRect(x: 170, y: 380, width: 400, height: 440), "A", alpha: 0.48)
    card(NSRect(x: 445, y: 185, width: 400, height: 440), "文", alpha: 0.78)
}
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size*scale
        let name = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
        try png(width: pixels, height: pixels, draw: { drawIcon(pixels) }).write(to: iconset.appendingPathComponent(name))
    }
}
let background = try png(width: 1080, height: 720) {
    let rect = NSRect(x: 0, y: 0, width: 1080, height: 720)
    NSGradient(colors: [NSColor(red: 0.93, green: 0.97, blue: 0.97, alpha: 1), .white])!.draw(in: rect, angle: 55)
    let centered = NSMutableParagraphStyle(); centered.alignment = .center
    ("轻译" as NSString).draw(in: NSRect(x: 0, y: 535, width: 1080, height: 70),
        withAttributes: [.font: NSFont.systemFont(ofSize: 38, weight: .semibold), .foregroundColor: NSColor.labelColor, .paragraphStyle: centered])
    ("拖入 Applications 即可安装" as NSString).draw(in: NSRect(x: 0, y: 94, width: 1080, height: 44),
        withAttributes: [.font: NSFont.systemFont(ofSize: 23, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: centered])
    let path = NSBezierPath(); path.move(to: NSPoint(x: 475, y: 320)); path.line(to: NSPoint(x: 605, y: 320))
    path.move(to: NSPoint(x: 581, y: 341)); path.line(to: NSPoint(x: 605, y: 320)); path.line(to: NSPoint(x: 581, y: 299))
    NSColor(red: 0.34, green: 0.52, blue: 0.55, alpha: 0.65).setStroke(); path.lineWidth = 4; path.stroke()
}
let dmgImage = NSBitmapImageRep(data: background)!
dmgImage.size = NSSize(width: 540, height: 360)
try dmgImage.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("dmg-background.png"))

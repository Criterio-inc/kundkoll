import AppKit

// Ritar Kundkolls appikon: petrolblå platta med ljudvåg och bock i vitt.
func rita(_ px: CGFloat) -> NSImage {
    let bild = NSImage(size: NSSize(width: px, height: px))
    bild.lockFocus()
    let s = px / 1024
    // macOS-ikoner har luft runt plattan: 824 av 1024.
    let marg: CGFloat = 100 * s
    let platta = NSRect(x: marg, y: marg, width: px - 2 * marg, height: px - 2 * marg)
    let väg = NSBezierPath(roundedRect: platta, xRadius: 185 * s, yRadius: 185 * s)
    // Skugga
    let skugga = NSShadow(); skugga.shadowBlurRadius = 24 * s; skugga.shadowOffset = NSSize(width: 0, height: -10 * s)
    skugga.shadowColor = NSColor.black.withAlphaComponent(0.28)
    NSGraphicsContext.saveGraphicsState(); skugga.set()
    NSColor(red: 0.08, green: 0.36, blue: 0.43, alpha: 1).setFill(); väg.fill()
    NSGraphicsContext.restoreGraphicsState()
    let grad = NSGradient(colors: [NSColor(red: 0.16, green: 0.58, blue: 0.66, alpha: 1),
                                   NSColor(red: 0.06, green: 0.30, blue: 0.38, alpha: 1)])!
    grad.draw(in: väg, angle: -70)
    // Glans upptill
    NSGraphicsContext.saveGraphicsState(); väg.addClip()
    let glans = NSGradient(colors: [NSColor.white.withAlphaComponent(0), NSColor.white.withAlphaComponent(0.14)])!
    glans.draw(in: platta, angle: 90)
    NSGraphicsContext.restoreGraphicsState()

    // Ljudvåg: fem staplar med rundade ändar, vänster halva.
    NSColor.white.setFill()
    let mitt = px / 2
    let höjder: [CGFloat] = [150, 300, 420, 260, 170]
    let bredd: CGFloat = 62 * s, steg: CGFloat = 96 * s
    let start = mitt - 2 * steg - 150 * s
    for (i, h) in höjder.enumerated() {
        let x = start + CGFloat(i) * steg - bredd / 2
        let r = NSRect(x: x, y: mitt - h * s / 2, width: bredd, height: h * s)
        NSBezierPath(roundedRect: r, xRadius: bredd / 2, yRadius: bredd / 2).fill()
    }
    // Bock: höger halva.
    let bock = NSBezierPath()
    bock.lineWidth = 74 * s; bock.lineCapStyle = .round; bock.lineJoinStyle = .round
    bock.move(to: NSPoint(x: mitt + 120 * s, y: mitt - 10 * s))
    bock.line(to: NSPoint(x: mitt + 215 * s, y: mitt - 110 * s))
    bock.line(to: NSPoint(x: mitt + 400 * s, y: mitt + 130 * s))
    NSColor.white.setStroke(); bock.stroke()
    bild.unlockFocus()
    return bild
}

func spara(_ bild: NSImage, _ px: Int, _ namn: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    bild.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "Kundkoll.iconset/\(namn)"))
}

try? FileManager.default.createDirectory(atPath: "Kundkoll.iconset", withIntermediateDirectories: true)
for (pt, skala) in [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)] {
    let px = pt * skala
    spara(rita(CGFloat(px)), px, "icon_\(pt)x\(pt)\(skala == 2 ? "@2x" : "").png")
}
print("ritat")

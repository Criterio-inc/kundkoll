import Foundation
import AppKit

enum Bildverktyg {
    /// Skalar ned till en kvadratisk jpeg för sigill. Beskär till mitten —
    /// ansikten sitter sällan i ett hörn.
    static func jpegSigill(_ data: Data, sida: CGFloat) -> Data? {
        guard let bild = NSImage(data: data) else { return nil }
        let källa = bild.size
        guard källa.width > 0, källa.height > 0 else { return nil }

        let kort = min(källa.width, källa.height)
        let urklipp = NSRect(x: (källa.width - kort) / 2,
                             y: (källa.height - kort) / 2,
                             width: kort, height: kort)

        let mål = NSImage(size: NSSize(width: sida, height: sida))
        mål.lockFocus()
        bild.draw(in: NSRect(x: 0, y: 0, width: sida, height: sida),
                  from: urklipp, operation: .copy, fraction: 1)
        mål.unlockFocus()

        guard let tiff = mål.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }
}

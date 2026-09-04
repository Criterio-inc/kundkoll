import Foundation
import AppKit

extension Tester {
    static func kontaktbilder() {
        Prov.svit("Kontaktbilder")
        let rot = FileManager.default.temporaryDirectory
            .appending(path: "kundkoll-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: rot) }
        let arkiv = Arkivet(rot: rot)
        let kund = try! arkiv.skapaKund(namn: "Acme")
        var k = Kontakt(namn: "Anna Svensson", epost: ["anna@acme.se"])
        try! arkiv.läggTill(k, hos: kund)

        // En liten riktig bild: 4×4 röda pixlar som png.
        let bild = NSImage(size: NSSize(width: 4, height: 4))
        bild.lockFocus(); NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill(); bild.unlockFocus()
        let png = NSBitmapImageRep(data: bild.tiffRepresentation!)!
            .representation(using: .png, properties: [:])!

        try! arkiv.sparaKontaktbild(png, för: &k, hos: kund)
        Prov.kolla(k.bild != nil, "bilden sparas och kontakten pekar på den")
        Prov.kolla(arkiv.kontaktbild(för: k, hos: kund) != nil, "och filen finns")
        Prov.lika(arkiv.kontakter(för: kund).first?.bild, k.bild,
                  "pekaren överlever omläsning")

        try! arkiv.taBortKontaktbild(för: &k, hos: kund)
        Prov.lika(k.bild, nil, "bilden går att ta bort")
        Prov.lika(arkiv.kontaktbild(för: k, hos: kund), nil, "och filen är borta")

        Prov.lika(Bildverktyg.jpegSigill(Data("smör".utf8), sida: 64), nil,
                  "det som inte är en bild ger inget sigill")
        let gammal = try? JSONDecoder.kundkoll.decode(
            Kontakt.self, from: Data(#"{"namn":"Bo Ek"}"#.utf8))
        Prov.lika(gammal?.bild, nil, "kontakter utan bildfält går att läsa")
    }
}

import Foundation

extension Tester {
    static func anteckningarMedObsidian() {
        Prov.svit("Anteckningar delade med Obsidian")

        do {
            let rot = FileManager.default.temporaryDirectory
                .appending(path: "kundkoll-test-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: rot) }
            let arkiv = Arkivet(rot: rot)
            let kund = try! arkiv.skapaKund(namn: "Acme")
            let a = try! arkiv.nyAnteckning(i: kund.anteckningsmapp, titel: "Möte")
            let läst = arkiv.anteckning(vid: a.fil)!

            // Vanlig sparning: ingen annan har rört filen.
            guard case .sparad(let s1) = try! arkiv.spara(läst, text: "# Möte\n\nMin text", lästÄndrad: läst.ändrad)
            else { Prov.kolla(false, "första sparningen skrivs"); return }
            Prov.lika(arkiv.anteckning(vid: a.fil)?.text, "# Möte\n\nMin text", "texten står på disk")

            // Obsidian skriver samma sak som appen just har: inget att göra.
            Thread.sleep(forTimeInterval: 1.1)
            try! "# Möte\n\nMin text".write(to: a.fil, atomically: true, encoding: .utf8)
            if case .redanSparad = try! arkiv.spara(s1, text: "# Möte\n\nMin text", lästÄndrad: s1.ändrad) {
                Prov.kolla(true, "samma text utifrån räknas som redan sparad")
            } else { Prov.kolla(false, "samma text utifrån räknas som redan sparad") }

            // Obsidian skriver något annat medan appen har egna ändringar.
            Thread.sleep(forTimeInterval: 1.1)
            try! "# Möte\n\nObsidians text".write(to: a.fil, atomically: true, encoding: .utf8)
            let utfall = try! arkiv.spara(s1, text: "# Möte\n\nAppens text", lästÄndrad: s1.ändrad)
            if case .ändradUtanför(let påDisk, let kopia) = utfall {
                Prov.lika(påDisk.text, "# Möte\n\nObsidians text", "filens version behålls")
                Prov.lika(arkiv.anteckning(vid: a.fil)?.text, "# Möte\n\nObsidians text", "och skrevs inte över")
                Prov.kolla(kopia.titel.hasSuffix("(min version)"), "den egna texten sparas bredvid: \(kopia.titel)")
                Prov.lika(arkiv.anteckning(vid: kopia.fil)?.text, "# Möte\n\nAppens text", "med appens text")
            } else {
                Prov.kolla(false, "en ändring utifrån med annat innehåll ger kollision")
            }
        }
    }
}

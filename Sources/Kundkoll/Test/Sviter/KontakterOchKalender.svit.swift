import Foundation

extension Tester {
    static func kontakterOchKalender() {
        Prov.svit("Kontakter och kalender")

        do {   // e-postmatchning
            let k = Kontakt(namn: "Anna", epost: ["Anna@Acme.se"])
            Prov.kolla(k.matchar(epost: "anna@acme.se"), "matchning bryr sig inte om skiftläge")
            Prov.kolla(k.matchar(epost: "Anna Svensson <anna@acme.se>"),
                       "adressen hittas även inbäddad i ett namn")
            Prov.kolla(!k.matchar(epost: "anna@annat.se"), "fel domän matchar inte")
        }

        do {   // domäner, med allmänna leverantörer bortsorterade
            let d = Kalendern.domäner(hos: [
                Kontakt(namn: "A", epost: ["a@acme.se"]),
                Kontakt(namn: "B", epost: ["b@gmail.com"]),
                Kontakt(namn: "C", epost: ["c@acme.se", "privat@hotmail.com"]),
            ])
            Prov.lika(d, ["acme.se"],
                      "gmail och hotmail räknas inte som kundens domän, annars matchar varje möte")
        }

        do {   // mötesmatchning
            let kund = Kund(namn: "Acme AB", mapp: URL(fileURLWithPath: "/tmp/Acme AB"))
            let kontakter = [Kontakt(namn: "Anna Svensson", epost: ["anna@acme.se"])]
            func möte(_ titel: String, _ deltagare: [(String, String?)]) -> Kalendern.Möte {
                Kalendern.Möte(id: UUID().uuidString, titel: titel, start: Date(),
                               slut: Date().addingTimeInterval(3600),
                               deltagare: deltagare.map {
                                   Kalendern.Deltagare(namn: $0.0, epost: $0.1, ärJag: false) },
                               plats: nil, möteslänk: nil)
            }
            Prov.kolla(Kalendern.hör(möte("Avstämning", [("Anna Svensson", "anna@acme.se")]),
                                     till: kund, kontakter: kontakter),
                       "möte med en känd kontakt hör till kunden")
            Prov.kolla(Kalendern.hör(möte("Uppstart", [("Bo Ek", "bo@acme.se")]),
                                     till: kund, kontakter: kontakter),
                       "okänd person på kundens domän räknas också")
            Prov.kolla(Kalendern.hör(möte("Möte med Acme AB", [("Cecilia", "c@annat.se")]),
                                     till: kund, kontakter: kontakter),
                       "kundnamnet i titeln räcker när adresser saknas")
            Prov.kolla(!Kalendern.hör(möte("Tandläkare", [("Tandvården", "info@tandlakaren.se")]),
                                      till: kund, kontakter: kontakter),
                       "ovidkommande möten sorteras bort")
        }

        do {   // deltagare som visas
            func möte(_ deltagare: [(String, Bool)]) -> Kalendern.Möte {
                Kalendern.Möte(id: "1", titel: "T", start: Date(), slut: Date(),
                               deltagare: deltagare.map {
                                   Kalendern.Deltagare(namn: $0.0, epost: nil, ärJag: $0.1) },
                               plats: nil, möteslänk: nil)
            }
            let m = möte([("Anders Bjarby", true), ("Kristin Sand Bakken", false)])
            Prov.lika(m.deltagare.filter { !$0.ärJag }.map(\.namn), ["Kristin Sand Bakken"],
                      "jag själv räknas inte som motpart i deltagarlistan")
        }

        do {   // kontakter sparas per kund och slås ihop
            let rot = FileManager.default.temporaryDirectory
                .appending(path: "kundkoll-test-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: rot) }
            let arkiv = Arkivet(rot: rot)
            let kund = try! arkiv.skapaKund(namn: "Acme")

            try! arkiv.läggTill(Kontakt(namn: "Anna Svensson", epost: ["anna@acme.se"]), hos: kund)
            Prov.lika(arkiv.kontakter(för: kund).count, 1, "kontakten sparas")

            // Samma person igen, från ett annat håll och med mer uppgifter
            try! arkiv.läggTill(Kontakt(namn: "Anna Svensson", roll: "VD",
                                        epost: ["anna.svensson@acme.se"],
                                        telefon: ["070-1234567"]), hos: kund)
            let alla = arkiv.kontakter(för: kund)
            Prov.lika(alla.count, 1, "samma namn ger inte en dubblett")
            Prov.lika(alla.first?.epost.count, 2, "adresserna slås ihop")
            Prov.lika(alla.first?.roll, "VD", "uppgifter som saknades fylls i")

            Prov.kolla(FileManager.default.fileExists(
                atPath: kund.kontaktmapp.appending(path: "Anna Svensson.md").path),
                       "kontakten får en not i vaultet")

            try! arkiv.taBort(alla.first!, hos: kund)
            Prov.lika(arkiv.kontakter(för: kund).count, 0, "kontakten går att ta bort")
        }

        do {   // redigering
            let rot = FileManager.default.temporaryDirectory
                .appending(path: "kundkoll-test-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: rot) }
            let arkiv = Arkivet(rot: rot)
            let kund = try! arkiv.skapaKund(namn: "Acme")
            try! arkiv.läggTill(Kontakt(namn: "Bo Ek"), hos: kund)

            var bo = arkiv.kontakter(för: kund).first!
            bo.roll = "Inköpschef"
            bo.epost = ["bo@acme.se", "bo.ek@acme.se"]
            bo.telefon = ["070-1234567"]
            try! arkiv.uppdatera(bo, hos: kund)

            let sparad = arkiv.kontakter(för: kund).first
            Prov.lika(sparad?.roll, "Inköpschef", "rollen sparas")
            Prov.lika(sparad?.epost.count, 2, "flera adresser sparas")
            Prov.lika(sparad?.telefon.first, "070-1234567", "telefonnumret sparas")

            let not = try! String(contentsOf: kund.kontaktmapp.appending(path: "Bo Ek.md"),
                                  encoding: .utf8)
            Prov.kolla(not.contains("roll: \"Inköpschef\""), "uppgifterna hamnar i frontmatter")
            Prov.kolla(not.contains("  - bo@acme.se"), "adresserna listas i frontmatter")
        }

        do {   // egna anteckningar i noten överlever en uppdatering
            let rot = FileManager.default.temporaryDirectory
                .appending(path: "kundkoll-test-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: rot) }
            let arkiv = Arkivet(rot: rot)
            let kund = try! arkiv.skapaKund(namn: "Acme")
            try! arkiv.läggTill(Kontakt(namn: "Cecilia Nord"), hos: kund)

            let not = kund.kontaktmapp.appending(path: "Cecilia Nord.md")
            var text = try! String(contentsOf: not, encoding: .utf8)
            text += "\nGillar att prata om segling. Ringer helst på förmiddagen.\n"
            try! text.write(to: not, atomically: true, encoding: .utf8)

            var c = arkiv.kontakter(för: kund).first!
            c.epost = ["cecilia@acme.se"]
            try! arkiv.uppdatera(c, hos: kund)

            let efter = try! String(contentsOf: not, encoding: .utf8)
            Prov.kolla(efter.contains("Gillar att prata om segling"),
                       "egna anteckningar skrivs inte över när uppgifter uppdateras")
            Prov.kolla(efter.contains("cecilia@acme.se"), "och de nya uppgifterna kommer med")
        }

        do {   // namnbyte
            let rot = FileManager.default.temporaryDirectory
                .appending(path: "kundkoll-test-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: rot) }
            let arkiv = Arkivet(rot: rot)
            let kund = try! arkiv.skapaKund(namn: "Acme")
            try! arkiv.läggTill(Kontakt(namn: "Eva Berg"), hos: kund)

            var eva = arkiv.kontakter(för: kund).first!
            eva.namn = "Eva Berg-Lund"
            try! arkiv.uppdatera(eva, hos: kund)

            let fm = FileManager.default
            Prov.kolla(fm.fileExists(atPath: kund.kontaktmapp.appending(path: "Eva Berg-Lund.md").path),
                       "noten följer med vid namnbyte")
            Prov.kolla(!fm.fileExists(atPath: kund.kontaktmapp.appending(path: "Eva Berg.md").path),
                       "den gamla noten lämnas inte kvar föräldralös")
            Prov.lika(arkiv.kontakter(för: kund).count, 1, "namnbyte skapar ingen dubblett")
        }

        do {   // frontmatter
            Prov.lika(Arkivet.utanFrontmatter("---\ntyp: kontakt\n---\n\n# Anna\n"),
                      "\n# Anna\n", "frontmatter skalas bort")
            Prov.lika(Arkivet.utanFrontmatter("# Anna\n"), "# Anna\n",
                      "filer utan frontmatter lämnas orörda")
            Prov.lika(Arkivet.utanFrontmatter("---\ntrasig utan slut\n"),
                      "---\ntrasig utan slut\n",
                      "en frontmatter utan avslutning rörs inte")
        }
    }
}

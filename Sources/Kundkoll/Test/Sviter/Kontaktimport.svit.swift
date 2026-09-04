import Foundation

extension Tester {
    static func kontaktimport() {
        Prov.svit("Kontaktimport")

        do {   // vCard, som Outlook skriver när man drar kontakter till Finder
            let vcf = """
            BEGIN:VCARD
            VERSION:3.0
            N:Svensson;Anna;;;
            FN:Anna Svensson
            ORG:Borås Stad
            TITLE:Enhetschef
            EMAIL;type=INTERNET;type=WORK;type=pref:Anna.Svensson@boras.example
            TEL;type=CELL;type=VOICE:+46 70 123 45 67
            END:VCARD
            BEGIN:VCARD
            VERSION:3.0
            N:;;;;
            FN:
            ORG:Bara ett bolag
            END:VCARD
            BEGIN:VCARD
            VERSION:3.0
            N:Ek;Bo;;;
            FN:Bo Ek
            EMAIL:bo@boras.example
            END:VCARD
            """
            let k = try! Kontaktimport.urVCard(Data(vcf.utf8))
            Prov.lika(k.map(\.namn), ["Anna Svensson", "Bara ett bolag", "Bo Ek"],
                      "tre poster i filens ordning: en organisation utan person får organisationens namn")
            Prov.lika(k[0].roll, "Enhetschef", "befattningen följer med")
            Prov.lika(k[0].epost, ["Anna.Svensson@boras.example"], "e-posten följer med")
            Prov.lika(k[0].telefon, ["+46 70 123 45 67"], "telefonen följer med")
        }

        do {   // CSV på engelska med komma, som Outlook på webben exporterar
            let csv = "\u{FEFF}First Name,Last Name,Title,Job Title,E-mail Address,E-mail 2 Address,Business Phone,Mobile Phone,Business Fax,Company\r\n"
                + "Anna,Svensson,Ms,Enhetschef,anna@boras.example,,033-35 70 00,070-123 45 67,033-1,Borås Stad\r\n"
                + "\"Ek, Bo\",,,,bo@boras.example,,,,,\r\n"
                + ",,,,,,,,,\r\n"
            let k = Kontaktimport.urCSV(Kontaktimport.text(ur: Data(csv.utf8)))
            Prov.lika(k.map(\.namn), ["Anna Svensson", "Ek, Bo"], "byteordningsmärket och den tomma raden stör inte")
            Prov.lika(k[0].roll, "Enhetschef", "«Job Title» är befattningen, «Title» är tilltalet")
            Prov.lika(k[0].epost, ["anna@boras.example"], "tomma e-postkolumner hoppas över")
            Prov.lika(k[0].telefon, ["033-35 70 00", "070-123 45 67"], "telefon och mobil, men inte fax")
            Prov.lika(k[1].namn, "Ek, Bo", "citerat komma i namnet klyver inte fältet")
        }

        do {   // CSV på svenska med semikolon, som Outlook för Windows exporterar
            let csv = "Förnamn;Efternamn;Titel;Befattning;E-postadress;Telefon, arbete;Mobiltelefon\n"
                + "Cecilia;Lund;Fru;Projektledare;cecilia@boras.example;;0701\n"
                + "Cecilia;Lund;;;Cecilia@Boras.example;0331;\n"
            let k = Kontaktimport.urCSV(csv)
            Prov.lika(k.count, 1, "samma person två gånger i filen blir en")
            Prov.lika(k[0].roll, "Projektledare", "svenska rubriker känns igen")
            Prov.lika(k[0].epost, ["cecilia@boras.example"], "samma adress med annat skiftläge dubbleras inte")
            Prov.lika(k[0].telefon, ["0701", "0331"], "telefonnumren läggs samman")
        }

        do {   // in i arkivet: dubbletter mot det som redan finns
            let rot = FileManager.default.temporaryDirectory
                .appending(path: "kundkoll-test-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: rot) }
            let arkiv = Arkivet(rot: rot)
            let kund = try! arkiv.skapaKund(namn: "Borås stad")
            try! arkiv.läggTill(Kontakt(namn: "Anna Svensson", epost: ["anna@boras.example"]), hos: kund)
            let utfall = try! arkiv.läggTill([
                Kontakt(namn: "A. Svensson", roll: "Enhetschef", epost: ["ANNA@boras.example"]),
                Kontakt(namn: "Bo Ek", epost: ["bo@boras.example"]),
                Kontakt(namn: "Bo Ek", telefon: ["0701"]),
            ], hos: kund)
            Prov.lika(utfall.nya, 1, "en ny person")
            Prov.lika(utfall.sammanslagna, 2, "två slogs ihop: en på e-post, en på namn")
            let alla = arkiv.kontakter(för: kund)
            Prov.lika(alla.map(\.namn), ["Anna Svensson", "Bo Ek"], "namnet som fanns behålls")
            Prov.lika(alla[0].roll, "Enhetschef", "befattningen fylldes på")
            Prov.lika(alla[1].telefon, ["0701"], "telefonen fylldes på")
            Prov.kolla(FileManager.default.fileExists(atPath: kund.kontaktmapp.appending(path: "Bo Ek.md").path),
                       "kontaktnoten skrevs")
        }

        do {   // filer: okänt format och tom fil
            let mapp = FileManager.default.temporaryDirectory
                .appending(path: "kundkoll-test-\(UUID().uuidString)")
            try! FileManager.default.createDirectory(at: mapp, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: mapp) }
            let xlsx = mapp.appending(path: "k.xlsx"); try! Data().write(to: xlsx)
            Prov.kolla((try? Kontaktimport.läs(xlsx)) == nil, "xlsx avvisas")
            let tom = mapp.appending(path: "k.csv"); try! Data("Namn,E-post\n".utf8).write(to: tom)
            Prov.kolla((try? Kontaktimport.läs(tom)) == nil, "en fil utan kontakter är ett fel, inte noll nya")
        }
    }
}

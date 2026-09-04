import Foundation

extension Tester {
    static func arkivet() {
        Prov.svit("Arkivet")
        let fm = FileManager.default

        do {   // mappstruktur och vault
            let (arkiv, rot) = tillfälligt()
            defer { try? fm.removeItem(at: rot) }
            let kund = try! arkiv.skapaKund(namn: "Åkessons Bygg AB")
            Prov.kolla(fm.fileExists(atPath: kund.projektmapp.path), "kunden får mappen Projekt")
            Prov.kolla(fm.fileExists(atPath: kund.samtalsmapp.path), "kunden får mappen Samtal")
            Prov.kolla(fm.fileExists(atPath: kund.kontaktmapp.path), "kunden får mappen Kontakter")
            Prov.kolla(fm.fileExists(atPath: kund.mailmapp.path), "kunden får mappen Mail")
            Prov.kolla(fm.fileExists(atPath: kund.mapp.appending(path: ".obsidian/app.json").path),
                       "mappen blir en Obsidian-vault")
            Prov.kolla(fm.fileExists(atPath: kund.mapp.appending(path: "Åkessons Bygg AB.md").path),
                       "vaultet får en ingångsnot")
        }

        do {   // svenska tecken
            let (arkiv, rot) = tillfälligt()
            defer { try? fm.removeItem(at: rot) }
            let kund = try! arkiv.skapaKund(namn: "Ängsö Trä & Rör")
            arkiv.läsOm()
            Prov.kolla(arkiv.kunder.contains { $0.namn == "Ängsö Trä & Rör" },
                       "å ä ö överlever vägen till disk och tillbaka")
            let md = try! String(contentsOf: kund.mapp.appending(path: "Ängsö Trä & Rör.md"), encoding: .utf8)
            Prov.kolla(md.contains("Ängsö Trä & Rör"), "å ä ö överlever i markdown")
        }

        do {   // farliga tecken
            let (arkiv, rot) = tillfälligt()
            defer { try? fm.removeItem(at: rot) }
            let kund = try! arkiv.skapaKund(namn: "Före/Efter AB")
            Prov.kolla(!kund.namn.contains("/"), "snedstreck skapar inte oavsiktliga undermappar")
            Prov.kolla(fm.fileExists(atPath: kund.mapp.path), "kunden skapas ändå")
        }

        do {   // läser det som skapats för hand
            let (arkiv, rot) = tillfälligt()
            defer { try? fm.removeItem(at: rot) }
            let förHand = rot.appending(path: "Handgjord AB/Projekt/Ombyggnad")
            try! fm.createDirectory(at: förHand, withIntermediateDirectories: true)
            arkiv.läsOm()
            let kund = arkiv.kunder.first { $0.namn == "Handgjord AB" }
            Prov.kolla(kund != nil, "kund skapad i Finder syns i appen")
            if let kund {
                Prov.lika(arkiv.projekt(för: kund).map(\.namn), ["Ombyggnad"],
                          "projekt skapat i Finder syns också")
            }
        }

        do {   // namnkollisioner
            let (arkiv, rot) = tillfälligt()
            defer { try? fm.removeItem(at: rot) }
            let kund = try! arkiv.skapaKund(namn: "Acme")
            let nu = Date()
            let a = try! arkiv.nyInspelningsmapp(placering: .kund(kund), titel: "Avstämning", datum: nu)
            let b = try! arkiv.nyInspelningsmapp(placering: .kund(kund), titel: "Avstämning", datum: nu)
            Prov.kolla(a != b, "två inspelningar samma minut skriver inte över varandra")
        }

        do {   // spara och läsa tillbaka
            let (arkiv, rot) = tillfälligt()
            defer { try? fm.removeItem(at: rot) }
            let kund = try! arkiv.skapaKund(namn: "Acme")
            _ = try! arkiv.skapaProjekt(namn: "Nytt lager", hos: kund)
            let mapp = try! arkiv.nyInspelningsmapp(placering: .kund(kund), titel: "Uppstart", datum: Date())
            let inspelning = Inspelning(
                titel: "Uppstart", inledd: Date(), längd: 92.5,
                kund: "Acme", projekt: "Nytt lager", mikrofon: "MacBook Pro-mikrofon",
                liveYttranden: [
                    Yttrande(röst: .jag, text: "Hej, hur går det med lagret?", start: 0, slut: 3),
                    Yttrande(röst: .motpart, text: "Det rullar på.", start: 3.2, slut: 5),
                ],
                arkivYttranden: nil)
            try! arkiv.spara(inspelning, i: mapp)

            let tillbaka = arkiv.inspelningar(för: kund)
            Prov.lika(tillbaka.count, 1, "sparad inspelning hittas igen")
            Prov.lika(tillbaka.first?.inspelning.yttranden.count, 2, "alla rader kommer med")

            let md = try! String(contentsOf: mapp.appending(path: "Transkript.md"), encoding: .utf8)
            Prov.kolla(md.contains("[[Acme]]"), "markdown länkar till kunden")
            Prov.kolla(md.contains("[[Nytt lager]]"), "markdown länkar till projektet")
            Prov.kolla(md.contains("**Jag** `00:00`"), "rader får talare och tidsstämpel")
            Prov.kolla(md.contains("Det rullar på."), "texten finns i markdown")
        }

        do {   // kasta en inspelning
            let rot = FileManager.default.temporaryDirectory
                .appending(path: "kundkoll-test-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: rot) }
            let arkiv = Arkivet(rot: rot)
            let kund = try! arkiv.skapaKund(namn: "Acme")
            let mapp = try! arkiv.nyInspelningsmapp(placering: .kund(kund),
                                                    titel: "Att kasta", datum: Date())
            let i = Inspelning(titel: "Att kasta", inledd: Date(), längd: 5,
                               kund: "Acme", projekt: nil, mikrofon: nil,
                               liveYttranden: [], arkivYttranden: nil)
            try! arkiv.spara(i, i: mapp)
            // Ljudfilerna ska följa med, inte lämnas kvar
            FileManager.default.createFile(atPath: mapp.appending(path: "jag.wav").path,
                                           contents: Data([1, 2, 3]))
            Prov.lika(arkiv.inspelningar(för: kund).count, 1, "inspelningen finns")

            try! arkiv.kastaInspelning(i: mapp)
            Prov.lika(arkiv.inspelningar(för: kund).count, 0, "den försvinner ur listan")
            Prov.kolla(!FileManager.default.fileExists(atPath: mapp.path),
                       "hela mappen är borta, med ljud och transkript")
        }

        do {   // arkiv går före live
            var i = Inspelning(titel: "T", inledd: Date(), längd: 10, kund: "K", projekt: nil, mikrofon: nil,
                               liveYttranden: [Yttrande(röst: .jag, text: "live", start: 0, slut: 1)],
                               arkivYttranden: nil)
            Prov.lika(i.yttranden.first?.text, "live", "live-transkriptet visas innan efterbearbetning")
            i.arkivYttranden = [Yttrande(röst: .jag, text: "arkiv", start: 0, slut: 1)]
            Prov.lika(i.yttranden.first?.text, "arkiv", "arkivtranskriptet tar över när det finns")
            Prov.kolla(i.efterbearbetad, "inspelningen räknas som efterbearbetad")
        }
    }
}

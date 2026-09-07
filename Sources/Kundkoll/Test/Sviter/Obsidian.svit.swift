import Foundation

extension Tester {
    static func obsidian() {
        Prov.svit("Obsidian")
        // Sökvägar med å ä ö och mellanslag måste överleva kodningen
        let c = CharacterSet.urlQueryValueAllowed
        Prov.kolla(!c.contains(Unicode.Scalar("/")), "snedstreck kodas i sökvägen")
        Prov.kolla(!c.contains(Unicode.Scalar("&")), "och-tecken kodas")
        let kodad = "/Users/a/Documents/Kunder/Ängsö Trä/Anteckningar/Möte.md"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed)
        Prov.kolla(kodad != nil, "sökvägen går att koda")
        Prov.kolla(kodad?.contains("%2F") == true, "snedstrecken är kodade")
        Prov.kolla(URL(string: "obsidian://open?path=\(kodad ?? "")") != nil,
                   "resultatet blir en giltig URL")
    }
}

extension Tester {
    static func obsidianSpegling() {
        Prov.svit("Speglingen i Obsidian")
        let (arkiv, rot) = tillfälligt()
        defer { try? FileManager.default.removeItem(at: rot) }
        let kund = try! arkiv.skapaKund(namn: "Acme")
        let sida = kund.mapp.appending(path: "Acme.md")
        func text() -> String { (try? String(contentsOf: sida, encoding: .utf8)) ?? "" }

        Prov.kolla(text().contains(Arkivet.blockstart), "kundsidan får ett block redan när kunden skapas")
        Prov.kolla(text().contains("Inga projekt än."), "och säger att projekt saknas")
        Prov.kolla(!text().contains("## Projekt\n\n## Kontakter"), "de tomma rubrikerna ur mallen är borta")

        let projekt = try! arkiv.skapaProjekt(namn: "Nytt lager", hos: kund)
        Prov.kolla(text().contains("[[Projekt/Nytt lager/Nytt lager|Nytt lager]]"), "projektet länkas med sökväg och namn")
        try! arkiv.läggTill(Kontakt(namn: "Anna Svensson", roll: "IT-chef"), hos: kund)
        Prov.kolla(text().contains("[[Kontakter/Anna Svensson|Anna Svensson]] · IT-chef"), "kontakten länkas till sin not, med roll")

        // Eget skrivet utanför blocket står kvar.
        try! (text() + "\nMina egna rader om Acme.\n").write(to: sida, atomically: true, encoding: .utf8)
        try! arkiv.läggTill(Kontakt(namn: "Bo Ek"), hos: kund)
        Prov.kolla(text().contains("Mina egna rader om Acme.") && text().contains("[[Kontakter/Bo Ek|Bo Ek]]"),
                   "egen text utanför markörerna rörs inte när blocket skrivs om")
        Prov.lika(text().components(separatedBy: Arkivet.blockstart).count, 2, "blocket finns en gång")

        // Anteckning i projektet syns på båda sidorna.
        try! FileManager.default.createDirectory(at: projekt.anteckningsmapp, withIntermediateDirectories: true)
        let not = Anteckning(titel: "Dagbok", text: "x", ändrad: Date(), fil: projekt.anteckningsmapp.appending(path: "Dagbok.md"))
        try! arkiv.spara(not)
        Prov.kolla(text().contains("[[Projekt/Nytt lager/Anteckningar/Dagbok|Dagbok]]") && text().contains("· Nytt lager"),
                   "projektets anteckning står på kundsidan med projektet")
        let projektsida = (try? String(contentsOf: projekt.mapp.appending(path: "Nytt lager.md"), encoding: .utf8)) ?? ""
        Prov.kolla(projektsida.contains("[[Projekt/Nytt lager/Anteckningar/Dagbok|Dagbok]]") && projektsida.contains("[[Acme]]"),
                   "och på projektsidan, som fortfarande länkar till kunden")

        // Att göra.md länkar till källan när den finns i valvet.
        try! arkiv.sparaUppgifter([
            Uppgift(vad: "Beställ hyllor", ursprung: .anteckning, källa: "Projekt/Nytt lager/Anteckningar/Dagbok.md", källtitel: "Dagbok"),
            Uppgift(vad: "Ring Bo", ursprung: .möte, källa: "Samtal/2026-09-01 0900 Möte", källtitel: "Möte"),
            Uppgift(vad: "Svara", när: "som det stod, eller null", ursprung: .mejl, källtitel: "Sv: offert"),
        ], för: kund)
        let attGöra = (try? String(contentsOf: kund.mapp.appending(path: "Att göra.md"), encoding: .utf8)) ?? ""
        Prov.kolla(attGöra.contains("[[Projekt/Nytt lager/Anteckningar/Dagbok|Dagbok]]"), "ett kort ur en anteckning länkar till den")
        Prov.kolla(attGöra.contains("[[Samtal/2026-09-01 0900 Möte/Transkript|Möte]]"), "ett kort ur ett möte länkar till transkriptet")
        Prov.kolla(attGöra.contains("— Sv: offert") && !attGöra.contains("[[Sv: offert"), "ett kort ur ett mejl har bara ämnesraden")
        Prov.kolla(text().contains("[[Att göra]] · 3 att göra"), "kundsidan räknar korten")
        Prov.lika(arkiv.uppgifter(för: kund).first { $0.vad == "Svara" }?.när, nil,
                  "mallens «som det stod, eller null» rensas bort ur kortet")
        Prov.lika(Modellsvar.tomSomNil("ÅÅÅÅ-MM-DD eller null"), nil, "och ur modellens svar")
    }
}

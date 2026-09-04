import Foundation

extension Tester {
    /// Ett projekt som byter namn i Finder ska behålla sina kort, sin tid,
    /// sina samtal, sina möten, sin lägesbild och sina kalenderkopplingar.
    static func namnbyte() {
        Prov.svit("Projekt som byter namn")
        let rot = FileManager.default.temporaryDirectory
            .appending(path: "kundkoll-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: rot) }
        let fm = FileManager.default
        let arkiv = Arkivet(rot: rot)
        let kund = try! arkiv.skapaKund(namn: "Acme")
        let projekt = try! arkiv.skapaProjekt(namn: "Nytt lager", hos: kund)

        do {   // id:t bor i mappen och står sig
            Prov.kolla(fm.fileExists(atPath: projekt.mapp.appending(path: ".kundkoll/projekt.json").path),
                       "projektet får en id-fil i sin mapp")
            Prov.lika(arkiv.projekt(för: kund).first?.id, projekt.id, "samma id vid nästa läsning")
            let iFinder = kund.projektmapp.appending(path: "Gjord i Finder")
            try! fm.createDirectory(at: iFinder, withIntermediateDirectories: true)
            let p2 = arkiv.projekt(för: kund).first { $0.namn == "Gjord i Finder" }
            Prov.kolla(p2 != nil && !p2!.id.isEmpty && p2!.id != projekt.id,
                       "en mapp gjord i Finder får ett eget id första gången appen ser den")
        }

        // Gammalt format på disk: kort, tid och samtal med projektets namn men utan id,
        // en källa med hel sökväg, en koppling med namnet och en lägesbild med namnet i filnamnet.
        let mötesmapp = projekt.inspelningsmapp.appending(path: "2026-09-01 0900 Byggmöte")
        try! fm.createDirectory(at: mötesmapp, withIntermediateDirectories: true)
        let inspelning = Inspelning(titel: "Byggmöte", inledd: Uppgift.dag("2026-09-01")!, längd: 60,
                                    kund: "Acme", projekt: "Nytt lager", mikrofon: nil,
                                    liveYttranden: [], arkivYttranden: nil)
        try! JSONEncoder.kundkoll.encode(inspelning).write(to: mötesmapp.appending(path: "möte.json"))
        try! Data(#"[{"vad":"Beställ hyllor","projekt":"Nytt lager","ursprung":"möte","källa":"\#(mötesmapp.path)"}]"#.utf8)
            .write(to: kund.mapp.appending(path: "uppgifter.json"))
        try! Data(#"[{"vad":"Ritade","projekt":"Nytt lager","sekunder":3600}]"#.utf8)
            .write(to: kund.mapp.appending(path: "tid.json"))
        try! arkiv.spara(Samtal(projekt: "Nytt lager", meddelanden: [.init(roll: .människa, text: "Hur går bygget?")]), för: kund)
        try! fm.createDirectory(at: kund.mapp.appending(path: ".kundkoll"), withIntermediateDirectories: true)
        try! Data(#"{"m1":"Nytt lager"}"#.utf8).write(to: kund.mapp.appending(path: ".kundkoll/möteskopplingar.json"))
        try! JSONEncoder.kundkoll.encode(Lägesbild(text: "Bygget går bra", skriven: Date(), modell: nil))
            .write(to: kund.mapp.appending(path: ".kundkoll/läget-Nytt lager.json"))
        var rundor = Uppgiftssamling.Rundor()
        rundor.anteckningar[projekt.anteckningsmapp.appending(path: "Dagbok.md").path] = "abc"
        Uppgiftssamling.spara(rundor, kund)

        do {   // det gamla formatet knyts till id:t vid första läsningen
            let u = arkiv.uppgifter(för: kund).first!
            Prov.lika(u.projektID, projekt.id, "kortets projektnamn ger kortet sitt id")
            Prov.lika(u.källa, "Projekt/Nytt lager/Inspelningar/2026-09-01 0900 Byggmöte",
                      "källan blir relativ kundmappen")
            Prov.kolla(u.kommer(ur: mötesmapp), "och känns fortfarande igen som mötets")
            Prov.lika(arkiv.tidsposter(för: kund).first?.projektID, projekt.id, "tidsposten likaså")
            Prov.lika(arkiv.samtal(för: kund, projekt: projekt).first?.projektID, projekt.id, "samtalet likaså")
            Prov.lika(arkiv.möteskopplingar(för: kund)["m1"], projekt.id, "kalenderkopplingen byter namn mot id")
            Prov.kolla(Läget.läs(kund: kund, projekt: projekt)?.text == "Bygget går bra",
                       "lägesbilden hittas och filen döps om efter id:t")
            Prov.kolla(Uppgiftssamling.rundor(kund).anteckningar["Projekt/Nytt lager/Anteckningar/Dagbok.md"] == "abc",
                       "bokföringen över genomgångna anteckningar blir relativ")
        }

        // Namnbytet, som i Finder.
        let nyMapp = kund.projektmapp.appending(path: "Lagret i Viared")
        try! fm.moveItem(at: projekt.mapp, to: nyMapp)

        do {
            let omdöpt = arkiv.projekt(för: kund).first { $0.namn == "Lagret i Viared" }
            Prov.lika(omdöpt?.id, projekt.id, "projektet har samma id efter namnbytet")
            guard let omdöpt else { return }
            let u = arkiv.uppgifter(för: kund).first!
            Prov.lika(u.projekt, "Lagret i Viared", "kortet visar det nya namnet")
            Prov.lika(u.projektID, omdöpt.id, "och pekar fortfarande på projektet")
            Prov.kolla(u.kommer(ur: nyMapp.appending(path: "Inspelningar/2026-09-01 0900 Byggmöte")),
                       "källan följer med till det nya mappnamnet, så mötesvyn hittar kortet")
            Prov.lika(arkiv.tidsposter(för: kund).first?.projekt, "Lagret i Viared", "tidsposten visar det nya namnet")
            Prov.lika(arkiv.samtal(för: kund, projekt: omdöpt).count, 1, "projektets samtal följer med")
            Prov.lika(arkiv.samtal(för: kund, projekt: nil).count, 0, "och hamnar inte hos kunden")
            let möten = arkiv.inspelningar(för: kund)
            Prov.lika(möten.count, 1, "mötet i projektmappen hittas")
            Prov.lika(möten.first?.inspelning.projekt, "Lagret i Viared",
                      "och visar det nya projektnamnet fast möte.json har det gamla")
            Prov.kolla(möten.first.map { omdöpt.innehåller($0.mapp) } == true, "projektet vet att mötet är dess")
            Prov.lika(arkiv.möteskopplingar(för: kund)["m1"], omdöpt.id, "kalenderkopplingen håller")
            Prov.kolla(Läget.läs(kund: kund, projekt: omdöpt)?.text == "Bygget går bra", "lägesbilden håller")
            Prov.lika(arkiv.projekt(innehållande: nyMapp.appending(path: "Anteckningar/x.md"), hos: kund)?.id,
                      omdöpt.id, "en anteckning i mappen hör till projektet")
        }

        do {   // ett kort utan projekt, och ett vars projekt inte finns, rörs inte
            let lösa = [Uppgift(vad: "Ring Bo"), Uppgift(vad: "Gammalt", projekt: "Nedlagt")]
            try! arkiv.sparaUppgifter(lösa, för: kund)
            let lästa = arkiv.uppgifter(för: kund)
            Prov.kolla(lästa[0].projektID == nil && lästa[0].projekt == nil, "ett kort utan projekt är utan")
            Prov.kolla(lästa[1].projektID == nil && lästa[1].projekt == "Nedlagt", "ett okänt projektnamn står kvar som det är")
        }
    }
}

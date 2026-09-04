import Foundation

extension Tester {
    static func mötesuppgifter() {
        Prov.svit("Uppgifter ur möten")
        let mapp = URL(fileURLWithPath: "/Kunder/Acme/Samtal/2026-09-01 0900 Avstämning")
        let annan = URL(fileURLWithPath: "/Kunder/Acme/Samtal/2026-09-02 0900 Uppföljning")

        let ur = Uppgift(vad: "Skicka offerten", ursprung: .möte,
                         källa: mapp.path, källtitel: "Avstämning")
        Prov.kolla(Uppgiftssamling.hör(ur, till: mapp, titel: "Avstämning"),
                   "uppgiften hör till mötet den kom ur")
        Prov.kolla(!Uppgiftssamling.hör(ur, till: annan, titel: "Uppföljning"),
                   "men inte till ett annat möte")

        // Uppgifter som lades upp innan mappen började sparas har bara titeln.
        let gammal = Uppgift(vad: "Skicka offerten", ursprung: .möte, källtitel: "Avstämning")
        Prov.kolla(Uppgiftssamling.hör(gammal, till: mapp, titel: "Avstämning"),
                   "äldre uppgifter känns igen på titeln")

        let urMejl = Uppgift(vad: "Skicka offerten", ursprung: .mejl,
                             källa: mapp.path, källtitel: "Avstämning")
        Prov.kolla(!Uppgiftssamling.hör(urMejl, till: mapp, titel: "Avstämning"),
                   "en uppgift ur ett mejl hör inte till mötet")

        // Riktiga datum. "före fredag" är fritext; det tavlan sorterar och
        // rödmarkerar på är modellens uträknade ÅÅÅÅ-MM-DD.
        Prov.kolla(Uppgift.dag("2026-09-05") != nil, "ÅÅÅÅ-MM-DD blir ett datum")
        Prov.kolla(Uppgift.dag(" 2026-09-05 ") != nil, "även med luft omkring")
        Prov.lika(Uppgift.dag("före fredag"), nil, "fritext blir inget datum")
        Prov.lika(Uppgift.dag("null"), nil, "null blir inget datum")
        Prov.lika(Uppgift.dag(nil), nil, "ingenting blir ingenting")

        let igår = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let imorgon = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        Prov.kolla(Uppgift(vad: "x", senast: igår).försenad, "ett passerat datum är försenat")
        Prov.kolla(!Uppgift(vad: "x", senast: igår, läge: .klart).försenad,
                   "men inte när uppgiften är klar")
        Prov.kolla(!Uppgift(vad: "x", senast: imorgon).försenad, "morgondagen är inte försenad")
        Prov.kolla(!Uppgift(vad: "x", senast: Date()).försenad, "och inte dagens dag")
        Prov.kolla(!Uppgift(vad: "x").försenad, "utan datum finns inget att försena")

        let tolkade = Uppgiftsletare.tolka(
            #"{"uppgifter":[{"vad":"Skicka offerten","vem":"Anders","när":"före fredag","senast":"2026-09-04"}]}"#)
        Prov.lika(tolkade?.first?.senast, Uppgift.dag("2026-09-04"),
                  "modellens uträknade datum följer med uppgiften")
        let utan = Uppgiftsletare.tolka(
            #"{"uppgifter":[{"vad":"Skicka offerten","vem":null,"när":null,"senast":null}]}"#)
        Prov.lika(utan?.first?.senast, nil, "null blir inget datum även här")

        let sam = Sammanfattare.tolka(
            #"{"kärna":"k","beslut":[],"öppet":[],"åtaganden":[{"vad":"Boka möte","vem":null,"när":"nästa vecka","senast":"2026-09-08"}]}"#)
        Prov.lika(sam?.åtaganden.first?.senast, Uppgift.dag("2026-09-08"),
                  "sammanfattningens åtaganden får också sitt datum")
    }
}

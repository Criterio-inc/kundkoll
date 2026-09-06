import Foundation

extension Tester {
    static func uppgiftsrundor() {
        Prov.svit("Uppgiftsrundor")

        do {   // vilka mejl som ska gås igenom
            func mejl(_ id: String, _ dagar: Double,
                      text: String = "Kan du återkomma om offerten före fredag? Styrgruppen vill ha den.") -> Mailen.Mejl {
                Mailen.Mejl(datum: Date().addingTimeInterval(-dagar * 86400), datumText: "",
                            avsändare: "a@acme.se", ämne: id, meddelandeID: id,
                            konto: "", låda: "", riktning: "fran", text: text)
            }
            let alla = [mejl("gammalt", 90), mejl("nytt", 1), mejl("mellan", 10),
                        mejl("tomt", 2, text: ""), mejl("gjort", 3)]
            let auto = Uppgiftssamling.attGåIgenom(alla, redan: ["gjort"], tak: 10,
                                                   sedan: Date().addingTimeInterval(-30 * 86400))
            Prov.lika(auto.map(\.id), ["nytt", "mellan"],
                      "automatiskt: nyaste först, senaste månaden, varken tomma eller redan gjorda")
            let retro = Uppgiftssamling.attGåIgenom(alla, redan: ["gjort"], tak: nil, sedan: nil)
            Prov.lika(retro.map(\.id), ["gammalt", "mellan", "nytt"], "retroaktivt: allt med text, äldst först")
            Prov.lika(Uppgiftssamling.attGåIgenom(alla, redan: [], tak: 1, sedan: nil).map(\.id), ["nytt"],
                      "taket tar de nyaste")
        }

        do {   // bokföringen per kund
            let rot = FileManager.default.temporaryDirectory
                .appending(path: "kundkoll-test-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: rot) }
            let arkiv = Arkivet(rot: rot)
            let kund = try! arkiv.skapaKund(namn: "Acme")
            Prov.lika(Uppgiftssamling.rundor(kund), Uppgiftssamling.Rundor(), "tom från början")
            var r = Uppgiftssamling.Rundor()
            r.mejl = ["x", "y"]
            r.anteckningar["/a.md"] = Uppgiftssamling.avtryck("hej")
            Uppgiftssamling.spara(r, kund)
            Prov.lika(Uppgiftssamling.rundor(kund), r, "läses tillbaka som den sparades")
            Prov.kolla(FileManager.default.fileExists(
                atPath: kund.mapp.appending(path: ".kundkoll/uppgiftsrundor.json").path),
                       "bokföringen ligger i kundmappen")
        }

        do {   // avtrycket
            Prov.lika(Uppgiftssamling.avtryck("samma text"), Uppgiftssamling.avtryck("samma text"),
                      "samma text ger samma avtryck")
            Prov.kolla(Uppgiftssamling.avtryck("en text") != Uppgiftssamling.avtryck("en text."),
                       "en punkt räcker för ett annat avtryck")
        }

        do {   // försenade i Klart på en gång
            let rot = FileManager.default.temporaryDirectory
                .appending(path: "kundkoll-test-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: rot) }
            let arkiv = Arkivet(rot: rot)
            let kund = try! arkiv.skapaKund(namn: "Acme")
            let igår = Date().addingTimeInterval(-86400), imorgon = Date().addingTimeInterval(86400)
            let alla = try! arkiv.läggTill([
                Uppgift(vad: "Skicka offerten till Anna", senast: igår),
                Uppgift(vad: "Boka uppföljningsmöte", senast: igår, läge: .pågår),
                Uppgift(vad: "Läs igenom avtalet", senast: imorgon),
                Uppgift(vad: "Ring Bo om leveransen"),
                Uppgift(vad: "Redan klart sedan länge", senast: igår, läge: .klart),
            ], för: kund)
            let försenade = alla.filter { $0.försenad && $0.läge != .klart }
            Prov.lika(försenade.count, 2, "två är försenade och öppna")
            let n = try! arkiv.läggKlart(Set(försenade.map(\.id)), för: kund)
            Prov.lika(n, 2, "båda flyttades")
            let efter = arkiv.uppgifter(för: kund)
            Prov.lika(efter.filter { $0.läge == .klart }.count, 3, "tre i Klart: de två plus den som redan var det")
            Prov.lika(efter.filter { $0.läge == .attGöra }.count, 2, "morgondagens och den utan datum rörs inte")
            Prov.lika(try! arkiv.läggKlart(Set(försenade.map(\.id)), för: kund), 0, "andra gången finns inget att flytta")
        }

        do {   // tavlan får veta när uppgifter sparas
            let rot = FileManager.default.temporaryDirectory
                .appending(path: "kundkoll-test-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: rot) }
            let arkiv = Arkivet(rot: rot)
            let kund = try! arkiv.skapaKund(namn: "Acme")
            let före = arkiv.sparningar
            try! arkiv.läggTill([Uppgift(vad: "Skicka offerten", vem: nil, när: nil, senast: nil,
                                         ursprung: .egen, källtitel: nil, skapad: Date())], för: kund)
            Prov.kolla(arkiv.sparningar > före, "räknaren stiger när uppgifter sparas, så tavlan läser om")
        }
    }
}

extension Tester {
    static func projektUrRundan() {
        Prov.svit("Kort får projekt ur rundan")
        let (arkiv, rot) = tillfälligt()
        defer { try? FileManager.default.removeItem(at: rot) }
        let kund = try! arkiv.skapaKund(namn: "Acme")
        let lager = try! arkiv.skapaProjekt(namn: "Nytt lager", hos: kund)

        let svar = #"{"uppgifter":[{"vad":"Beställ hyllor","vem":"jag","när":null,"senast":null,"projekt":"nytt lager"},{"vad":"Ring Bo","vem":"jag","projekt":"Påhittat projekt"},{"vad":"Skicka faktura","vem":"jag","projekt":null}]}"#
        let tolkade = Uppgiftsletare.tolka(svar)!
        Prov.lika(tolkade.map(\.projekt), ["nytt lager", "Påhittat projekt", nil], "modellens projektnamn läses in")
        let knutna = Uppgiftssamling.knyt(tolkade, till: arkiv.projekt(för: kund))
        Prov.lika(knutna[0].projektID, lager.id, "ett namn som matchar, oavsett versaler, ger kortet projektets id")
        Prov.lika(knutna[0].projekt, "Nytt lager", "och projektets riktiga stavning")
        Prov.lika(knutna[1].projekt, "Nytt lager", "ett påhittat projektnamn byts mot det riktiga")
        Prov.lika(knutna[2].projektID, lager.id, "med ett enda projekt landar även ett kort utan angivet projekt där")
        Prov.lika(knutna[1].projektID, lager.id, "och det med påhittat namn likaså")

        // Med två projekt får modellen välja, och det oplacerade stannar hos kunden.
        try! arkiv.skapaProjekt(namn: "Föreläsningsserie", hos: kund)
        let två = Uppgiftssamling.knyt(tolkade, till: arkiv.projekt(för: kund))
        Prov.lika(två[0].projektID, lager.id, "namnet avgör när det finns flera")
        Prov.kolla(två[1].projektID == nil && två[2].projektID == nil, "det utan träff förblir kundens")
        Prov.kolla(arkiv.standardprojekt(för: kund) == nil, "med två projekt finns inget standardprojekt")

        Prov.lika(Mailen.förhandsrad("Hej Pär,\n\nKan du skicka offerten?\n\nMvh"), "Kan du skicka offerten?",
                  "förhandsraden hoppar över hälsningen")
        Prov.lika(Mailen.förhandsrad("> citerat\n"), nil, "citat räknas inte")
        Prov.kolla(Mailen.förhandsrad(String(repeating: "x", count: 200))!.hasSuffix("…"), "långa rader kapas")
    }

    static func ensamtProjekt() {
        Prov.svit("Ett enda uppdrag är standard")
        let (arkiv, rot) = tillfälligt()
        defer { try? FileManager.default.removeItem(at: rot) }
        let kund = try! arkiv.skapaKund(namn: "Borås")
        try! Data(#"[{"vad":"Svara på frågan om lådor"},{"vad":"Gammalt","projekt":"Nedlagt"}]"#.utf8)
            .write(to: kund.mapp.appending(path: "uppgifter.json"))
        Prov.kolla(arkiv.uppgifter(för: kund).allSatisfy { $0.projektID == nil }, "utan projekt är korten kundens")

        let uppdrag = try! arkiv.skapaProjekt(namn: "Informationshantering i M365", hos: kund)
        Prov.lika(arkiv.standardprojekt(för: kund)?.id, uppdrag.id, "det enda projektet är standard")
        let kort = arkiv.uppgifter(för: kund)
        Prov.lika(kort[0].projektID, uppdrag.id, "ett löst kort landar i uppdraget vid nästa läsning")
        Prov.lika(kort[0].projekt, "Informationshantering i M365", "med namnet som etikett")
        Prov.kolla(kort[1].projektID == nil && kort[1].projekt == "Nedlagt", "ett kort med ett okänt projektnamn rörs inte")
    }
}

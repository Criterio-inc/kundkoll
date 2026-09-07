import Foundation

extension Tester {
    static func tavlanRäknarRätt() {
        Prov.svit("Tavlan räknar rätt")

        do {   // mejldatum: som tal ur skriptet, svensk text som reserv
            Prov.kolla(Mailen.datum(iso: "2026-09-02 13:42:54") != nil, "talformen tolkas")
            Prov.kolla(Mailen.datum(ur: "onsdag 2 september 2026 13:42:54") != nil, "svensk datumtext tolkas")
            Prov.kolla(Mailen.datum(ur: "Tuesday, 18 August 2026 at 00:49:37") != nil, "engelsk datumtext tolkas fortfarande")
            let sv = Mailen.datum(ur: "onsdag 2 september 2026 13:42:54")!
            let iso = Mailen.datum(iso: "2026-09-02 13:42:54")!
            Prov.lika(sv, iso, "text och tal ger samma tidpunkt")
            let rad = "onsdag 2 september 2026 13:42:54\u{1F}Anna <anna@acme.se>\u{1F}Hej\u{1F}<id>\u{1F}Konto\u{1F}INBOX\u{1F}fran\u{1F}text\u{1F}2026-09-02 13:42:54\n"
            Prov.lika(Mailen.tolka(rad).first?.datum, iso, "skriptets nionde fält blir mejlets datum")
            let gammal = try! JSONDecoder.kundkoll.decode(Mailen.Mejl.self, from: Data(
                "{\"datumText\":\"onsdag 2 september 2026 13:42:54\",\"avsändare\":\"a\",\"ämne\":\"b\",\"meddelandeID\":\"c\",\"konto\":\"\",\"låda\":\"\",\"riktning\":\"fran\",\"text\":\"\"}".utf8))
            Prov.lika(gammal.datum, iso, "en cache utan datum får det ur texten")
        }

        do {   // den retroaktiva rundan: passerat datum är historia, kort utan person
            let idag = Date()
            Prov.kolla(Uppgiftssamling.historisk(Uppgift(vad: "Svara", senast: idag.addingTimeInterval(-86400)), idag: idag),
                       "i går är historia")
            Prov.kolla(!Uppgiftssamling.historisk(Uppgift(vad: "Svara", senast: idag), idag: idag),
                       "i dag är det inte")
            Prov.kolla(!Uppgiftssamling.historisk(Uppgift(vad: "Svara"), idag: idag),
                       "utan datum är det inte")
            let utan = [Uppgift(vad: "Läsa direktivet"), Uppgift(vad: "Svara Erik", vem: "Erik")]
            Prov.lika(Uppgiftssamling.medVem(utan, skickat: false).map(\.vem), ["jag", "Erik"],
                      "ur ett mottaget mejl är det utan person mitt")
            Prov.lika(Uppgiftssamling.medVem(utan, skickat: true).map(\.vad), ["Svara Erik"],
                      "ur ett skickat mejl stryks det utan person")
        }

        do {   // dubblettspärren
            Prov.kolla(!Uppgift(vad: "Boka möte med Anna").liknar(Uppgift(vad: "Boka möte med Bo")),
                       "olika korta namn är olika åtaganden")
            Prov.kolla(Uppgift(vad: "Skicka veckorapporten").liknar(Uppgift(vad: "Skicka veckorapport")),
                       "samma sak i annan böjning känns igen")
            Prov.kolla(!Uppgift(vad: "Skicka underlag", vem: "Anna").liknar(Uppgift(vad: "Skicka underlag", vem: "Bo")),
                       "samma text till olika personer är olika")
            let igår = Date().addingTimeInterval(-86400), omMånad = Date().addingTimeInterval(30 * 86400)
            Prov.kolla(!Uppgift(vad: "Skicka underlag", senast: igår).liknar(Uppgift(vad: "Skicka underlag", senast: omMånad)),
                       "samma text en månad isär är olika")
            Prov.kolla(Uppgift(vad: "Boka in tid med Linnea", vem: "jag").liknar(Uppgift(vad: "Ta en kort avstämning med Linnea", vem: "Pär Levander")),
                       "boka tid och avstämning med samma person är ett åtagande")
            Prov.kolla(!Uppgift(vad: "Boka in tid med Linnea").liknar(Uppgift(vad: "Ta en kort avstämning med Erik")),
                       "men med olika personer är det två")
            let rot = FileManager.default.temporaryDirectory
                .appending(path: "kundkoll-test-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: rot) }
            let arkiv = Arkivet(rot: rot)
            let kund = try! arkiv.skapaKund(namn: "Acme")
            try! arkiv.läggTill([Uppgift(vad: "Skicka veckorapporten", läge: .klart)], för: kund)
            let efter = try! arkiv.läggTill([Uppgift(vad: "Skicka veckorapporten")], för: kund)
            Prov.lika(efter.count, 2, "ett avklarat kort hindrar inte samma löfte på nytt")
            let mötet = kund.samtalsmapp.appending(path: "2026-09-01 0900 Möte")
            let m = "Samtal/2026-09-01 0900 Möte"
            try! arkiv.ersätt(kort: [Uppgift(vad: "Ring Bo om leveransen", ursprung: .möte, källa: m)], ur: mötet, för: kund)
            var flyttat = arkiv.uppgifter(för: kund).first { $0.vad == "Ring Bo om leveransen" }!
            flyttat.läge = .pågår
            try! arkiv.uppdatera(flyttat, för: kund)
            try! arkiv.läggTill([Uppgift(vad: "Boka uppföljning", ursprung: .möte, källa: m)], för: kund)
            let ny = try! arkiv.ersätt(kort: [Uppgift(vad: "Boka uppföljningsmöte i oktober", ursprung: .möte, källa: m)], ur: mötet, för: kund)
            Prov.kolla(ny.contains { $0.vad == "Ring Bo om leveransen" && $0.läge == .pågår }, "ett kort som flyttats lämnas kvar vid omskrivning")
            Prov.kolla(!ny.contains { $0.vad == "Boka uppföljning" }, "ett orört kort ur samma möte byts ut")
            Prov.kolla(ny.contains { $0.vad == "Boka uppföljningsmöte i oktober" }, "mot det nya")
        }

        do {   // sortering och projekt ur sökväg
            let snart = Uppgift(vad: "a", senast: Date().addingTimeInterval(86400))
            let sen = Uppgift(vad: "b", senast: Date().addingTimeInterval(10 * 86400))
            let utan = Uppgift(vad: "c")
            let ordnade = [utan, sen, snart].sorted(by: Kanbanvy.ordning)
            Prov.lika(ordnade.map(\.vad), ["a", "b", "c"], "närmast datum överst, utan datum sist")
            Prov.lika(Uppgiftssamling.projektnamn(ur: URL(fileURLWithPath: "/K/Acme/Projekt/Nytt lager/Anteckningar/x.md")),
                      "Nytt lager", "anteckning i projektmapp får projektet")
            Prov.lika(Uppgiftssamling.projektnamn(ur: URL(fileURLWithPath: "/K/Acme/Anteckningar/x.md")), nil,
                      "anteckning hos kunden får inget projekt")
        }

        do {   // uppföljningsmejlet ur tavlan
            var i = Inspelning(titel: "Möte", inledd: Date(), längd: 1, kund: "Acme", projekt: nil,
                               mikrofon: nil, liveYttranden: [], arkivYttranden: nil, kallade: [], språk: "sv")
            i.sammanfattning = Mötessammanfattning(kärna: "k", beslut: ["Beslutet"],
                                                    åtaganden: [.init(vad: "Påhittat åtagande")], öppet: [])
            let text = Uppföljning.brödtext(för: i, kort: [Uppgift(vad: "Skicka offerten", vem: "Anna", läge: .klart)])
            Prov.kolla(text.contains("Skicka offerten (Anna) — klart"), "tavlans kort står i mejlet")
            Prov.kolla(!text.contains("Påhittat"), "sammanfattningens ögonblicksbild används inte när tavlan finns")
        }
    }
}

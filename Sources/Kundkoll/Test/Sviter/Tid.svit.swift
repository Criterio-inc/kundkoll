import Foundation

extension Tester {
    static func tid() {
        Prov.svit("Tidsloggen")

        // Längdtolkningen följer hur man faktiskt skriver.
        Prov.lika(Tidspost.tolkaLängd("1:30"), 5400, "kolon är timmar och minuter")
        Prov.lika(Tidspost.tolkaLängd("0:45"), 2700, "även under en timme")
        Prov.lika(Tidspost.tolkaLängd("1,5"), 5400, "decimaler är timmar")
        Prov.lika(Tidspost.tolkaLängd("1.5"), 5400, "med punkt också")
        Prov.lika(Tidspost.tolkaLängd("90"), 5400, "ett naket tal är minuter")
        Prov.lika(Tidspost.tolkaLängd("1:75"), nil, "75 minuter i minutfältet är fel")
        Prov.lika(Tidspost.tolkaLängd("smör"), nil, "text är inte tid")
        Prov.lika(Tidspost.tolkaLängd(""), nil, "tomt är inte tid")

        Prov.lika(Tidspost.längdtext(5400), "1:30", "och skrivs ut på samma form")
        Prov.lika(Tidspost.längdtext(89), "0:01", "korta pass rundas till minuter")

        // Uret: räknar när det går, står stilla pausat, och sovtid räknas bort.
        var p = Tidur.Pågående(kund: "Acme", projekt: "Nytt lager", vad: "Bygger",
                               start: Uppgift.dag("2026-09-02")!)
        let start = p.start
        Prov.lika(p.gången(nu: start.addingTimeInterval(600)), 600,
                  "uret räknar väggtid")
        // Datorn somnar efter 10 minuter: frys där.
        p.ackumulerat += 600
        p.pausad = true
        Prov.lika(p.gången(nu: start.addingTimeInterval(4000)), 600,
                  "pausat ur står stilla hur länge datorn än sover")
        // Vaknar och fortsätter: sovtiden är borta.
        p.senasteStart = start.addingTimeInterval(4000)
        p.pausad = false
        Prov.lika(p.gången(nu: start.addingTimeInterval(4300)), 900,
                  "fortsättningen räknar från uppvaknandet, inte insomningen")

        // Lagringen.
        let rot = FileManager.default.temporaryDirectory
            .appending(path: "kundkoll-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: rot) }
        let arkiv = Arkivet(rot: rot)
        let kund = try! arkiv.skapaKund(namn: "Acme")
        try! arkiv.läggTill(Tidspost(vad: "Byggde hyllor", projekt: "Nytt lager",
                                     sekunder: 5400), för: kund)
        try! arkiv.läggTill(Tidspost(vad: "Möte", projekt: nil, sekunder: 1800), för: kund)
        Prov.lika(arkiv.tidsposter(för: kund).count, 2, "poster går att logga och läsa")
        let md = (try? String(contentsOf: kund.mapp.appending(path: "Tid.md"),
                              encoding: .utf8)) ?? ""
        Prov.kolla(md.contains("Nytt lager · 1:30"), "markdown-loggen summerar per projekt")
        Prov.kolla(md.contains("Byggde hyllor"), "och raderna står där")
        try! arkiv.taBort(arkiv.tidsposter(för: kund).first!, för: kund)
        Prov.lika(arkiv.tidsposter(för: kund).count, 1, "en post går att ta bort")

        // Gamla filer utan nya fält ska gå att läsa.
        let gammal = try? JSONDecoder.kundkoll.decode(
            Tidspost.self,
            from: Data(#"{"vad":"Möte","start":"2026-09-01T09:00:00Z","sekunder":600}"#.utf8))
        Prov.lika(gammal?.vad, "Möte", "en post utan id och projekt går att läsa")
    }
}

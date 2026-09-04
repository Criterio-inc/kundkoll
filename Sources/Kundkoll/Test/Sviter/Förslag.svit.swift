import Foundation

extension Tester {
    /// Ett möte i en serie säger vad som blev klart och vad som fick svar
    /// sedan sist, och ett hållet möte är en tidspost ett klick bort.
    static func förslag() {
        Prov.svit("Förslag ur mötena")

        func möte(_ titel: String, _ dag: String, öppet: [String] = [], besvarade: [String] = []) -> Möte {
            var i = Inspelning(titel: titel, inledd: Uppgift.dag(dag)!, längd: 1800, kund: "Acme",
                               projekt: nil, mikrofon: nil, liveYttranden: [], arkivYttranden: nil)
            i.sammanfattning = Mötessammanfattning(kärna: "k", beslut: [], åtaganden: [],
                                                   öppet: öppet, besvarade: besvarade)
            return Möte(inspelning: i, mapp: URL(fileURLWithPath: "/x/\(titel) \(dag)"))
        }

        do {   // numren i svaret blir kortens id och frågornas text
            let a = UUID(), b = UUID()
            let förra = Sammanfattare.Förra(
                öppnaKort: [.init(id: a, vad: "Skicka offerten"), .init(id: b, vad: "Boka besök")],
                öppnaFrågor: ["Vem betalar frakten?", "När börjar bygget?"])
            let svar = #"{"kärna":"k","beslut":[],"åtaganden":[],"öppet":[],"avklarade":[2],"besvarade":["1", 7]}"#
            let s = Sammanfattare.tolka(svar, förra: förra)!
            Prov.lika(s.verkarKlara.map(\.kort), [b], "«avklarade: [2]» pekar på det andra kortet")

            // Med transkript krävs belägg som faktiskt står där.
            let transkript = "[00:00:03] Jag: Hej Anna, jag skickade offerten i fredags, har ni fått den?\n[00:00:10] Anna: Ja, den kom.\n[00:00:26] Anna: Frakten står kommunen för, det är klart."
            let medBelägg = #"{"kärna":"k","avklarade":[{"nummer":1,"belägg":"jag skickade offerten i fredags"},{"nummer":2,"belägg":"besöket är bokat och klart"}],"besvarade":[{"nummer":"1","belägg":"Frakten står kommunen för, det är klart"},{"nummer":2}]}"#
            let g = Sammanfattare.tolka(medBelägg, förra: förra, transkript: transkript)!
            Prov.lika(g.verkarKlara.map(\.kort), [a], "ett belägg som står i transkriptet godtas, ett påhittat fälls")
            Prov.lika(g.verkarKlara.first?.belägg, "jag skickade offerten i fredags", "belägget följer med kortet")
            Prov.lika(g.besvarade, ["Vem betalar frakten?"], "en fråga utan belägg räknas inte som besvarad")
            Prov.kolla(Sammanfattare.finns("Ja den kom", i: transkript) == false, "korta citat räknas inte")
            Prov.kolla(Sammanfattare.finns("frakten står kommunen för det är klart", i: transkript),
                       "skiljetecken och versaler spelar ingen roll")
            Prov.lika(s.besvarade, ["Vem betalar frakten?"], "«besvarade» som text och utanför listan tolkas tolerant")
            Prov.kolla(Sammanfattare.tolka(svar)!.verkarKlara.isEmpty, "utan underlag om förra mötet ignoreras numren")
            Prov.kolla(Sammanfattare.förradel(förra).contains("1. Skicka offerten"), "prompten numrerar korten")
            Prov.lika(Sammanfattare.förradel(nil), "", "utan förra möte läggs inget till")
            Prov.lika(Sammanfattare.förradel(Sammanfattare.Förra()), "", "och inte heller när det inte finns något öppet")

            // Rundtur genom möte.json
            let data = try! JSONEncoder.kundkoll.encode(s)
            let läst = try! JSONDecoder.kundkoll.decode(Mötessammanfattning.self, from: data)
            Prov.lika(läst.verkarKlara.map(\.kort), [b], "förslagen överlever sparning")
            let gammal = try! JSONDecoder.kundkoll.decode(Mötessammanfattning.self, from: Data(#"{"kärna":"k"}"#.utf8))
            Prov.kolla(gammal.verkarKlara.isEmpty && gammal.besvarade.isEmpty, "äldre sammanfattningar läses utan fälten")
        }

        do {   // frågorna lever genom serien tills någon besvarar dem
            let m1 = möte("magnus 1on1 20260801", "2026-08-01", öppet: ["Vem betalar frakten?", "Var ska lagret ligga?"])
            let m2 = möte("magnus 1on1 20260815", "2026-08-15", öppet: ["När börjar bygget?"], besvarade: ["var ska lagret ligga"])
            let m3 = möte("magnus 1on1 20260901", "2026-09-01", öppet: ["Vem betalar frakten?"], besvarade: ["När börjar bygget?"])
            let annat = möte("Styrgrupp", "2026-08-20", öppet: ["Budget?"])
            let alla = [m1, m2, m3, annat]
            Prov.lika(Mötesserie.öppnaFrågor(tillOchMed: m2.inspelning, bland: alla),
                      ["Vem betalar frakten?", "När börjar bygget?"],
                      "en besvarad fråga försvinner, nya läggs till, oavsett skiljetecken och versaler")
            Prov.lika(Mötesserie.öppnaFrågor(tillOchMed: m3.inspelning, bland: alla),
                      ["Vem betalar frakten?"],
                      "samma fråga som ställs igen står bara en gång, och mötet utanför serien räknas inte")
            let b = Briefing.bygg(kund: "Acme", möte: nil, inspelningar: alla.sorted { $0.inspelning.inledd > $1.inspelning.inledd },
                                  uppgifter: [], mejl: [])
            Prov.lika(b.öppnaFrågor, ["Vem betalar frakten?"], "briefen visar det som fortfarande är öppet i serien")
        }

        do {   // förslaget landar på kortet, aldrig som en stängning
            let (arkiv, rot) = tillfälligt()
            defer { try? FileManager.default.removeItem(at: rot) }
            let kund = try! arkiv.skapaKund(namn: "Acme")
            let kort = Uppgift(vad: "Skicka offerten", ursprung: .möte)
            let klart = Uppgift(vad: "Redan gjort", läge: .klart)
            try! arkiv.sparaUppgifter([kort, klart], för: kund)
            let m = möte("magnus 1on1 20260901", "2026-09-01").inspelning
            Uppgiftssamling.föreslåKlart([.init(kort: kort.id, belägg: "jag skickade den i fredags"),
                                          .init(kort: klart.id, belägg: "")], enligt: m, för: kund, arkiv: arkiv)
            let efter = arkiv.uppgifter(för: kund)
            let k = efter.first { $0.id == kort.id }!
            Prov.lika(k.läge, .attGöra, "kortet är fortfarande öppet")
            Prov.kolla(k.klartFörslag?.contains("magnus 1on1 20260901") == true
                       && k.klartFörslag?.contains("«jag skickade den i fredags»") == true,
                       "men bär förslaget med mötets namn och belägget")
            Prov.lika(efter.first { $0.id == klart.id }!.klartFörslag, nil, "ett redan klart kort får inget förslag")
            let gammalt = try! JSONDecoder.kundkoll.decode(Uppgift.self, from: Data(#"{"vad":"x"}"#.utf8))
            Prov.lika(gammalt.klartFörslag, nil, "äldre kort läses utan fältet")

            // Underlaget till nästa sammanfattning: förra mötets öppna kort och frågor.
            let projekt = try! arkiv.skapaProjekt(namn: "Nytt lager", hos: kund)
            let mapp1 = projekt.inspelningsmapp.appending(path: "2026-08-15 0900 magnus 1on1 20260815")
            try! FileManager.default.createDirectory(at: mapp1, withIntermediateDirectories: true)
            var förraMötet = möte("magnus 1on1 20260815", "2026-08-15", öppet: ["Vem betalar frakten?"]).inspelning
            förraMötet.kund = "Acme"
            try! JSONEncoder.kundkoll.encode(förraMötet).write(to: mapp1.appending(path: "möte.json"))
            try! arkiv.sparaUppgifter([Uppgift(vad: "Boka besök", ursprung: .möte, källa: arkiv.relativ(mapp1, i: kund), källtitel: förraMötet.titel)], för: kund)
            let mapp2 = projekt.inspelningsmapp.appending(path: "2026-09-01 0900 magnus 1on1 20260901")
            let u = Uppgiftssamling.förra(för: m, mapp: mapp2, arkiv: arkiv)
            Prov.lika(u?.öppnaKort.map(\.vad), ["Boka besök"], "förra mötets öppna kort följer med")
            Prov.lika(u?.öppnaFrågor, ["Vem betalar frakten?"], "och dess öppna frågor")
            Prov.kolla(Uppgiftssamling.förra(för: förraMötet, mapp: mapp1, arkiv: arkiv) == nil,
                       "det första mötet i serien har inget förra")
        }

        do {   // briefen läser projektets lägesbild
            let (arkiv, rot) = tillfälligt()
            defer { try? FileManager.default.removeItem(at: rot) }
            let kund = try! arkiv.skapaKund(namn: "Acme")
            let projekt = try! arkiv.skapaProjekt(namn: "Nytt lager", hos: kund)
            try! FileManager.default.createDirectory(at: kund.mapp.appending(path: ".kundkoll"), withIntermediateDirectories: true)
            try! JSONEncoder.kundkoll.encode(Lägesbild(text: "Bygget går bra", skriven: Date(), modell: nil))
                .write(to: kund.mapp.appending(path: ".kundkoll/läget-\(projekt.id).json"))
            let kalendermöte = Kalendern.Möte(id: "k1", titel: "Byggmöte", start: Date(), slut: Date().addingTimeInterval(3600),
                                              deltagare: [], plats: nil, möteslänk: nil)
            Prov.kolla(Briefing.bygg(för: kund, möte: kalendermöte, arkiv: arkiv).projekt == nil,
                       "ett okopplat möte utan tidigare möten har inget projekt")
            try! arkiv.kopplaMöte("k1", till: projekt, för: kund)
            let b = Briefing.bygg(för: kund, möte: kalendermöte, arkiv: arkiv)
            Prov.lika(b.projekt?.id, projekt.id, "kopplingen i kalendern ger briefen sitt projekt")
            Prov.lika(b.lägesbild?.text, "Bygget går bra", "och projektets lägesbild följer med")

            // Utan koppling: projektet det förra mötet i serien ligger i.
            let mapp = projekt.inspelningsmapp.appending(path: "2026-09-01 0900 Byggmöte")
            try! FileManager.default.createDirectory(at: mapp, withIntermediateDirectories: true)
            var i = möte("Byggmöte", "2026-09-01").inspelning; i.kund = "Acme"
            try! JSONEncoder.kundkoll.encode(i).write(to: mapp.appending(path: "möte.json"))
            let b2 = Briefing.bygg(för: kund, möte: nil, arkiv: arkiv)
            Prov.lika(b2.projekt?.id, projekt.id, "utan koppling tas projektet där förra mötet ligger")
        }

        do {   // tidsposter ur mötena
            let idag = Uppgift.dag("2026-09-10")!
            let nyligen = möte("Byggmöte", "2026-09-08")
            let gammalt = möte("Uppstart", "2026-08-20")
            var kortInsp = möte("Snabbt", "2026-09-09").inspelning; kortInsp.längd = 30
            let kort2 = Möte(inspelning: kortInsp, mapp: URL(fileURLWithPath: "/x/Snabbt"))
            let loggat = möte("Avstämning", "2026-09-09")
            let avfärdat = möte("Genomgång", "2026-09-07")
            let poster = [Tidspost(vad: "Avstämning", sekunder: 1800, möte: loggat.inspelning.id)]
            let f = Tidspost.förslag(ur: [nyligen, gammalt, kort2, loggat, avfärdat], poster: poster,
                                     avfärdade: [avfärdat.inspelning.id], idag: idag)
            Prov.lika(f.map(\.inspelning.titel), ["Byggmöte"],
                      "bara veckans möten som är längre än en minut, inte loggade och inte avfärdade")
            let projekt = Projekt(id: "p1", namn: "Nytt lager", mapp: URL(fileURLWithPath: "/x/p"), kundnamn: "Acme")
            let post = Tidspost.ur(nyligen, projekt: projekt)
            Prov.kolla(post.vad == "Byggmöte" && post.sekunder == 1800 && post.projektID == "p1"
                       && post.möte == nyligen.inspelning.id && post.start == nyligen.inspelning.inledd,
                       "posten får mötets titel, längd, start och projekt")
            let läst = try! JSONDecoder.kundkoll.decode(Tidspost.self, from: try! JSONEncoder.kundkoll.encode(post))
            Prov.lika(läst.möte, nyligen.inspelning.id, "kopplingen till mötet överlever sparning")
        }
    }
}

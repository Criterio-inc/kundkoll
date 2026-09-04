import Foundation

extension Tester {
    static func lägesbilden() {
        Prov.svit("Lägesbilden")

        func inspelning(_ titel: String, projekt: String?, dag: String,
                        kärna: String? = nil) -> Inspelning {
            var i = Inspelning(titel: titel, inledd: Uppgift.dag(dag)!, längd: 60,
                               kund: "Acme", projekt: projekt, mikrofon: nil,
                               liveYttranden: [], arkivYttranden: nil)
            if let kärna {
                i.sammanfattning = Mötessammanfattning(kärna: kärna, beslut: ["B"],
                                                       åtaganden: [], öppet: ["Ö"])
            }
            return i
        }
        let underlag = Läget.underlag(
            projekt: "Nytt lager",
            inspelningar: [inspelning("Avstämning", projekt: "Nytt lager",
                                      dag: "2026-08-28", kärna: "Vi kom igång."),
                           inspelning("Annat möte", projekt: nil,
                                      dag: "2026-08-29", kärna: "Hör inte hit.")],
            uppgifter: [Uppgift(vad: "Skicka offerten", senast: Uppgift.dag("2026-08-20"),
                                projekt: "Nytt lager"),
                        Uppgift(vad: "Beställ hyllor till Nytt lager", projekt: nil),
                        Uppgift(vad: "Annan kunds sak", projekt: nil)],
            mejl: [Mailen.Mejl(datum: Uppgift.dag("2026-08-30"), datumText: "",
                               avsändare: "Anna <anna@acme.se>", ämne: "Offert",
                               meddelandeID: "a", konto: "k", låda: "INBOX",
                               riktning: "från", text: "Hur går det med offerten?")],
            anteckningar: [])

        Prov.kolla(underlag.contains { $0.titel.contains("Avstämning") },
                   "projektets möte är med i underlaget")
        Prov.kolla(!underlag.contains { $0.titel.contains("Annat möte") },
                   "men inte möten utanför projektet")
        let tavlan = underlag.first { $0.titel == "Uppgifterna på tavlan" }
        Prov.kolla(tavlan?.text.contains("Skicka offerten") == true,
                   "projektets uppgifter är med")
        Prov.kolla(tavlan?.text.contains("FÖRSENAD") == true,
                   "och det försenade är utpekat")
        Prov.kolla(tavlan?.text.contains("Beställ hyllor") == true,
                   "liksom uppgifter som nämner projektet vid namn")
        Prov.kolla(tavlan?.text.contains("Annan kunds sak") == false,
                   "uppgifter utanför projektet är inte med")
        Prov.kolla(underlag.contains { $0.typ == "mejl" }, "mejlen följer med")

        Prov.lika(Läget.underlag(projekt: "Tomt", inspelningar: [], uppgifter: [],
                                 mejl: [], anteckningar: []).count, 0,
                  "utan underlag byggs ingenting")

        // Färskhet: en bild skriven före senaste materialet är gammal.
        let rot = FileManager.default.temporaryDirectory
            .appending(path: "kundkoll-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: rot) }
        let arkiv = Arkivet(rot: rot)
        let kund = try! arkiv.skapaKund(namn: "Acme")
        let projekt = try! arkiv.skapaProjekt(namn: "Nytt lager", hos: kund)
        try! arkiv.läggTill([Uppgift(vad: "Skicka offerten", projekt: "Nytt lager")],
                            för: kund)
        let gammalBild = Lägesbild(text: "x", skriven: Uppgift.dag("2026-01-01")!)
        Prov.kolla(Läget.gammal(gammalBild, kund: kund, projekt: projekt, arkiv: arkiv),
                   "en bild skriven före senaste materialet är gammal")
        let färsk = Lägesbild(text: "x", skriven: Date().addingTimeInterval(60))
        Prov.kolla(!Läget.gammal(färsk, kund: kund, projekt: projekt, arkiv: arkiv),
                   "en nyskriven är det inte")
    }
}

import Foundation

extension Tester {
    static func lagring() {
        Prov.svit("Lagring")

        func läs<T: Decodable>(_ typ: T.Type, _ json: String, _ vad: String) -> T? {
            do {
                return try JSONDecoder.kundkoll.decode(typ, from: Data(json.utf8))
            } catch {
                Prov.kolla(false, "\(vad): \(error)")
                return nil
            }
        }

        // Sammanfattningen ligger inne i möte.json. Faller den, försvinner
        // hela inspelningen ur listan.
        let sam = läs(Mötessammanfattning.self,
                      #"{"kärna":"Vi gick igenom offerten","beslut":[],"åtaganden":[],"öppet":[]}"#,
                      "en sammanfattning utan skriven-datum går att läsa")
        Prov.lika(sam?.kärna, "Vi gick igenom offerten", "och innehållet kommer med")

        let åtagande = läs(Mötessammanfattning.self,
                           #"{"kärna":"","beslut":[],"öppet":[],"åtaganden":[{"vad":"Skicka offerten"}]}"#,
                           "ett åtagande utan id och klart går att läsa")
        Prov.lika(åtagande?.åtaganden.first?.vad, "Skicka offerten", "och texten kommer med")
        Prov.lika(åtagande?.åtaganden.first?.klart, false, "klart får sitt standardvärde")

        // Röstprofilerna byggs upp över månader. De får inte kunna gå förlorade.
        let profil = läs([Röstprofil].self,
                         #"[{"namn":"Anna","avtryck":[{"vektor":[0.1,0.2],"sekunder":6}],"uppdaterad":"2026-08-01T09:00:00Z","samtal":2}]"#,
                         "en röstprofil utan id går att läsa")
        Prov.lika(profil?.first?.namn, "Anna", "och namnet kommer med")
        Prov.lika(profil?.first?.avtryck.count, 1, "liksom avtrycket")

        let kopplad = läs([Kopplad].self, #"[{"väg":"/Users/a/kod"}]"#,
                          "en kopplad mapp med bara sin väg går att läsa")
        Prov.lika(kopplad?.first?.väg, "/Users/a/kod", "och vägen kommer med")
        Prov.lika(kopplad?.first?.ändelser.count, 0, "ändelserna får sitt standardvärde")

        // Chattarna ligger i samtalen. Ett nytt fält på ett meddelande skulle
        // annars ta hela samtalshistoriken med sig.
        let samtal = läs(Samtal.self,
                         #"{"titel":"Om offerten","meddelanden":[{"roll":"människa","text":"Vad kostar det?"}]}"#,
                         "ett meddelande utan id, tid och ursprung går att läsa")
        Prov.lika(samtal?.meddelanden.first?.text, "Vad kostar det?", "och frågan kommer med")
        Prov.lika(samtal?.meddelanden.first?.ursprung, .kunskapsbank, "ursprunget får sitt standardvärde")

        let hänvisning = läs(Chatt.Meddelande.self,
                             #"{"roll":"assistent","text":"Svar","hänvisningar":[{"nummer":1,"titel":"Möte","typ":"transkript","källa":"/a"}]}"#,
                             "en hänvisning utan datum går att läsa")
        Prov.lika(hänvisning?.hänvisningar.first?.titel, "Möte", "och titeln kommer med")

        let modell = läs(Modellval.self, #"{"leverantör":"openrouter"}"#,
                         "ett modellval utan modell och adress går att läsa")
        Prov.lika(modell?.leverantör, .openrouter, "och leverantören kommer med")
        Prov.kolla(!(modell?.modell.isEmpty ?? true), "modellen får sitt standardvärde")

        // Åt andra hållet: en fil skriven av en nyare version, med fält den
        // här inte känner till, ska också gå att läsa.
        let framtid = läs(Uppgift.self,
                          #"{"vad":"Skicka offerten","prioritet":"hög"}"#,
                          "ett okänt fält gör inte filen oläsbar")
        Prov.lika(framtid?.vad, "Skicka offerten", "och det kända kommer med")

        // Och skulle en möte.json ändå bli oläslig — en avbruten skrivning,
        // en trasig disk — ska inspelningen synas som påbörjad i stället för
        // att bara försvinna ur listan.
        do {
            let rot = FileManager.default.temporaryDirectory
                .appending(path: "kundkoll-test-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: rot) }
            let arkiv = Arkivet(rot: rot)
            let kund = try! arkiv.skapaKund(namn: "Acme")
            let mapp = try! arkiv.nyInspelningsmapp(placering: .kund(kund), titel: "Avstämning",
                                                    datum: Date())
            try! Data("x".utf8).write(to: mapp.appending(path: "motpart.wav"))
            let i = Inspelning(titel: "Avstämning", inledd: Date(), längd: 60, kund: "Acme",
                               projekt: nil, mikrofon: nil, liveYttranden: [], arkivYttranden: nil)
            try! arkiv.spara(i, i: mapp)
            Prov.lika(arkiv.inspelningar(för: kund).count, 1, "inspelningen syns i listan")
            Prov.lika(arkiv.ofullständiga(för: kund).count, 0, "och räknas inte som påbörjad")

            try! Data("{ trasig".utf8).write(to: mapp.appending(path: "möte.json"))
            Prov.lika(arkiv.inspelningar(för: kund).count, 0,
                      "en oläslig möte.json går inte att lista")
            Prov.lika(arkiv.ofullständiga(för: kund).count, 1,
                      "men mappen syns som påbörjad i stället för att försvinna")
        }
    }
}

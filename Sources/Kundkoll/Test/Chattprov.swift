import Foundation

/// Ett skarpt anrop mot den valda modellen.
///
///     Kundkoll --prov-chatt [leverantör] [modell] [adress]
///
/// Kostar en bråkdel av en cent hos en molnleverantör, ingenting lokalt.
/// Adressen gör att en lokal server på en annan port — LM Studio, mlx_lm —
/// kan provas utan att röra appens sparade inställning.
enum Chattprov {
    static func kör(argument: [String]) async -> Int32 {
        var val = Modellval.läs()
        if let första = argument.first, let l = Leverantör(rawValue: första) {
            val.leverantör = l
            val.modell = l.standardmodell
            val.adress = l.behöverEgenAdress ? l.standardadress : ""
        }
        if argument.count > 1 { val.modell = argument[1] }
        if argument.count > 2 { val.adress = argument[2] }

        print("Leverantör: \(val.leverantör.namn)")
        print("Modell:     \(val.modell.isEmpty ? "(ur adressen)" : val.modell)")
        print("Adress:     \(val.url?.absoluteString ?? "trasig")")
        print("Nyckel:     \(Nyckelring.förLeverantör(val.leverantör) != nil ? "finns" : "saknas")")
        print("")

        // Ett underlag att svara ur, så att både hämtning och hänvisning provas
        let träffar = [
            Kunskapsbank.Träff(id: 1, typ: "transkript", titel: "Avstämning 12 maj",
                               text: "[03:12] Bo: Vi behöver offerten på pallställ före fredag.",
                               källa: "", tid: nil, poäng: 0),
            Kunskapsbank.Träff(id: 2, typ: "anteckning", titel: "Prisbild",
                               text: "Battericellerna kostar 2 400 kr per enhet vid volym över 500.",
                               källa: "", tid: nil, poäng: 0),
        ]

        let chatt = Chatt(val: val)
        let t0 = Date()
        // Samma väg som panelen tar: strömmande, med räkning av bitarna.
        nonisolated(unsafe) var bitar = 0
        nonisolated(unsafe) var förstaBit: TimeInterval = 0
        do {
            let svar = try await chatt.fråga(
                "Vad kostar battericellerna och vad ska jag göra före fredag?",
                om: "Acme", projekt: nil, träffar: träffar, historik: [],
                vidDelta: { _ in
                    bitar += 1
                    if förstaBit == 0 { förstaBit = Date().timeIntervalSince(t0) }
                })
            let tid = Date().timeIntervalSince(t0)
            print("Svar (\(String(format: "%.1f", tid)) s):")
            print(svar.text)
            print("")
            print("Hänvisningar: \(svar.hänvisningar.isEmpty ? "inga" : svar.hänvisningar.map(\.titel).joined(separator: ", "))")
            print("Strömmat i \(bitar) bitar, första efter \(String(format: "%.1f", förstaBit)) s")

            Prov.svit("Chatt")
            Prov.kolla(!svar.text.isEmpty, "modellen svarade")
            Prov.kolla(svar.text.contains("2 400") || svar.text.contains("2400"),
                       "svaret använde priset ur underlaget")
            Prov.kolla(!svar.hänvisningar.isEmpty, "svaret hänvisade till underlaget")
            Prov.kolla(bitar > 1, "svaret strömmades i flera bitar (\(bitar))")

            // Den viktigaste egenskapen: att inte hitta på. Frågan går inte
            // att besvara ur underlaget, och då ska modellen säga det.
            print("")
            print("Provar en fråga som underlaget inte svarar på …")
            let utan = try await chatt.fråga(
                "Vem är kundens verkställande direktör och vilket är deras organisationsnummer?",
                om: "Acme", projekt: nil, träffar: träffar, historik: [])
            print(utan.text)
            let säger = utan.text.lowercased()
            let erkänner = ["finns inte", "framgår inte", "saknas", "inget", "ingen uppgift",
                            "kan inte", "hittar inte", "nämns inte", "står inte", "underlaget"]
                .contains { säger.contains($0) }
            Prov.kolla(erkänner, "modellen säger ifrån när svaret inte finns i underlaget")
            Prov.kolla(!säger.contains("556"), "inget påhittat organisationsnummer")

            return Prov.sammanfatta()
        } catch {
            print("Gick inte: \(error.localizedDescription)")
            return 1
        }
    }
}

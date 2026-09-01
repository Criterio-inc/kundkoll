import Foundation

/// Provar skarpt att modellen räknar ut riktiga datum ur relativa uttryck.
///
///     Kundkoll --prov-datum
///
/// "före fredag" är bara meningsfullt tillsammans med dagen det sades, och
/// det är modellen som gör omräkningen. Det här är det som ska mätas, inte
/// antas: att prompten med angivet datum faktiskt ger rätt ÅÅÅÅ-MM-DD.
enum Datumprov {

    static func kör() async -> Int32 {
        Prov.svit("Datum ur relativa uttryck")

        // En onsdag, så att "före fredag" och "nästa vecka" är entydiga nog.
        let onsdag = Uppgift.dag("2026-09-02")!
        let text = """
        Ämne: Uppföljning
        Från: Anna Svensson

        Hej! Som vi sa skickar jag offerten på pallställ före fredag.
        Kan du boka in ett uppföljningsmöte den 15 september?
        Bo återkommer om lagersaldot, han sa inte när.
        """

        let letare = Uppgiftsletare()
        let uppgifter: [Uppgift]
        do {
            uppgifter = try await letare.leta(
                i: text, sammanhang: "ett mejl jag fått", kund: "Acme", datum: onsdag)
        } catch {
            Prov.kolla(false, "modellen svarade: \(error.localizedDescription)")
            return Prov.sammanfatta()
        }

        for u in uppgifter {
            let d = u.senast.map { DateFormatter.iso.string(from: $0) } ?? "—"
            print("  · \(u.vad)  [\(u.vem ?? "?")] när «\(u.när ?? "—")» senast \(d)")
        }

        Prov.kolla(uppgifter.count >= 2, "uppgifterna hittades (\(uppgifter.count))")

        let offert = uppgifter.first { $0.vad.lowercased().contains("offert") }
        Prov.kolla(offert != nil, "offerten är en av dem")
        // Före fredag, sagt en onsdag 2 sep → torsdag 3:e eller fredag 4:e.
        // Båda är rimliga läsningar; det som inte är rimligt är null eller
        // ett datum utanför veckan.
        if let s = offert?.senast {
            Prov.kolla(s >= Uppgift.dag("2026-09-03")! && s <= Uppgift.dag("2026-09-04")!,
                       "«före fredag» en onsdag blir den 3:e eller 4:e")
        } else {
            Prov.kolla(false, "«före fredag» gav inget datum alls")
        }

        let möte = uppgifter.first { $0.vad.lowercased().contains("möte") }
        Prov.lika(möte?.senast, Uppgift.dag("2026-09-15"),
                  "«den 15 september» blir 2026-09-15")

        let saldo = uppgifter.first { $0.vad.lowercased().contains("saldo") }
        if let saldo {
            Prov.lika(saldo.senast, nil, "det som saknar tid får inget påhittat datum")
        }

        return Prov.sammanfatta()
    }
}

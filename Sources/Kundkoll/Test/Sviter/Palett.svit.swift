import Foundation

extension Tester {
    static func palett() {
        Prov.svit("Kommandopaletten")

        func kund(_ namn: String) -> Kommandopalett.Träff {
            .init(slag: .kund(Kund(namn: namn, mapp: URL(fileURLWithPath: "/x/\(namn)"))))
        }
        func uppgift(_ vad: String) -> Kommandopalett.Träff {
            .init(slag: .uppgift(Uppgift(vad: vad),
                                 Kund(namn: "Acme", mapp: URL(fileURLWithPath: "/x/Acme"))))
        }
        let allt = [kund("Corvus"), kund("Acme"), uppgift("Skicka offerten till Corvus"),
                    Kommandopalett.Träff(slag: .minVecka)]

        Prov.lika(Kommandopalett.sök("cor", i: allt).first?.namn, "Corvus",
                  "prefix på kundnamnet vinner")
        Prov.lika(Kommandopalett.sök("corvus", i: allt).count, 2,
                  "uppgiften som nämner kunden finns också med")
        Prov.lika(Kommandopalett.sök("offerten", i: allt).first?.namn,
                  "Skicka offerten till Corvus", "ordprefix inne i en uppgift hittas")
        Prov.lika(Kommandopalett.sök("CORVUS", i: allt).first?.namn, "Corvus",
                  "skiftläge spelar ingen roll")
        Prov.kolla(Kommandopalett.sök("zzz", i: allt).isEmpty,
                   "det som inte finns ger ingenting")
        Prov.lika(Kommandopalett.sök("", i: allt).count, 3,
                  "tom sökning visar kunder och Min vecka, inte uppgifter")
    }
}

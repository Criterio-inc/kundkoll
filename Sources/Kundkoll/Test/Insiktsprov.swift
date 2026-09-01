import Foundation

/// Mäter hur väl den lokala modellen hittar frågeställningar i mötestal.
///
///     Kundkoll --prov-insikter [modell …]
///
/// Facit är stycken ur riktiga möten, avidentifierade. Måttet som betyder
/// mest är falska larm:
/// en assistent som avbryter mötet med påhittade frågor blir avstängd, en som
/// missar en fråga stör ingen.
enum Insiktsprov {

    static let prov: [(text: String, väntat: Bool)] = [
        ("Jag är Anders och jag har lyckats samla fyra av världens mest avancerade språkmodeller i samma rum. Innan vi kör igång tänkte jag att ni får presentera er kort. Claude, vill du börja?", false),
        ("Okej, så dagens ämne. Hur skapar man den optimala afterworken? Jag pratar om den där perfekta fredagskvällen efter jobbet.", false),
        ("Vi behöver kolla vad vi lovade dem i somras om leveranstiden. Jag minns inte om det var sex eller åtta veckor.", true),
        ("Det ska vara spontant nog att kännas fritt, men planerat nog att folk dyker upp. Rätt miljö. Inte för fint.", false),
        ("Vad kostade battericellerna i den förra offerten? Hade vi någon volymrabatt?", true),
        ("Ja precis. Det blev en lång dag men vi kom i mål till slut.", false),
        ("Vi sa något om DMZ i förra mötet men jag kommer inte ihåg vad vi landade i.", true),
        ("Tack för hjälpen. Vi hörs på fredag.", false),
        ("Jag gillar struktur, listor och att bryta ner problem i hanterbara delar.", false),
        ("Kan du kolla vad Bo skrev om lagersaldot i mejlet i augusti?", true),
        ("Den optimala afterworken är en digital detox med öl.", false),
        ("Vi lovade återkomma om priset på pallställ. Vet du vad vi sa?", true),
        // Ordagrant ur den inspelning där livetranskriberingen fallerade.
        ("Okej, då spelar jag in ett möte. Bo hade definierat upp ett 20-tal uppgifter, vilka var det nu igen? Den lyssnar men ingen transkribering syns. Vilka var de 20 uppgifterna?", true),
    ]

    static func kör(modeller: [String]) async -> Int32 {
        let lista = modeller.isEmpty ? [Insikter.standardmodell] : modeller
        for modell in lista {
            let insikter = Insikter(modell: modell)
            guard await insikter.tillgänglig else {
                print("Ollama svarar inte på 11434. Starta den med: ollama serve")
                Prov.svit("Insikter")
                Prov.kolla(false, "Ollama är igång")
                return Prov.sammanfatta()
            }

            print("\n=== \(modell) ===")
            // Första anropet laddar modellen och räknas inte.
            _ = try? await insikter.granska("uppvärmning")

            var rätt = 0, falska = 0, missade = 0
            var tider: [Double] = []
            for (text, väntat) in prov {
                let t0 = Date()
                let fråga = try? await insikter.granska(text)
                tider.append(Date().timeIntervalSince(t0))
                let fick = fråga != nil
                if fick == väntat { rätt += 1 }
                else if fick { falska += 1 }
                else { missade += 1 }
                print("  \(fick == väntat ? "✓" : "✗") [\(String(format: "%.1f", tider.last ?? 0)) s] "
                      + "väntat \(väntat ? "JA " : "nej") fick \(fick ? "JA " : "nej")  «\(text.prefix(42))…»")
                if let fråga { print("        → \(fråga.prefix(88))") }
            }
            let median = tider.sorted()[tider.count / 2]
            print("  \(rätt)/\(prov.count) rätt · \(falska) falska larm · \(missade) missade "
                  + "· median \(String(format: "%.1f", median)) s")

            if modell == lista.last {
                Prov.svit("Insikter")
                Prov.kolla(rätt >= prov.count * 3 / 4,
                           "minst tre fjärdedelar rätt (\(rätt) av \(prov.count))")
                Prov.kolla(falska == 0, "inga falska larm (\(falska))")
                Prov.kolla(median < 5,
                           String(format: "svarar inom fem sekunder (median %.1f s)", median))
            }
        }
        return Prov.sammanfatta()
    }
}

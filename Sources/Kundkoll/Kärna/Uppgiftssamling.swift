import Foundation

/// Samlar in uppgifter från det material som kommer in.
///
/// Möten bidrar med sina åtaganden direkt, eftersom sammanfattningen redan
/// plockat ut dem. Mejl och anteckningar går genom en egen runda.
@MainActor
enum Uppgiftssamling {

    /// Mötets åtaganden till tavlan.
    static func frånMöte(_ sammanfattning: Mötessammanfattning,
                         inspelning: Inspelning, mapp: URL?) {
        guard let kund = Arkivet.shared.kunder.first(where: { $0.namn == inspelning.kund })
        else { return }
        let nya = sammanfattning.åtaganden.map {
            Uppgift(vad: $0.vad, vem: $0.vem, när: $0.när, senast: $0.senast,
                    läge: $0.klart ? .klart : .attGöra,
                    ursprung: .möte,
                    källa: mapp?.path,
                    källtitel: inspelning.titel,
                    projekt: inspelning.projekt,
                    skapad: inspelning.inledd)
        }
        try? Arkivet.shared.läggTill(nya, för: kund)
    }

    /// Om en uppgift kom ur ett visst möte. Mappen är det säkra kännetecknet;
    /// titeln finns kvar för uppgifter som lades upp innan mappen sparades.
    static func hör(_ uppgift: Uppgift, till mapp: URL, titel: String) -> Bool {
        guard uppgift.ursprung == .möte else { return false }
        if let källa = uppgift.källa { return källa == mapp.path }
        return uppgift.källtitel == titel
    }

    /// Letar åtaganden i nyhämtade mejl.
    ///
    /// Bara de senaste och bara de som kommit efter förra genomgången: varje
    /// runda kostar ett modellanrop, och gamla mejl har redan gåtts igenom.
    static func frånMejl(_ mejl: [Mailen.Mejl], kund: Kund) async {
        let sedan = senastGenomgången(kund)
        let nya = mejl
            .filter { ($0.datum ?? .distantPast) > sedan }
            .filter { !$0.text.isEmpty }
            .prefix(10)
        guard !nya.isEmpty else { return }

        let letare = Uppgiftsletare()
        var funna: [Uppgift] = []
        for m in nya {
            let text = "Ämne: \(m.ämne)\nFrån: \(m.avsändarnamn)\n\n\(m.text)"
            guard let u = try? await letare.leta(
                i: text,
                sammanhang: m.skickat ? "ett mejl jag skickat" : "ett mejl jag fått",
                kund: kund.namn,
                datum: m.datum ?? Date()) else { continue }
            funna += u.map {
                Uppgift(vad: $0.vad, vem: $0.vem, när: $0.när, senast: $0.senast,
                        ursprung: .mejl, källtitel: m.ämne, skapad: m.datum ?? Date())
            }
        }
        try? Arkivet.shared.läggTill(funna, för: kund)
        märkGenomgången(kund, till: nya.compactMap(\.datum).max() ?? Date())
    }

    /// Fram till hit har mejlen redan gåtts igenom.
    private static func senastGenomgången(_ kund: Kund) -> Date {
        let nyckel = "kundkoll.uppgifter.\(kund.namn)"
        guard let t = UserDefaults.standard.object(forKey: nyckel) as? Date else {
            // Första gången: bara den senaste månaden, annars går hela
            // mejlhistoriken genom modellen.
            return Date().addingTimeInterval(-30 * 24 * 3600)
        }
        return t
    }

    private static func märkGenomgången(_ kund: Kund, till tid: Date) {
        UserDefaults.standard.set(tid, forKey: "kundkoll.uppgifter.\(kund.namn)")
    }
}

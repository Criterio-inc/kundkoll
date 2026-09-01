import Foundation

/// Läsningen inför ett möte: vad hände sist, vad är olevererat, vad har
/// kommit in sedan dess.
///
/// Byggs helt ur det som redan finns — förra mötets sammanfattning, tavlans
/// öppna åtaganden, mejlcachen. Ingen modell och ingen väntan: briefen ska
/// finnas på skärmen innan mötet börjar, inte strax efter.
struct Briefing {
    var kund: String
    var möte: Kalendern.Möte?
    /// Senaste mötet — helst det förra i samma serie som kalendermötet.
    var senaste: (Inspelning, URL)?
    var öppnaUppgifter: [Uppgift]
    /// Frågorna som lämnades obesvarade sist.
    var öppnaFrågor: [String]
    /// Mejl som kommit efter senaste mötet.
    var mejlSedanSist: [Mailen.Mejl]

    var tom: Bool {
        senaste == nil && öppnaUppgifter.isEmpty && mejlSedanSist.isEmpty
    }

    /// Ren hopsättning, utbruten för att kunna provas.
    static func bygg(kund: String,
                     möte: Kalendern.Möte?,
                     inspelningar: [(Inspelning, URL)],
                     uppgifter: [Uppgift],
                     mejl: [Mailen.Mejl]) -> Briefing {
        // Heter kalendermötet som en känd serie är det den förra i serien
        // man vill läsa på, inte nödvändigtvis det allra senaste mötet.
        var senaste = inspelningar.first
        if let titel = möte?.titel {
            let nyckel = Mötesserie.nyckel(titel)
            if !nyckel.isEmpty,
               let iSerien = inspelningar.first(where: {
                   Mötesserie.nyckel($0.0.titel) == nyckel
               }) {
                senaste = iSerien
            }
        }

        let öppna = uppgifter
            .filter { $0.läge != .klart }
            .sorted { ($0.senast ?? .distantFuture, $0.skapad)
                    < ($1.senast ?? .distantFuture, $1.skapad) }

        // Utan ett tidigare möte är "sedan sist" de senaste två veckorna.
        let sedan = senaste?.0.inledd ?? Date().addingTimeInterval(-14 * 24 * 3600)
        let nya = mejl
            .filter { ($0.datum ?? .distantPast) > sedan }
            .sorted { ($0.datum ?? .distantPast) > ($1.datum ?? .distantPast) }

        return Briefing(kund: kund, möte: möte, senaste: senaste,
                        öppnaUppgifter: öppna,
                        öppnaFrågor: senaste?.0.sammanfattning?.öppet ?? [],
                        mejlSedanSist: Array(nya.prefix(5)))
    }

    @MainActor
    static func bygg(för kund: Kund, möte: Kalendern.Möte?,
                     arkiv: Arkivet = .shared) -> Briefing {
        bygg(kund: kund.namn,
             möte: möte,
             inspelningar: arkiv.inspelningar(för: kund),
             uppgifter: arkiv.uppgifter(för: kund),
             mejl: arkiv.mailcache(för: kund)?.mejl ?? [])
    }
}

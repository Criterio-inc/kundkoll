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
    var senaste: Möte?
    var öppnaUppgifter: [Uppgift]
    /// Frågorna som lämnades obesvarade sist.
    var öppnaFrågor: [String]
    /// Mejl som kommit efter senaste mötet.
    var mejlSedanSist: [Mailen.Mejl]
    /// Sådant jag väntar på från någon annan, som passerat sitt datum utan
    /// att något mejl kommit från den personen sedan dess.
    var väntarUtanSvar: [Uppgift] = []
    /// Projektet mötet hör till: kopplat för hand i kalendern, annars det
    /// förra mötet i serien ligger i. Med projektets lägesbild, om den finns.
    var projekt: Projekt?
    var lägesbild: Lägesbild?

    var tom: Bool {
        senaste == nil && öppnaUppgifter.isEmpty && mejlSedanSist.isEmpty
    }

    /// Ren hopsättning, utbruten för att kunna provas.
    static func bygg(kund: String,
                     möte: Kalendern.Möte?,
                     inspelningar: [Möte],
                     uppgifter: [Uppgift],
                     mejl: [Mailen.Mejl],
                     idag: Date = Date()) -> Briefing {
        // Heter kalendermötet som en känd serie är det den förra i serien
        // man vill läsa på, inte nödvändigtvis det allra senaste mötet.
        var senaste = inspelningar.first
        if let titel = möte?.titel {
            let nyckel = Mötesserie.nyckel(titel)
            if !nyckel.isEmpty,
               let iSerien = inspelningar.first(where: {
                   Mötesserie.nyckel($0.inspelning.titel) == nyckel
               }) {
                senaste = iSerien
            }
        }

        let öppna = uppgifter
            .filter { $0.läge != .klart }
            .sorted { ($0.senast ?? .distantFuture, $0.skapad)
                    < ($1.senast ?? .distantFuture, $1.skapad) }

        // Utan ett tidigare möte är "sedan sist" de senaste två veckorna.
        let sedan = senaste?.inspelning.inledd ?? Date().addingTimeInterval(-14 * 24 * 3600)
        let nya = mejl
            .filter { ($0.datum ?? .distantPast) > sedan }
            .sorted { ($0.datum ?? .distantPast) > ($1.datum ?? .distantPast) }

        // Ett väntat åtagande vars dag passerat: har personen hört av sig
        // sedan dess räknas det som att det är på gång, annars sägs det här.
        let dagensStart = Calendar.current.startOfDay(for: idag)
        let utanSvar = öppna.filter { u in
            guard !u.mitt, let vem = u.vem, let senast = u.senast, senast < dagensStart else { return false }
            return !mejl.contains { m in
                !m.skickat && (m.datum ?? .distantPast) > senast && avsändare(m.avsändare, är: vem)
            }
        }

        return Briefing(kund: kund, möte: möte, senaste: senaste,
                        öppnaUppgifter: öppna,
                        öppnaFrågor: senaste.map { Mötesserie.öppnaFrågor(tillOchMed: $0.inspelning, bland: inspelningar) } ?? [],
                        mejlSedanSist: Array(nya.prefix(5)),
                        väntarUtanSvar: utanSvar)
    }

    /// Om ett mejls avsändare («Anna Berg <anna@x.se>») är personen bakom
    /// ett «vem» («Anna», «Anna Berg»). Förnamnet avgör; ett kort «vem»
    /// under tre tecken matchar aldrig.
    static func avsändare(_ avsändare: String, är vem: String) -> Bool {
        guard let förnamn = vem.lowercased().split(separator: " ").first.map(String.init),
              förnamn.count >= 3 else { return false }
        let ord = avsändare.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "åäöéü")).inverted)
        return ord.contains(förnamn)
    }

    @MainActor
    static func bygg(för kund: Kund, möte: Kalendern.Möte?,
                     arkiv: Arkivet? = nil) -> Briefing {
        let arkiv = arkiv ?? .shared
        var b = bygg(kund: kund.namn,
                     möte: möte,
                     inspelningar: arkiv.inspelningar(för: kund),
                     uppgifter: arkiv.uppgifter(för: kund),
                     mejl: arkiv.mailcache(för: kund)?.mejl ?? [])
        // Lägesbilden och briefen läste förut aldrig varandra: sidan inför
        // mötet sa vad som sades sist men inte var projektet står.
        let projekt = arkiv.projekt(för: kund)
        b.projekt = möte.flatMap { m in
            arkiv.möteskopplingar(för: kund)[m.id].flatMap { id in projekt.first { $0.id == id } }
        } ?? b.senaste.flatMap { arkiv.projekt(innehållande: $0.mapp, hos: kund) }
        b.lägesbild = b.projekt.flatMap { Läget.läs(kund: kund, projekt: $0) }
        return b
    }
}

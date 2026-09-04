import Foundation

/// Allt appen gör i bakgrunden, på ett ställe.
///
/// Mejlhämtning, uppgiftsrundor, lägesbilder, dokumentinläsning och
/// efterbearbetning bodde förut var för sig: som en flaggvariabel i en flik,
/// en global mängd, ett par publicerade fält. Det som pågick syntes bara i
/// den flik som råkade starta det, och ett fel i bakgrunden såg ut som
/// «inget hittades». Här får varje jobb ett namn, ett steg, ett kvitto när
/// det är klart, och ett fel som ligger kvar tills det stängs. Raden längst
/// ned i fönstret och knappen som startade jobbet läser samma sak.
@MainActor
final class Arbeten: ObservableObject {
    static let delad = Arbeten()

    enum Slag: String, Codable, CaseIterable {
        case mejlhämtning, uppgiftsrunda, anteckningsrunda, lägesbild
        case indexering, görKlart, efterbearbetning

        var namn: String {
            switch self {
            case .mejlhämtning: "Hämtar mejl"
            case .uppgiftsrunda: "Letar åtaganden i mejl"
            case .anteckningsrunda: "Letar åtaganden i anteckning"
            case .lägesbild: "Skriver lägesbild"
            case .indexering: "Läser in dokument"
            case .görKlart: "Gör inspelning klar"
            case .efterbearbetning: "Skriver rent mötet"
            }
        }
    }

    struct Arbete: Identifiable {
        let id: UUID
        let slag: Slag
        let kund: String
        let kundmapp: URL
        var titel: String
        var steg: String
        var andel: Double?
        let startad: Date
        /// Startat av Pär, inte av appen.
        let beställt: Bool
        /// Skickar kundmaterial till ett moln.
        let lämnarDatorn: Bool
    }

    /// Det som blir kvar när jobbet är klart. Skrivs till kundmappen så att
    /// «vad hände i morse» går att svara på efteråt.
    struct Kvitto: Codable, Identifiable, Equatable {
        var id = UUID()
        var slag: Slag
        var kund: String
        var titel: String
        var startad: Date
        var klar: Date
        var resultat: String?
        var fel: String?
        var modell: String?
        var lämnadeDatorn = false

        /// «10:42 · 3 nya på tavlan ur 12 mejl · Lokalt · qwen3:8b»
        var rad: String {
            var delar = [DateFormatter.klocka.string(from: klar)]
            if let fel { delar.append("Stannade: \(fel)") } else if let resultat { delar.append(resultat) }
            if let modell { delar.append(modell) }
            if lämnadeDatorn { delar.append("lämnade datorn") }
            return delar.joined(separator: " · ")
        }
        var föll: Bool { fel != nil }
    }

    /// Ett grepp om ett pågående jobb. Metoderna går att anropa från vilken
    /// tråd som helst; de hoppar själva till huvudaktören.
    struct Handtag: Sendable, Equatable {
        let id: UUID
        nonisolated func steg(_ text: String, andel: Double? = nil) {
            let id = id
            Task { @MainActor in Arbeten.delad.uppdatera(id, steg: text, andel: andel) }
        }
        nonisolated func klart(_ resultat: String, modell: String? = nil) {
            let id = id
            Task { @MainActor in Arbeten.delad.avsluta(id, resultat: resultat, fel: nil, modell: modell) }
        }
        nonisolated func föll(_ fel: String) {
            let id = id
            Task { @MainActor in Arbeten.delad.avsluta(id, resultat: nil, fel: fel, modell: nil) }
        }
    }

    @Published private(set) var pågående: [Arbete] = []
    /// Fel som ligger kvar tills de stängs, som Importkö.fel.
    @Published private(set) var fel: [Kvitto] = []
    /// Senaste kvitto per kund och slag, det som knappen visar.
    @Published private(set) var senaste: [String: Kvitto] = [:]

    private static func nyckel(_ slag: Slag, _ kund: String) -> String { "\(kund)|\(slag.rawValue)" }

    var pågårNågot: Bool { !pågående.isEmpty }
    func pågår(_ slag: Slag, kund: Kund) -> Bool { arbete(slag, kund: kund) != nil }
    func pågår(hos kund: Kund) -> Bool { pågående.contains { $0.kund == kund.namn } }
    func arbete(_ slag: Slag, kund: Kund) -> Arbete? {
        pågående.first { $0.slag == slag && $0.kund == kund.namn }
    }

    /// Startar ett jobb. Ger nil om samma slag redan pågår hos kunden: två
    /// mejlhämtningar eller två uppgiftsrundor samtidigt skrev över
    /// varandras resultat, så det andra får vänta på nästa tillfälle.
    func starta(_ slag: Slag, kund: Kund, titel: String? = nil,
                beställt: Bool = false, lämnarDatorn: Bool = false) -> Handtag? {
        guard !pågår(slag, kund: kund) else { return nil }
        let a = Arbete(id: UUID(), slag: slag, kund: kund.namn, kundmapp: kund.mapp,
                       titel: titel ?? slag.namn, steg: "", andel: nil, startad: Date(),
                       beställt: beställt, lämnarDatorn: lämnarDatorn)
        pågående.append(a)
        return Handtag(id: a.id)
    }

    func uppdatera(_ id: UUID, steg: String, andel: Double?) {
        guard let i = pågående.firstIndex(where: { $0.id == id }) else { return }
        pågående[i].steg = steg
        pågående[i].andel = andel
    }

    func avsluta(_ id: UUID, resultat: String?, fel: String?, modell: String?) {
        guard let i = pågående.firstIndex(where: { $0.id == id }) else { return }
        let a = pågående.remove(at: i)
        let k = Kvitto(slag: a.slag, kund: a.kund, titel: a.titel, startad: a.startad,
                       klar: Date(), resultat: resultat, fel: fel, modell: modell,
                       lämnadeDatorn: a.lämnarDatorn)
        senaste[Self.nyckel(a.slag, a.kund)] = k
        if let fel {
            self.fel.append(k)
            Logg.fel("\(a.slag.namn) hos \(a.kund): \(fel)", i: "Arbeten")
        }
        skriv(k, till: a.kundmapp)
    }

    func stängFel(_ id: UUID) { fel.removeAll { $0.id == id } }

    /// Senaste kvittot, ur minnet eller ur kundmappens logg.
    func senasteKvitto(_ slag: Slag, kund: Kund) -> Kvitto? {
        if let k = senaste[Self.nyckel(slag, kund.namn)] { return k }
        let k = Self.logg(i: kund.mapp).last { $0.slag == slag }
        if let k { senaste[Self.nyckel(slag, kund.namn)] = k }
        return k
    }

    /// Raden längst ned: det första jobbet, och hur många till.
    var beskrivning: String? {
        guard let a = pågående.first else { return nil }
        var text = "\(a.kund): \(a.titel)"
        if !a.steg.isEmpty { text += " — \(a.steg)" }
        if pågående.count > 1 { text += " · +\(pågående.count - 1) till" }
        return text
    }

    // MARK: - Kvittona på disk

    static func loggfil(_ kundmapp: URL) -> URL { kundmapp.appending(path: ".kundkoll/arbetslogg.json") }

    static func logg(i kundmapp: URL) -> [Kvitto] {
        guard let data = try? Data(contentsOf: loggfil(kundmapp)),
              let k = try? JSONDecoder.kundkoll.decode([Kvitto].self, from: data) else { return [] }
        return k
    }

    /// De senaste kvittona att visa i «Sedan sist», utan upprepningar: två
    /// dokumentgenomgångar i rad som båda sa «inget nytt» är ett besked, inte
    /// två. Samma slag med samma utfall räknas en gång, det senaste.
    static func senasteKvitton(i kundmapp: URL, antal: Int = 2) -> [Kvitto] {
        var sedda: Set<String> = []
        var ut: [Kvitto] = []
        for k in logg(i: kundmapp).reversed() {
            let nyckel = "\(k.slag.rawValue)|\(k.resultat ?? "")|\(k.fel ?? "")"
            guard !sedda.contains(nyckel) else { continue }
            sedda.insert(nyckel)
            ut.append(k)
            if ut.count == antal { break }
        }
        return ut
    }

    private func skriv(_ k: Kvitto, till kundmapp: URL) {
        var alla = Self.logg(i: kundmapp)
        alla.append(k)
        // De senaste tvåhundra räcker för att svara på «vad hände i veckan».
        if alla.count > 200 { alla.removeFirst(alla.count - 200) }
        let fil = Self.loggfil(kundmapp)
        try? FileManager.default.createDirectory(at: fil.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let data = try? JSONEncoder.kundkoll.encode(alla) {
            try? data.write(to: fil, options: .atomic)
        }
    }
}

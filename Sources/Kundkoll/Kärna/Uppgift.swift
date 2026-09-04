import Foundation

/// Något som ska göras, oavsett var det kom upp.
///
/// Åtaganden dyker upp i mötessammanfattningar, i mejl och i anteckningar, och
/// hamnade tidigare på tre olika ställen. Här samlas de.
struct Uppgift: Codable, Hashable, Identifiable {
    enum Läge: String, Codable, CaseIterable, Identifiable {
        case attGöra, pågår, klart
        var id: String { rawValue }
        var namn: String {
            switch self {
            case .attGöra: "Att göra"
            case .pågår: "Pågår"
            case .klart: "Klart"
            }
        }
    }

    enum Ursprung: String, Codable {
        case möte, mejl, anteckning, egen
        var ikon: String {
            switch self {
            case .möte: "waveform"
            case .mejl: "envelope"
            case .anteckning: "note.text"
            case .egen: "square.and.pencil"
            }
        }
    }

    var id = UUID()
    var vad: String
    var vem: String?
    /// När, som det sades — "före fredag", "nästa vecka".
    var när: String?
    /// När som ett riktigt datum, när det gick att räkna ut. Det är detta
    /// tavlan sorterar på och det som blir rött när det passerats.
    var senast: Date?
    /// Påminnelsen i macOS Påminnelser, om uppgiften lagts dit.
    var påminnelse: String?
    var läge: Läge = .attGöra
    var ursprung: Ursprung = .egen
    /// Var den kom ifrån, så man kan gå tillbaka och läsa sammanhanget.
    var källa: String?
    var källtitel: String?
    var projekt: String?
    var skapad = Date()
    var ändrad = Date()

    init(id: UUID = UUID(), vad: String, vem: String? = nil, när: String? = nil,
         senast: Date? = nil, påminnelse: String? = nil,
         läge: Läge = .attGöra, ursprung: Ursprung = .egen, källa: String? = nil,
         källtitel: String? = nil, projekt: String? = nil,
         skapad: Date = Date(), ändrad: Date = Date()) {
        self.id = id
        self.vad = vad
        self.vem = vem
        self.när = när
        self.senast = senast
        self.påminnelse = påminnelse
        self.läge = läge
        self.ursprung = ursprung
        self.källa = källa
        self.källtitel = källtitel
        self.projekt = projekt
        self.skapad = skapad
        self.ändrad = ändrad
    }

    /// Skriven för hand så att ett nytt fält inte gör tidigare sparade
    /// uppgifter oläsbara.
    init(from avkodare: Decoder) throws {
        let c = try avkodare.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        vad = try c.decodeIfPresent(String.self, forKey: .vad) ?? ""
        vem = try c.decodeIfPresent(String.self, forKey: .vem)
        när = try c.decodeIfPresent(String.self, forKey: .när)
        senast = try c.decodeIfPresent(Date.self, forKey: .senast)
        påminnelse = try c.decodeIfPresent(String.self, forKey: .påminnelse)
        läge = try c.decodeIfPresent(Läge.self, forKey: .läge) ?? .attGöra
        ursprung = try c.decodeIfPresent(Ursprung.self, forKey: .ursprung) ?? .egen
        källa = try c.decodeIfPresent(String.self, forKey: .källa)
        källtitel = try c.decodeIfPresent(String.self, forKey: .källtitel)
        projekt = try c.decodeIfPresent(String.self, forKey: .projekt)
        skapad = try c.decodeIfPresent(Date.self, forKey: .skapad) ?? Date()
        ändrad = try c.decodeIfPresent(Date.self, forKey: .ändrad) ?? Date()
    }

    /// Om tiden har runnit ut utan att uppgiften blivit klar.
    var försenad: Bool {
        guard let senast, läge != .klart else { return false }
        return senast < Calendar.current.startOfDay(for: Date())
    }

    /// Tolkar "2026-09-05" till ett datum. Det är formatet modellerna ombeds
    /// svara i; allt annat — "null", "före fredag" — blir ingenting.
    static func dag(_ text: String?) -> Date? {
        guard let text else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: text.trimmingCharacters(in: .whitespaces))
    }

    /// Två uppgifter räknas som samma sak om orden i stort sett överlappar.
    /// Samma åtagande nämns ofta i både ett möte och ett mejl.
    ///
    /// Orden jämförs på sina första bokstäver, inte hela. Svenskan böjer, och
    /// "skicka offert på pallställ" och "skicka offerten på pallställen" är
    /// samma sak — utan kapningen delar de bara två ord av fem.
    /// Samma åtagande i annan formulering. Orden i «vad» jämförs kapade;
    /// ett kort namn räknas (Bo, Eva), småord räknas inte. Olika «vem» eller
    /// datum mer än en vecka isär är olika åtaganden: «boka möte med Anna»
    /// hindrade förut «boka möte med Bo».
    func liknar(_ annan: Uppgift) -> Bool {
        let a = Self.stammar(vad), b = Self.stammar(annan.vad)
        guard !a.isEmpty, !b.isEmpty else { return false }
        if let x = vem, let y = annan.vem,
           Self.förnamn(x) != Self.förnamn(y) { return false }
        if let d1 = senast, let d2 = annan.senast, abs(d1.timeIntervalSince(d2)) > 7 * 86400 {
            return false
        }
        return Double(a.intersection(b).count) / Double(min(a.count, b.count)) >= 0.75
    }

    private static func förnamn(_ s: String) -> String {
        s.lowercased().split(separator: " ").first.map(String.init) ?? s.lowercased()
    }

    static let småord: Set<String> = [
        "och", "att", "med", "till", "för", "den", "det", "som", "ett", "en", "på", "av",
        "om", "vi", "ni", "de", "är", "ska", "kan", "the", "and", "to", "for", "of", "in",
    ]

    static func stammar(_ text: String) -> Set<String> {
        Set(text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 && !småord.contains($0) }
            .map { String($0.prefix(5)) })
    }
}

/// Plockar ut uppgifter ur material som kommer in.
actor Uppgiftsletare {

    private let chatt: Chatt
    init(chatt: Chatt = Chatt()) { self.chatt = chatt }

    /// Letar åtaganden i en text — ett mejl, en anteckning.
    ///
    /// Mötena behöver inte gå den här vägen: deras åtaganden står redan i
    /// sammanfattningen.
    func leta(i text: String, sammanhang: String, kund: String,
              datum: Date = Date(), automatiskt: Bool = false) async throws -> [Uppgift] {
        guard text.count > 60 else { return [] }

        let dag: String = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.locale = Locale(identifier: "en_US_POSIX")
            return f.string(from: datum)
        }()
        let uppdrag = """
        Här är \(sammanhang) som rör kunden \(kund). Det är skrivet \(dag).

        Plocka ut sådant som någon ska göra — åtaganden, utlovade leveranser, \
        saker att återkomma om. Svara som JSON:

        {"uppgifter": [{"vad": "…", "vem": "namn eller null", \
        "när": "som det stod, eller null", "senast": "ÅÅÅÅ-MM-DD eller null"}]}

        "senast" är sista dagen som ett riktigt datum, räknat från \(dag) — \
        "före fredag" blir fredagens datum. Går det inte att räkna ut, null.

        Ta bara med sådant som verkligen står där. Hellre en tom lista än en \
        påhittad uppgift. Beskriv varje uppgift kort och konkret på svenska, \
        som en att-göra-rad. Svara med enbart JSON.

        \(text.prefix(12_000))
        """

        let svar = try await chatt.fråga(uppdrag, om: kund, projekt: nil,
                                         träffar: [], historik: [], automatiskt: automatiskt,
                                         uppdrag: .utdrag)
        senasteSvar = svar.text
        // Ett svar utan JSON är ett fel, inte «inga uppgifter»: bokfördes
        // det som genomgånget var mejlets åtaganden borta för gott.
        guard let tolkade = Self.tolka(svar.text) else { throw Fel.otolkbart }
        return tolkade
    }

    enum Fel: LocalizedError {
        case otolkbart
        var errorDescription: String? {
            switch self {
            case .otolkbart: "Modellen svarade med text i stället för den lista appen bad om."
            }
        }
    }

    /// Vilken modell letaren använder, för kvitton och besked.
    nonisolated var etikett: String { chatt.etikett }

    /// Modellens råa svar från senaste letningen, för provläget: när
    /// tolkningen ger noll uppgifter vill man se vad som faktiskt kom.
    private(set) var senasteSvar = ""

    /// nil när svaret inte gick att tolka; en tom lista när modellen
    /// svarade rätt och inte hittade något.
    static func tolka(_ text: String) -> [Uppgift]? {
        guard let data = Modellsvar.json(ur: text) else { return nil }

        struct Rå: Decodable {
            struct U: Decodable {
                let vad: String; let vem: String?; let när: String?; let senast: String?
            }
            let uppgifter: [U]?
        }
        guard let rå = try? JSONDecoder().decode(Rå.self, from: data) else { return nil }
        return (rå.uppgifter ?? [])
            .filter { $0.vad.count > 5 }
            .map { Uppgift(vad: $0.vad, vem: tomSomNil($0.vem), när: tomSomNil($0.när),
                           senast: Uppgift.dag(tomSomNil($0.senast))) }
    }

    private static func tomSomNil(_ s: String?) -> String? { Modellsvar.tomSomNil(s) }
}

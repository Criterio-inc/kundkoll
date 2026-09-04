import Foundation

/// Vad ett möte landade i.
///
/// Ett fyrtio minuter långt samtal blir fyra hundra rader transkript. Det man
/// behöver därifrån är tre saker: vad beslutades, vad lovade jag, och vad är
/// fortfarande öppet. Resten är underlag man går tillbaka till vid behov.
struct Mötessammanfattning: Codable, Hashable {
    var kärna: String
    var beslut: [String]
    var åtaganden: [Åtagande]
    var öppet: [String]
    var skriven = Date()
    /// Modellen som skrev den, som «Lokalt · qwen3:8b». Saknas i äldre filer.
    var modell: String?
    /// Kort från förra mötet i serien som enligt det här mötet verkar
    /// avklarade. Ett förslag, aldrig en stängning: kortet får en bock att
    /// bekräfta med.
    var verkarKlara: [Klartbelägg] = []
    /// Förra mötets öppna frågor som fick svar i det här mötet.
    var besvarade: [String] = []

    /// Ett kort som verkar klart, och meningen ur transkriptet som säger det.
    struct Klartbelägg: Codable, Hashable {
        var kort: UUID
        var belägg: String
    }

    struct Åtagande: Codable, Hashable, Identifiable {
        var id = UUID()
        var vad: String
        /// Vem som ska göra det, med namnet som står i transkriptet.
        var vem: String?
        /// När, som det sades — "före fredag", "nästa vecka".
        var när: String?
        /// När som ett riktigt datum, när modellen kunde räkna ut det.
        var senast: Date?
        var klart = false

        init(id: UUID = UUID(), vad: String, vem: String? = nil,
             när: String? = nil, senast: Date? = nil, klart: Bool = false) {
            self.id = id
            self.vad = vad
            self.vem = vem
            self.när = när
            self.senast = senast
            self.klart = klart
        }

        /// Skriven för hand: se `Inspelning`.
        init(from avkodare: Decoder) throws {
            let c = try avkodare.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            vad = try c.decodeIfPresent(String.self, forKey: .vad) ?? ""
            vem = try c.decodeIfPresent(String.self, forKey: .vem)
            när = try c.decodeIfPresent(String.self, forKey: .när)
            senast = try c.decodeIfPresent(Date.self, forKey: .senast)
            klart = try c.decodeIfPresent(Bool.self, forKey: .klart) ?? false
        }
    }

    var tom: Bool { beslut.isEmpty && åtaganden.isEmpty && öppet.isEmpty }

    init(kärna: String, beslut: [String], åtaganden: [Åtagande],
         öppet: [String], skriven: Date = Date(), modell: String? = nil,
         verkarKlara: [Klartbelägg] = [], besvarade: [String] = []) {
        self.kärna = kärna
        self.beslut = beslut
        self.åtaganden = åtaganden
        self.öppet = öppet
        self.skriven = skriven
        self.modell = modell
        self.verkarKlara = verkarKlara
        self.besvarade = besvarade
    }

    /// Ligger inne i möte.json. Faller den går hela inspelningen förlorad ur
    /// listan, så den läses lika försiktigt som inspelningen själv.
    init(from avkodare: Decoder) throws {
        let c = try avkodare.container(keyedBy: CodingKeys.self)
        kärna = try c.decodeIfPresent(String.self, forKey: .kärna) ?? ""
        beslut = try c.decodeIfPresent([String].self, forKey: .beslut) ?? []
        åtaganden = try c.decodeIfPresent([Åtagande].self, forKey: .åtaganden) ?? []
        öppet = try c.decodeIfPresent([String].self, forKey: .öppet) ?? []
        skriven = try c.decodeIfPresent(Date.self, forKey: .skriven) ?? Date()
        modell = try c.decodeIfPresent(String.self, forKey: .modell)
        verkarKlara = try c.decodeIfPresent([Klartbelägg].self, forKey: .verkarKlara) ?? []
        besvarade = try c.decodeIfPresent([String].self, forKey: .besvarade) ?? []
    }
}

/// Skriver sammanfattningen med den modell som valts för chatten.
actor Sammanfattare {

    private let chatt: Chatt

    init(chatt: Chatt = Chatt()) { self.chatt = chatt }

    /// Ett transkript kan vara långt. Det som betyder något för besluten sägs
    /// nästan alltid i klartext, så hela texten skickas — men kapad, så att en
    /// tre timmar lång inspelning inte spränger fönstret.
    private let maxTecken = 60_000

    /// Det förra mötet i serien lämnade efter sig: öppna kort på tavlan och
    /// obesvarade frågor. Skickas med så att modellen kan säga vilka som
    /// verkar avklarade respektive besvarade i det här mötet.
    struct Förra: Sendable {
        struct Kort: Sendable { let id: UUID; let vad: String }
        var öppnaKort: [Kort] = []
        var öppnaFrågor: [String] = []
        var tom: Bool { öppnaKort.isEmpty && öppnaFrågor.isEmpty }
    }

    /// `automatiskt` när ingen tryckte: efter ett möte och efter en import.
    /// Då körs bara lokalt, se `Chatt.fråga`.
    func skriv(för inspelning: Inspelning, kund: String,
               automatiskt: Bool = false, förra: Förra? = nil) async throws -> Mötessammanfattning {
        let rader = inspelning.yttranden.map { y in
            "[\(y.tidsstämpel)] \(y.etikett(inspelning.röstnamn, enspårig: inspelning.enspårig)): \(y.text)"
        }
        var text = rader.joined(separator: "\n")
        if text.count > maxTecken {
            // Slutet av ett möte bär besluten; början bär sammanhanget.
            let halva = maxTecken / 2
            text = String(text.prefix(halva)) + "\n\n[…]\n\n" + String(text.suffix(halva))
        }

        let dag: String = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.locale = Locale(identifier: "en_US_POSIX")
            return f.string(from: inspelning.inledd)
        }()
        let uppdrag = """
        Här är transkriptet från ett möte med kunden \(kund), hållet \(dag).

        Sammanfatta det som JSON med exakt dessa fält:

        {
          "kärna": "två eller tre meningar om vad mötet handlade om",
          "beslut": ["det som faktiskt bestämdes"],
          "åtaganden": [{"vad": "…", "vem": "namn eller null", \
        "när": "som det sades, eller null", "senast": "ÅÅÅÅ-MM-DD eller null"}],
          "öppet": ["frågor som lämnades obesvarade"]
        }

        "senast" är sista dagen som ett riktigt datum, räknat från mötesdagen \
        \(dag) — "före fredag" blir fredagens datum. Går det inte att räkna \
        ut, null.

        Den som spelade in mötet heter \(Inställningar.användarnamn) och talar \
        som «Jag» i transkriptet. När det är \(Inställningar.användarnamn) som \
        ska göra något, skriv "jag" som vem; när någon annan lovat något, \
        skriv den personens namn.

        Ta bara med sådant som verkligen sades. Hellre en tom lista än ett
        påhittat beslut. Skriv på svenska, kort och konkret, utan artigheter.
        Svara med enbart JSON.
        \(Self.förradel(förra))
        Transkript:
        \(text)
        """

        let svar = try await chatt.fråga(uppdrag, om: kund, projekt: inspelning.projekt,
                                         träffar: [], historik: [], automatiskt: automatiskt,
                                         uppdrag: .utdrag)
        guard var tolkad = Self.tolka(svar.text, förra: förra, transkript: text) else { throw Fel.otolkbart }
        tolkad.modell = chatt.etikett
        return tolkad
    }

    /// Avsnittet om förra mötet, med numrerade rader så att modellen kan
    /// svara med nummer i stället för att skriva om texten.
    static func förradel(_ förra: Förra?) -> String {
        guard let förra, !förra.tom else { return "" }
        var rader = ["", "Förra mötet i samma serie lämnade följande efter sig."]
        if !förra.öppnaKort.isEmpty {
            rader.append("Öppna åtaganden:")
            for (i, k) in förra.öppnaKort.enumerated() { rader.append("  \(i + 1). \(k.vad)") }
            rader.append("Lägg till fältet \"avklarade\": [{\"nummer\": 1, \"belägg\": \"…\"}] för de åtaganden "
                         + "som enligt det här mötet är gjorda. \"belägg\" är den mening ur transkriptet, ordagrant, "
                         + "där det sägs att det är gjort. Något som ännu inte är gjort, som skjuts upp eller som "
                         + "ska göras senare hör inte hit. Är det oklart, utelämna.")
        }
        if !förra.öppnaFrågor.isEmpty {
            rader.append("Obesvarade frågor:")
            for (i, f) in förra.öppnaFrågor.enumerated() { rader.append("  \(i + 1). \(f)") }
            rader.append("Lägg till fältet \"besvarade\": [{\"nummer\": 1, \"belägg\": \"…\"}] för de frågor "
                         + "som fick ett svar i det här mötet. \"belägg\" är meningen ur transkriptet, ordagrant, "
                         + "där svaret ges. En fråga som fortfarande är öppen hör inte hit.")
        }
        rader.append("")
        return rader.joined(separator: "\n")
    }

    /// Modeller lägger gärna JSON i en kodruta, eller skriver en rad före.
    /// Med `förra` översätts numren i «avklarade» och «besvarade» till kortens
    /// id och frågornas text. Med `transkript` krävs dessutom att belägget
    /// modellen anger faktiskt står i transkriptet: ett påhittat citat fäller
    /// förslaget. Uppmätt: utan belägg räknade qwen3 ett uppskjutet besök
    /// som gjort; med belägg gjorde den det inte.
    static func tolka(_ text: String, förra: Förra? = nil, transkript: String? = nil) -> Mötessammanfattning? {
        guard let data = Modellsvar.json(ur: text) else { return nil }

        /// Ett nummer med belägg, som modellen kan ha skrivit som objekt,
        /// som tal eller som text.
        struct Tal: Decodable {
            let värde: Int?
            let belägg: String?
            enum Nycklar: String, CodingKey { case nummer, belägg }
            init(from d: Decoder) throws {
                if let c = try? d.container(keyedBy: Nycklar.self) {
                    if let i = try? c.decode(Int.self, forKey: .nummer) { värde = i }
                    else { värde = (try? c.decode(String.self, forKey: .nummer)).flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } }
                    belägg = try? c.decode(String.self, forKey: .belägg)
                    return
                }
                let c = try d.singleValueContainer()
                belägg = nil
                if let i = try? c.decode(Int.self) { värde = i }
                else if let s = try? c.decode(String.self) { värde = Int(s.trimmingCharacters(in: .whitespaces)) }
                else { värde = nil }
            }
        }
        struct Rå: Decodable {
            struct Å: Decodable {
                let vad: String; let vem: String?; let när: String?; let senast: String?
            }
            let kärna: String?
            let beslut: [String]?
            let åtaganden: [Å]?
            let öppet: [String]?
            let avklarade: [Tal]?
            let besvarade: [Tal]?
        }
        guard let rå = try? JSONDecoder().decode(Rå.self, from: data) else { return nil }
        func plocka<T>(_ tal: [Tal]?, ur lista: [T]) -> [(T, String)] {
            (tal ?? []).compactMap { t -> (T, String)? in
                guard let n = t.värde, n >= 1, n <= lista.count else { return nil }
                let belägg = t.belägg?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if let transkript, !finns(belägg, i: transkript) { return nil }
                return (lista[n - 1], belägg)
            }
        }
        return Mötessammanfattning(
            kärna: rå.kärna ?? "",
            beslut: rå.beslut ?? [],
            åtaganden: (rå.åtaganden ?? []).map {
                .init(vad: Modellsvar.utanVäntaPå($0.vad), vem: tomSomNil($0.vem), när: tomSomNil($0.när),
                      senast: Uppgift.dag(tomSomNil($0.senast)))
            },
            öppet: rå.öppet ?? [],
            verkarKlara: plocka(rå.avklarade, ur: förra?.öppnaKort ?? []).map { .init(kort: $0.0.id, belägg: $0.1) },
            besvarade: plocka(rå.besvarade, ur: förra?.öppnaFrågor ?? []).map(\.0))
    }

    /// Om ett citat står i transkriptet: hela meningen som delsträng, eller
    /// alla dess ord på en och samma rad. Kortare citat än tolv tecken räknas
    /// inte, de kan matcha av en slump.
    static func finns(_ citat: String, i transkript: String) -> Bool {
        let c = rensa(citat)
        guard c.count >= 12 else { return false }
        let t = rensa(transkript)
        if t.contains(c) { return true }
        let ord = c.split(separator: " ").map(String.init)
        guard ord.count >= 5 else { return false }
        return transkript.split(separator: "\n").contains { rad in
            let r = rensa(String(rad))
            return ord.allSatisfy { r.contains($0) }
        }
    }

    private static func rensa(_ s: String) -> String {
        s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted).joined()
            .split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }

    private static func tomSomNil(_ s: String?) -> String? { Modellsvar.tomSomNil(s) }

    enum Fel: LocalizedError {
        case otolkbart
        var errorDescription: String? { "Sammanfattningen gick inte att tolka." }
    }
}

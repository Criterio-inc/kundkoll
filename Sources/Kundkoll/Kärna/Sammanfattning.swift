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

    struct Åtagande: Codable, Hashable, Identifiable {
        var id = UUID()
        var vad: String
        /// Vem som ska göra det, med namnet som står i transkriptet.
        var vem: String?
        /// När, som det sades — "före fredag", "nästa vecka".
        var när: String?
        var klart = false
    }

    var tom: Bool { beslut.isEmpty && åtaganden.isEmpty && öppet.isEmpty }
}

/// Skriver sammanfattningen med den modell som valts för chatten.
actor Sammanfattare {

    private let chatt: Chatt

    init(chatt: Chatt = Chatt()) { self.chatt = chatt }

    /// Ett transkript kan vara långt. Det som betyder något för besluten sägs
    /// nästan alltid i klartext, så hela texten skickas — men kapad, så att en
    /// tre timmar lång inspelning inte spränger fönstret.
    private let maxTecken = 60_000

    func skriv(för inspelning: Inspelning, kund: String) async throws -> Mötessammanfattning {
        let rader = inspelning.yttranden.map { y in
            "[\(y.tidsstämpel)] \(y.etikett(inspelning.röstnamn, enspårig: inspelning.enspårig)): \(y.text)"
        }
        var text = rader.joined(separator: "\n")
        if text.count > maxTecken {
            // Slutet av ett möte bär besluten; början bär sammanhanget.
            let halva = maxTecken / 2
            text = String(text.prefix(halva)) + "\n\n[…]\n\n" + String(text.suffix(halva))
        }

        let uppdrag = """
        Här är transkriptet från ett möte med kunden \(kund).

        Sammanfatta det som JSON med exakt dessa fält:

        {
          "kärna": "två eller tre meningar om vad mötet handlade om",
          "beslut": ["det som faktiskt bestämdes"],
          "åtaganden": [{"vad": "…", "vem": "namn eller null", "när": "som det sades, eller null"}],
          "öppet": ["frågor som lämnades obesvarade"]
        }

        Ta bara med sådant som verkligen sades. Hellre en tom lista än ett
        påhittat beslut. Skriv på svenska, kort och konkret, utan artigheter.
        Svara med enbart JSON.

        Transkript:
        \(text)
        """

        let svar = try await chatt.fråga(uppdrag, om: kund, projekt: inspelning.projekt,
                                         träffar: [], historik: [])
        guard let tolkad = Self.tolka(svar.text) else { throw Fel.otolkbart }
        return tolkad
    }

    /// Modeller lägger gärna JSON i en kodruta, eller skriver en rad före.
    static func tolka(_ text: String) -> Mötessammanfattning? {
        var rent = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = rent.range(of: "```") {
            rent = String(rent[start.upperBound...])
            if rent.hasPrefix("json") { rent = String(rent.dropFirst(4)) }
            if let slut = rent.range(of: "```") { rent = String(rent[..<slut.lowerBound]) }
        }
        guard let första = rent.firstIndex(of: "{"), let sista = rent.lastIndex(of: "}") else {
            return nil
        }
        rent = String(rent[första...sista])

        struct Rå: Decodable {
            struct Å: Decodable { let vad: String; let vem: String?; let när: String? }
            let kärna: String?
            let beslut: [String]?
            let åtaganden: [Å]?
            let öppet: [String]?
        }
        guard let rå = try? JSONDecoder().decode(Rå.self, from: Data(rent.utf8)) else { return nil }
        return Mötessammanfattning(
            kärna: rå.kärna ?? "",
            beslut: rå.beslut ?? [],
            åtaganden: (rå.åtaganden ?? []).map {
                .init(vad: $0.vad, vem: tomSomNil($0.vem), när: tomSomNil($0.när))
            },
            öppet: rå.öppet ?? [])
    }

    private static func tomSomNil(_ s: String?) -> String? {
        guard let s, !s.isEmpty, s.lowercased() != "null" else { return nil }
        return s
    }

    enum Fel: LocalizedError {
        case otolkbart
        var errorDescription: String? { "Sammanfattningen gick inte att tolka." }
    }
}

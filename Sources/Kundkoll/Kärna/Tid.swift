import Foundation

/// En loggad arbetsinsats: vad som gjordes, när, och hur länge.
struct Tidspost: Codable, Identifiable, Hashable {
    var id = UUID()
    var vad: String
    /// Projektets namn som etikett; `projektID` är nyckeln.
    var projekt: String?
    var projektID: String?
    var start: Date
    var sekunder: Double
    /// Mötet posten loggades ur, när den kom som ett förslag.
    var möte: UUID?

    init(id: UUID = UUID(), vad: String, projekt: String? = nil, projektID: String? = nil,
         start: Date = Date(), sekunder: Double, möte: UUID? = nil) {
        self.id = id
        self.vad = vad
        self.projekt = projekt
        self.projektID = projektID
        self.möte = möte
        self.start = start
        self.sekunder = sekunder
    }

    /// Skriven för hand: se `Inspelning`.
    init(from avkodare: Decoder) throws {
        let c = try avkodare.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        vad = try c.decodeIfPresent(String.self, forKey: .vad) ?? ""
        projekt = try c.decodeIfPresent(String.self, forKey: .projekt)
        projektID = try c.decodeIfPresent(String.self, forKey: .projektID)
        start = try c.decodeIfPresent(Date.self, forKey: .start) ?? Date()
        sekunder = try c.decodeIfPresent(Double.self, forKey: .sekunder) ?? 0
        möte = try c.decodeIfPresent(UUID.self, forKey: .möte)
    }

    /// Möten i projektet som kan bli tidsposter med ett klick: hållna den
    /// senaste veckan, minst en minut långa, inte redan loggade och inte
    /// avfärdade. Äldre förslag försvinner tyst i stället för att bli en lista.
    static func förslag(ur möten: [Möte], poster: [Tidspost], avfärdade: Set<UUID>,
                        idag: Date = Date()) -> [Möte] {
        let loggade = Set(poster.compactMap(\.möte))
        let gräns = idag.addingTimeInterval(-7 * 86400)
        return möten.filter { m in
            let i = m.inspelning
            return i.inledd > gräns && i.inledd <= idag && i.längd >= 60
                && !loggade.contains(i.id) && !avfärdade.contains(i.id)
        }
    }

    /// Posten ett möte blir.
    static func ur(_ möte: Möte, projekt: Projekt) -> Tidspost {
        let i = möte.inspelning
        return Tidspost(vad: i.titel, projekt: projekt.namn, projektID: projekt.id,
                        start: i.inledd, sekunder: i.längd, möte: i.id)
    }

    /// "1:30" är en och en halv timme, "1,5" också, "90" är minuter.
    ///
    /// Regeln följer hur man faktiskt skriver: kolon betyder timmar och
    /// minuter, decimaler betyder timmar, ett naket tal betyder minuter.
    static func tolkaLängd(_ text: String) -> Double? {
        let rent = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "")
        guard !rent.isEmpty else { return nil }
        if rent.contains(":") {
            let delar = rent.split(separator: ":")
            guard delar.count == 2, let h = Double(delar[0]), let m = Double(delar[1]),
                  h >= 0, m >= 0, m < 60 else { return nil }
            return (h * 60 + m) * 60
        }
        let punktad = rent.replacingOccurrences(of: ",", with: ".")
        guard let tal = Double(punktad), tal > 0 else { return nil }
        // Decimaltal är timmar; heltal är minuter.
        return punktad.contains(".") ? tal * 3600 : tal * 60
    }

    /// 5 400 s → "1:30".
    static func längdtext(_ sekunder: Double) -> String {
        let minuter = Int((sekunder / 60).rounded())
        return String(format: "%d:%02d", minuter / 60, minuter % 60)
    }
}

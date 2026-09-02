import Foundation

/// En loggad arbetsinsats: vad som gjordes, när, och hur länge.
struct Tidspost: Codable, Identifiable, Hashable {
    var id = UUID()
    var vad: String
    var projekt: String?
    var start: Date
    var sekunder: Double

    init(id: UUID = UUID(), vad: String, projekt: String? = nil,
         start: Date = Date(), sekunder: Double) {
        self.id = id
        self.vad = vad
        self.projekt = projekt
        self.start = start
        self.sekunder = sekunder
    }

    /// Skriven för hand: se `Inspelning`.
    init(from avkodare: Decoder) throws {
        let c = try avkodare.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        vad = try c.decodeIfPresent(String.self, forKey: .vad) ?? ""
        projekt = try c.decodeIfPresent(String.self, forKey: .projekt)
        start = try c.decodeIfPresent(Date.self, forKey: .start) ?? Date()
        sekunder = try c.decodeIfPresent(Double.self, forKey: .sekunder) ?? 0
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

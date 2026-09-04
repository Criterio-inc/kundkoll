import Foundation

/// En chatt med kunskapsbanken.
///
/// Flera per kund: ett samtal handlar oftast om en sak, och att rensa för att
/// börja på nytt kastar det man kanske vill tillbaka till.
struct Samtal: Codable, Identifiable, Hashable {
    var id = UUID()
    /// Härleds ur den första frågan, men går att ändra.
    var titel: String
    /// Projektets namn som etikett; `projektID` är nyckeln.
    var projekt: String?
    var projektID: String?
    /// Satt när samtalet gäller ett enskilt möte. Då hör det hemma i
    /// transkriptvyn och ska inte dyka upp i kundens allmänna chatt.
    var möte: String?
    var meddelanden: [Chatt.Meddelande] = []
    var skapad = Date()
    var ändrad = Date()

    var tomt: Bool { meddelanden.isEmpty }

    /// Första frågan, kapad. Det är den som säger vad samtalet handlade om.
    static func titel(ur meddelanden: [Chatt.Meddelande]) -> String {
        guard let första = meddelanden.first(where: { $0.roll == .människa })?.text
            .trimmingCharacters(in: .whitespacesAndNewlines), !första.isEmpty
        else { return "Nytt samtal" }
        let rad = första.split(separator: "\n").first.map(String.init) ?? första
        return rad.count <= 52 ? rad : String(rad.prefix(52)) + "…"
    }

    init(id: UUID = UUID(), titel: String = "Nytt samtal", projekt: String? = nil,
         projektID: String? = nil,
         möte: String? = nil, meddelanden: [Chatt.Meddelande] = [],
         skapad: Date = Date(), ändrad: Date = Date()) {
        self.id = id
        self.titel = titel
        self.projekt = projekt
        self.projektID = projektID
        self.möte = möte
        self.meddelanden = meddelanden
        self.skapad = skapad
        self.ändrad = ändrad
    }

    init(from avkodare: Decoder) throws {
        let c = try avkodare.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        titel = try c.decodeIfPresent(String.self, forKey: .titel) ?? "Samtal"
        projekt = try c.decodeIfPresent(String.self, forKey: .projekt)
        projektID = try c.decodeIfPresent(String.self, forKey: .projektID)
        möte = try c.decodeIfPresent(String.self, forKey: .möte)
        meddelanden = try c.decodeIfPresent([Chatt.Meddelande].self, forKey: .meddelanden) ?? []
        skapad = try c.decodeIfPresent(Date.self, forKey: .skapad) ?? Date()
        ändrad = try c.decodeIfPresent(Date.self, forKey: .ändrad) ?? Date()
    }
}

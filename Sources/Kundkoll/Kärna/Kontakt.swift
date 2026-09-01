import Foundation

/// En person hos en kund.
///
/// Kan vara knuten till en post i macOS Kontakter, men behöver inte vara det —
/// alla man talar med finns inte i adressboken, och en person som dyker upp i
/// ett möte ska gå att skriva upp direkt.
struct Kontakt: Codable, Hashable, Identifiable {
    var id = UUID()
    var namn: String
    var roll: String?
    var epost: [String] = []
    var telefon: [String] = []
    /// Identifieraren i macOS Kontakter, när kontakten är hämtad därifrån.
    var systemID: String?

    init(id: UUID = UUID(), namn: String, roll: String? = nil,
         epost: [String] = [], telefon: [String] = [], systemID: String? = nil) {
        self.id = id
        self.namn = namn
        self.roll = roll
        self.epost = epost
        self.telefon = telefon
        self.systemID = systemID
    }

    /// Skriven för hand så att en kontakt sparad före ett nytt fält
    /// fortfarande går att läsa.
    init(from avkodare: Decoder) throws {
        let c = try avkodare.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        namn = try c.decodeIfPresent(String.self, forKey: .namn) ?? ""
        roll = try c.decodeIfPresent(String.self, forKey: .roll)
        epost = try c.decodeIfPresent([String].self, forKey: .epost) ?? []
        telefon = try c.decodeIfPresent([String].self, forKey: .telefon) ?? []
        systemID = try c.decodeIfPresent(String.self, forKey: .systemID)
    }

    var förstaEpost: String? { epost.first }

    /// Matchar en e-postadress, oavsett skiftläge och kringliggande text.
    func matchar(epost adress: String) -> Bool {
        let a = adress.lowercased()
        return epost.contains { a.contains($0.lowercased()) }
    }
}

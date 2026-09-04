import Foundation

extension Tester {
    static func obsidian() {
        Prov.svit("Obsidian")
        // Sökvägar med å ä ö och mellanslag måste överleva kodningen
        let c = CharacterSet.urlQueryValueAllowed
        Prov.kolla(!c.contains(Unicode.Scalar("/")), "snedstreck kodas i sökvägen")
        Prov.kolla(!c.contains(Unicode.Scalar("&")), "och-tecken kodas")
        let kodad = "/Users/a/Documents/Kunder/Ängsö Trä/Anteckningar/Möte.md"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed)
        Prov.kolla(kodad != nil, "sökvägen går att koda")
        Prov.kolla(kodad?.contains("%2F") == true, "snedstrecken är kodade")
        Prov.kolla(URL(string: "obsidian://open?path=\(kodad ?? "")") != nil,
                   "resultatet blir en giltig URL")
    }
}

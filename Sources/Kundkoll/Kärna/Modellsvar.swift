import Foundation

/// Plockar JSON ur ett modellsvar. Modeller lägger gärna JSON i en kodruta,
/// eller skriver en rad före och efter. Fanns förut i två identiska kopior,
/// en för sammanfattningen och en för uppgiftsletaren.
enum Modellsvar {
    /// Bytes för det första fullständiga objektet, eller nil om det inte
    /// finns något som ser ut som JSON alls.
    static func json(ur text: String) -> Data? {
        var rent = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = rent.range(of: "```") {
            rent = String(rent[start.upperBound...])
            if rent.hasPrefix("json") { rent = String(rent.dropFirst(4)) }
            if let slut = rent.range(of: "```") { rent = String(rent[..<slut.lowerBound]) }
        }
        guard let första = rent.firstIndex(of: "{"), let sista = rent.lastIndex(of: "}"),
              första <= sista else { return nil }
        return Data(String(rent[första...sista]).utf8)
    }

    /// «null», tomt och mellanslag är inget värde.
    static func tomSomNil(_ s: String?) -> String? {
        guard let s else { return nil }
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t.lowercased() != "null" else { return nil }
        return t
    }

    /// «Vänta på beslutet från nämnden» blir «Beslutet från nämnden». Modellen
    /// ombeds skriva vad personen ska leverera, men qwen3 skriver ändå ofta
    /// väntandet som uppgift; i spalten «Jag väntar på» blir det dubbelt.
    static func utanVäntaPå(_ vad: String) -> String {
        let l = vad.lowercased()
        for prefix in ["vänta på att ", "vänta in att ", "vänta på ", "vänta in ", "invänta "] where l.hasPrefix(prefix) {
            let rest = String(vad.dropFirst(prefix.count))
            guard let första = rest.first else { return vad }
            return första.uppercased() + rest.dropFirst()
        }
        return vad
    }
}

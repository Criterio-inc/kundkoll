import Foundation

/// Kedjar ihop möten som är samma samtal i avsnitt.
///
/// Ett återkommande avstämningsmöte heter nästan likadant varje gång —
/// "magnus 1on1 20260901", "magnus 1on1 20261001" — det som skiljer är
/// datum och nummer. Nyckeln är därför titeln med siffrorna bortplockade.
/// Ingen inställning, ingen registrering: serien finns så fort två möten
/// heter samma sak.
enum Mötesserie {

    /// Titeln utan siffror, skiljetecken och skiftläge.
    static func nyckel(_ titel: String) -> String {
        titel.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted
                .union(.decimalDigits))
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Närmast föregående möte i samma serie, om det finns ett.
    static func föregående(_ inspelning: Inspelning,
                           bland alla: [Möte]) -> Möte? {
        let egen = nyckel(inspelning.titel)
        guard !egen.isEmpty else { return nil }
        return alla
            .filter { $0.inspelning.id != inspelning.id }
            .filter { nyckel($0.inspelning.titel) == egen }
            .filter { $0.inspelning.inledd < inspelning.inledd }
            .max { $0.inspelning.inledd < $1.inspelning.inledd }
    }

    /// Mötena i serien fram till och med det här, äldst först.
    static func kedja(tillOchMed inspelning: Inspelning, bland alla: [Möte]) -> [Inspelning] {
        var ut = [inspelning]
        var nuvarande = inspelning
        while ut.count < 24, let f = föregående(nuvarande, bland: alla) {
            ut.append(f.inspelning)
            nuvarande = f.inspelning
        }
        return ut.reversed()
    }

    /// Frågorna som fortfarande är öppna efter ett möte: allt som lämnats
    /// öppet i serien, minus det som ett senare möte besvarat. Samma princip
    /// som tavlan, tillämpad på frågor.
    static func öppnaFrågor(tillOchMed inspelning: Inspelning, bland alla: [Möte]) -> [String] {
        var öppna: [String] = []
        for m in kedja(tillOchMed: inspelning, bland: alla) {
            guard let s = m.sammanfattning else { continue }
            let besvarade = Set(s.besvarade.map(normalisera))
            öppna.removeAll { besvarade.contains(normalisera($0)) }
            for f in s.öppet where !öppna.contains(where: { normalisera($0) == normalisera(f) }) {
                öppna.append(f)
            }
        }
        return öppna
    }

    private static func normalisera(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".?!"))
    }
}

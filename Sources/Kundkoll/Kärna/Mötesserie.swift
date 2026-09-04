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
}

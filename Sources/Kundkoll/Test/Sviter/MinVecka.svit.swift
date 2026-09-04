import Foundation

extension Tester {
    static func minVecka() {
        Prov.svit("Min vecka")
        let idag = Uppgift.dag("2026-09-02")!   // en onsdag

        func var_(_ dag: String?) -> String {
            Minveckavy.grupp(Uppgift(vad: "x", senast: dag.flatMap(Uppgift.dag)), idag: idag)
        }
        Prov.lika(var_("2026-09-01"), "Försenat", "gårdagen är försenad")
        Prov.lika(var_("2026-09-02"), "Denna vecka", "dagens dag hör till veckan")
        Prov.lika(var_("2026-09-06"), "Denna vecka", "söndagen med — veckan är mån–sön")
        Prov.lika(var_("2026-09-07"), "Senare", "måndagen därpå är senare")
        Prov.lika(var_(nil), "Utan datum", "utan datum är utan datum")
    }
}

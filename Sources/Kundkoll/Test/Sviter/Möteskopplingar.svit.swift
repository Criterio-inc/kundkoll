import Foundation

extension Tester {
    static func möteskopplingar() {
        Prov.svit("Möteskopplingar")
        let rot = FileManager.default.temporaryDirectory
            .appending(path: "kundkoll-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: rot) }
        let arkiv = Arkivet(rot: rot)
        let kund = try! arkiv.skapaKund(namn: "Acme")
        let projekt = try! arkiv.skapaProjekt(namn: "Nytt lager", hos: kund)

        Prov.lika(arkiv.möteskopplingar(för: kund).count, 0, "inga kopplingar från början")
        try! arkiv.kopplaMöte("m1", till: projekt, för: kund)
        Prov.lika(arkiv.möteskopplingar(för: kund)["m1"], projekt.id,
                  "ett möte kan kopplas till ett projekt, med projektets id som värde")
        // Utan projekt är mötet ändå kundens — det är anspråket som räknas:
        // möten utan deltagarlista kan ingen regel känna igen.
        try! arkiv.kopplaMöte("m1", till: nil, för: kund)
        Prov.lika(arkiv.möteskopplingar(för: kund)["m1"], "",
                  "utan projekt hör mötet ändå till kunden")
        try! arkiv.taBortMöteskoppling("m1", för: kund)
        Prov.lika(arkiv.möteskopplingar(för: kund)["m1"], nil,
                  "och anspråket går att släppa")
    }
}

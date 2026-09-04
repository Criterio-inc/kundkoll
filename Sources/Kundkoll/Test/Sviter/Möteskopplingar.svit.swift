import Foundation

extension Tester {
    static func möteskopplingar() {
        Prov.svit("Möteskopplingar")
        let rot = FileManager.default.temporaryDirectory
            .appending(path: "kundkoll-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: rot) }
        let arkiv = Arkivet(rot: rot)
        let kund = try! arkiv.skapaKund(namn: "Acme")

        Prov.lika(arkiv.möteskopplingar(för: kund).count, 0, "inga kopplingar från början")
        try! arkiv.kopplaMöte("m1", till: "Nytt lager", för: kund)
        Prov.lika(arkiv.möteskopplingar(för: kund)["m1"], "Nytt lager",
                  "ett möte kan kopplas till ett projekt")
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

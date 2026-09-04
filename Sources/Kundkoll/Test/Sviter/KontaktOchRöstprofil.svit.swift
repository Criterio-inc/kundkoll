import Foundation

extension Tester {
    static func kontaktOchRöstprofil() {
        Prov.svit("Kontakt och röstprofil")

        do {
            let rot = FileManager.default.temporaryDirectory
                .appending(path: "kundkoll-test-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: rot) }
            let arkiv = Arkivet(rot: rot)
            let kund = try! arkiv.skapaKund(namn: "Acme")
            try! arkiv.läggTill(Kontakt(namn: "Anna Svensson"), hos: kund)
            try! arkiv.sparaRöstprofiler([
                Röstprofil(namn: "Anna Svensson", avtryck: []),
                Röstprofil(namn: "Bo Ek", avtryck: []),
            ], för: kund)
            let anna = arkiv.kontakter(för: kund).first!
            try! arkiv.taBort(anna, hos: kund)
            Prov.lika(arkiv.röstprofiler(för: kund).map(\.namn), ["Bo Ek"],
                      "röstprofilen följer med när kontakten tas bort")
        }
    }
}

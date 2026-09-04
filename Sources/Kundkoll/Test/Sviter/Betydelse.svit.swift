import Foundation

extension Tester {
    static func betydelse() {
        Prov.svit("Betydelsesökning")

        // RRF: det som ligger högt i båda listorna vinner.
        Prov.lika(Kunskapsbank.rrf(ord: [1, 2, 3], betydelse: [3, 4, 1]).first, 1,
                  "hög placering i båda listorna vinner")
        Prov.lika(Kunskapsbank.rrf(ord: [1], betydelse: []), [1],
                  "en tom lista fäller ingenting")
        Prov.lika(Kunskapsbank.rrf(ord: [], betydelse: [7]), [7],
                  "och åt andra hållet")
        Prov.kolla(Kunskapsbank.rrf(ord: [1, 2], betydelse: [9, 8]).count == 4,
                   "alla kandidater finns kvar i ordningen")

        let rot = FileManager.default.temporaryDirectory
            .appending(path: "kundkoll-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: rot) }
        let arkiv = Arkivet(rot: rot)
        let kund = try! arkiv.skapaKund(namn: "Acme")
        let bank = try! Kunskapsbank(kund: kund)
        try! bank.läggTill(titel: "Avstämning", text: "Vi pratade om leveranstiden",
                           typ: "transkript", källa: "/a", tid: nil)
        try! bank.läggTill(titel: "Offert", text: "Pris per pallställ",
                           typ: "bilaga", källa: "/b", tid: nil)

        Prov.lika(bank.utanVektor().count, 2, "nya stycken saknar vektor")
        let rader = bank.utanVektor()
        try! bank.sparaVektor(rader[0].id, [1, 0, 0])
        try! bank.sparaVektor(rader[1].id, [0, 1, 0])
        Prov.lika(bank.utanVektor().count, 0, "inbäddade stycken frågas inte om")
        Prov.lika(bank.vektorer().count, 2, "vektorerna går att läsa tillbaka")
        Prov.lika(bank.vektorer().first(where: { $0.id == rader[0].id })?.vektor,
                  [1, 0, 0], "och innehållet är intakt")

        // Frågevektorn pekar mot offerten — den ska upp, trots att orden
        // i frågan inte finns i texten.
        let träffar = bank.hybrid("vad kostar det", vektor: [0, 1, 0])
        Prov.lika(träffar.first?.titel, "Offert",
                  "betydelsen hittar det orden missar")

        Prov.lika(bank.hybrid("leveranstid", vektor: nil).first?.titel, "Avstämning",
                  "utan vektor är hybriden vanlig ordsökning")

        try! bank.glöm(källa: "/b")
        Prov.lika(bank.vektorer().count, 1, "en glömd källa tar sina vektorer med sig")
    }
}

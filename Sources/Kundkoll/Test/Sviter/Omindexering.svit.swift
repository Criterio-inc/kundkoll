import Foundation

extension Tester {
    static func omindexering() {
        Prov.svit("Omindexering")
        let rot = FileManager.default.temporaryDirectory
            .appending(path: "kundkoll-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: rot) }
        let arkiv = Arkivet(rot: rot)
        let kund = try! arkiv.skapaKund(namn: "Acme")

        // Ett mejl med en bilaga som redan har utläst text.
        let mejl = Mailen.Mejl(datum: Date(), datumText: "", avsändare: "Anna <anna@acme.se>",
                               ämne: "Offert", meddelandeID: "id1", konto: "a",
                               låda: "INBOX", riktning: "från", text: "Här är offerten.")
        let bilagefil = kund.mailmapp.appending(path: "Bilagor/offert.pdf").path
        let bilaga = Bilagor.Bilaga(ämne: "Offert", namn: "offert.pdf", fil: bilagefil,
                                    storlek: 1000,
                                    text: "Offert på pallställ, 2 400 kr per enhet")
        try! arkiv.sparaMail([mejl], bilagor: [bilaga], för: kund)

        let bank = try! Kunskapsbank(kund: kund)
        _ = try! Indexering.kör(för: kund, bank: bank)
        let efterEn = bank.antal

        // Mailcachen skrivs om — som efter varje hämtning — och indexeras om.
        try! arkiv.sparaMail([mejl], bilagor: [bilaga], för: kund)
        _ = try! Indexering.kör(för: kund, bank: bank)
        _ = try! Indexering.kör(för: kund, bank: bank)

        Prov.lika(bank.antal, efterEn,
                  "att indexera om ger inga dubbletter (\(bank.antal) mot \(efterEn))")
        Prov.kolla(!bank.sök("pallställ").isEmpty, "och bilagan är fortfarande sökbar")
    }
}

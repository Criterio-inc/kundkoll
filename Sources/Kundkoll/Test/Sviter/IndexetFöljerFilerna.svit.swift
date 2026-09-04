import Foundation

extension Tester {
    static func indexetFöljerFilerna() {
        Prov.svit("Indexet följer filerna")

        do {   // en raderad anteckning glöms
            let rot = FileManager.default.temporaryDirectory
                .appending(path: "kundkoll-test-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: rot) }
            let arkiv = Arkivet(rot: rot)
            let kund = try! arkiv.skapaKund(namn: "Acme")
            var an = try! arkiv.nyAnteckning(i: kund.anteckningsmapp, titel: "Offertmötet")
            an.text = "Vi lovade offert på pallställ före fredag, och Anna skickar ritningarna."
            try! arkiv.spara(an)
            let bank = try! Kunskapsbank(kund: kund)
            _ = try! Indexering.kör(för: kund, bank: bank)
            // Arkivet löser upp /var → /private/var när det läser mappen, och
            // Foundation tar bort /private igen; svansen räcker att jämföra.
            let svans = "/Acme/Anteckningar/Offertmötet.md"
            Prov.kolla(bank.allaKällor().contains { $0.hasSuffix(svans) }, "anteckningen är en källa")
            Prov.kolla(!bank.sök("pallställ").isEmpty, "och går att hitta")
            try! arkiv.taBort(an)
            let r = try! Indexering.kör(för: kund, bank: bank)
            Prov.lika(r.glömda, 1, "nästa genomgång glömmer den raderade filen")
            Prov.kolla(!bank.allaKällor().contains { $0.hasSuffix(svans) }, "källan är borta")
            Prov.kolla(bank.sök("pallställ").isEmpty, "och texten hittas inte längre")
        }

        do {   // mail.json rörs inte när inget ändrats
            let rot = FileManager.default.temporaryDirectory
                .appending(path: "kundkoll-test-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: rot) }
            let arkiv = Arkivet(rot: rot)
            let kund = try! arkiv.skapaKund(namn: "Acme")
            let m = Mailen.Mejl(datum: Date(), datumText: "", avsändare: "a@acme.example", ämne: "Hej",
                                meddelandeID: "x", konto: "", låda: "", riktning: "fran", text: "text")
            Prov.kolla(try! arkiv.sparaMail([m], för: kund), "första sparningen skriver")
            let fil = kund.mailmapp.appending(path: "mail.json")
            let t1 = try! fil.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate!
            Thread.sleep(forTimeInterval: 1.1)
            Prov.kolla(!(try! arkiv.sparaMail([m], för: kund)), "samma innehåll skriver inte")
            let t2 = try! fil.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate!
            Prov.lika(t1, t2, "filens ändringstid står stilla, så indexet läser inte om")
            Prov.kolla(arkiv.mailcache(för: kund)!.ålder < 5, "men «hämtad» är nyss ändå")
        }
    }
}

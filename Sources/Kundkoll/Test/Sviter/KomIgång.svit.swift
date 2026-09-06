import Foundation

extension Tester {
    static func komIgång() {
        Prov.svit("Kom igång")
        let (arkiv, rot) = tillfälligt()
        defer { try? FileManager.default.removeItem(at: rot) }

        func klara() -> Set<String> { Set(Komigång.steg(arkiv: arkiv).filter(\.klar).map(\.id)) }
        let steg = Komigång.steg(arkiv: arkiv)
        Prov.lika(steg.count, 8, "åtta steg")
        Prov.lika(Set(steg.map(\.id)).count, 8, "med unika id")
        Prov.kolla(steg.allSatisfy { !$0.varför.isEmpty && !$0.rubrik.isEmpty }, "alla har rubrik och skäl")
        let arkivsteg: Set<String> = ["kund", "kontakter", "mejl", "inspelning", "tavlan"]
        Prov.kolla(klara().isDisjoint(with: arkivsteg), "utan kunder är inget av arkivstegen gjort")
        if case .nyKund = steg[0].mål {} else { Prov.kolla(false, "utan kund pekar första steget på Ny kund") }

        let kund = try! arkiv.skapaKund(namn: "Acme")
        Prov.kolla(!klara().contains("kund"), "en kund utan projekt räcker inte: uppdraget saknas")
        try! arkiv.skapaProjekt(namn: "Nytt lager", hos: kund)
        Prov.kolla(klara().contains("kund"), "kund med projekt bockar första steget")
        try! arkiv.läggTill(Kontakt(namn: "Anna"), hos: kund)
        Prov.kolla(klara().contains("kontakter"), "en kontakt bockar kontaktsteget")
        try! arkiv.sparaUppgifter([Uppgift(vad: "x", läge: .klart)], för: kund)
        Prov.kolla(klara().contains("tavlan"), "ett avbockat kort bockar tavlan")
        Prov.kolla(!klara().contains("inspelning"), "utan möten är inspelningssteget kvar")
        Prov.kolla(Komigång.visasISidopanelen(arkiv: arkiv) || Komigång.dold,
                   "sidan visas i panelen medan steg återstår, om den inte dolts")

        Prov.lika(Mailen.förhandsrad("Hej,\r\rNu finns anteckningarna på ytan.\r"), "Nu finns anteckningarna på ytan.",
                  "radbrytningar som \\r ur Mail tolkas")
    }
}

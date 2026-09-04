import Foundation

extension Tester {
    static func arbetscentret() {
        Prov.svit("Arbetscentret")

        do {
            let rot = FileManager.default.temporaryDirectory
                .appending(path: "kundkoll-test-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: rot) }
            let arkiv = Arkivet(rot: rot)
            let kund = try! arkiv.skapaKund(namn: "Acme")
            let arbeten = Arbeten()

            Prov.lika(arbeten.senasteKvitto(.uppgiftsrunda, kund: kund), nil, "inget kvitto från början")
            let jobb = arbeten.starta(.uppgiftsrunda, kund: kund, titel: "Letar", beställt: true)
            Prov.kolla(jobb != nil, "ett jobb går att starta")
            Prov.kolla(arbeten.starta(.uppgiftsrunda, kund: kund) == nil, "samma slag hos samma kund spärras medan det pågår")
            Prov.kolla(arbeten.starta(.mejlhämtning, kund: kund) != nil, "ett annat slag går bra samtidigt")
            Prov.kolla(arbeten.pågår(hos: kund), "kunden har något som pågår")
            Prov.kolla(arbeten.beskrivning?.hasPrefix("Acme: Letar") == true,
                       "raden längst ned säger kund och titel: \(arbeten.beskrivning ?? "")")

            // Handtaget hoppar via huvudaktören; avsluta direkt här i provet.
            arbeten.avsluta(jobb!.id, resultat: "3 nya på tavlan", fel: nil, modell: "Lokalt · qwen3:8b")
            let k = arbeten.senasteKvitto(.uppgiftsrunda, kund: kund)
            Prov.kolla(k != nil && !k!.föll, "kvittot finns och är utan fel")
            Prov.kolla(k?.rad.contains("3 nya på tavlan · Lokalt · qwen3:8b") == true, "kvittoraden: \(k?.rad ?? "")")
            Prov.lika(Arbeten.logg(i: kund.mapp).count, 1, "kvittot skrevs till kundmappen")
            Prov.kolla(!arbeten.pågår(.uppgiftsrunda, kund: kund), "jobbet är borta ur pågående")

            let andra = Arbeten()
            Prov.lika(andra.senasteKvitto(.uppgiftsrunda, kund: kund)?.resultat, "3 nya på tavlan",
                      "ett nytt arbetscenter läser kvittot ur filen")

            let m = arbeten.arbete(.mejlhämtning, kund: kund)!
            arbeten.avsluta(m.id, resultat: nil, fel: "når inte Mail", modell: nil)
            Prov.lika(arbeten.fel.count, 1, "ett fel ligger kvar")
            Prov.kolla(arbeten.senasteKvitto(.mejlhämtning, kund: kund)?.rad.contains("Stannade: når inte Mail") == true,
                       "felet står i kvittot")
            arbeten.stängFel(arbeten.fel[0].id)
            Prov.lika(arbeten.fel.count, 0, "och går att stänga")
            Prov.lika(Arbeten.logg(i: kund.mapp).count, 2, "båda kvittona i loggen")

            // «Sedan sist» visar inte samma besked två gånger.
            for _ in 0..<3 {
                let h = arbeten.starta(.indexering, kund: kund, titel: "Läser in dokument")!
                arbeten.avsluta(h.id, resultat: "Inget nytt bland dokumenten", fel: nil, modell: nil)
            }
            let senaste = Arbeten.senasteKvitton(i: kund.mapp)
            Prov.lika(senaste.count, 2, "två kvitton visas")
            Prov.lika(senaste.filter { $0.slag == .indexering }.count, 1,
                      "tre likadana dokumentgenomgångar i rad blir ett kvitto")
        }
    }
}

extension Tester {
    static func diagnos() {
        Prov.svit("Diagnos")
        let lokala = Diagnos.lokala()
        Prov.lika(lokala.map(\.id), ["whisper", "python", "pyannote", "mlx", "claude"],
                  "de fem sakerna på disk kontrolleras i fast ordning")
        Prov.kolla(lokala.allSatisfy { !$0.besked.isEmpty }, "varje rad har ett besked")
        Prov.kolla(lokala.filter { $0.läge != .ok }.allSatisfy { $0.åtgärd != nil },
                   "det som saknas säger hur det ordnas")
        let b = Diagnos.behörigheter()
        Prov.lika(b.count, 6, "sex behörigheter: mikrofon, skärm, kalender, kontakter, påminnelser, Mail")
        Prov.kolla(b.filter { $0.läge != .ok }.allSatisfy { $0.länk != nil },
                   "en behörighet som saknas länkar till Systeminställningar")
        Prov.kolla(Set(lokala.map(\.id)).isDisjoint(with: b.map(\.id)), "raderna har unika id")
    }
}

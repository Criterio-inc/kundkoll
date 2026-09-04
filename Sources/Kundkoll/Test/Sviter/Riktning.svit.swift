import Foundation

extension Tester {
    static func riktning() {
        Prov.svit("Åtaganden i båda riktningar")

        do {   // gissningen ur «vem», med ett givet användarnamn
            func g(_ vem: String?) -> Uppgift.Riktning { Uppgift.gissaRiktning(vem, jag: "Pär Levander") }
            Prov.lika(g(nil), .jag, "utan vem är det mitt")
            Prov.lika(g(""), .jag, "tomt vem är mitt")
            Prov.lika(g("jag"), .jag, "«jag» är mitt")
            Prov.lika(g("Jag"), .jag, "oavsett versal")
            Prov.lika(g("Pär"), .jag, "förnamnet är mitt")
            Prov.lika(g("pär levander"), .jag, "hela namnet är mitt")
            Prov.lika(g("Pär L"), .jag, "förnamn plus efternamnets början är mitt")
            Prov.lika(g("Anna"), .väntar, "ett annat namn är något jag väntar på")
            Prov.lika(g("Per"), .väntar, "ett snarlikt namn räknas inte som mitt")
            Prov.lika(g("Pär Andersson"), .väntar, "samma förnamn, annat efternamn, är någon annan")
            Prov.lika(g("Anna Berg <anna@x.se>"), .väntar, "en adress är någon annan")
        }

        do {   // uppgiften: gissning mot uttryckligt val
            let jag = "Pär Levander"
            var u = Uppgift(vad: "Skicka offerten", vem: "Anna")
            Prov.kolla(!u.mitt || Uppgift.gissaRiktning("Anna", jag: jag) == .väntar,
                       "ett kort med annans namn är något jag väntar på")
            u.riktning = .jag
            Prov.kolla(u.mitt, "ett uttryckligt val vinner över gissningen")
            u.riktning = nil
            u.vem = nil
            Prov.kolla(u.mitt, "utan vem och utan val är kortet mitt")

            // Äldre sparade kort saknar fältet och läses som förut.
            let gammal = #"{"vad":"Ring Bo","vem":"Bo"}"#
            let läst = try! JSONDecoder.kundkoll.decode(Uppgift.self, from: Data(gammal.utf8))
            Prov.lika(läst.riktning, nil, "ett kort utan riktning i filen har ingen sparad")
            Prov.lika(läst.vem, "Bo", "och resten läses")
            let rundtur = try! JSONDecoder.kundkoll.decode(
                Uppgift.self, from: try! JSONEncoder.kundkoll.encode(u.with { $0.riktning = .väntar }))
            Prov.lika(rundtur.riktning, .väntar, "ett satt val överlever sparning")
        }

        do {   // modellens «vänta på …» skalas av
            Prov.lika(Modellsvar.utanVäntaPå("Vänta på beslut från nämnden"), "Beslut från nämnden",
                      "«vänta på» tas bort och nästa ord får versal")
            Prov.lika(Modellsvar.utanVäntaPå("Invänta ritningen"), "Ritningen", "«invänta» likaså")
            Prov.lika(Modellsvar.utanVäntaPå("Skicka offerten"), "Skicka offerten", "annat rörs inte")
            let tolkade = Uppgiftsletare.tolka(#"{"uppgifter":[{"vad":"Vänta på beslutet från Bo","vem":"Bo","när":null,"senast":null}]}"#)!
            Prov.lika(tolkade.first?.vad, "Beslutet från Bo", "letarens kort får den kortare texten")
        }

        do {   // dubblettkontrollen ser «jag» och det egna namnet som samma person
            let namn = Inställningar.användarnamn
            let a = Uppgift(vad: "Skicka offerten på pallställen till Anna", vem: "jag")
            let b = Uppgift(vad: "Skicka offert på pallställ till Anna", vem: namn)
            Prov.kolla(a.liknar(b), "«jag» och mitt eget namn är samma vem")
            let c = Uppgift(vad: "Skicka offert på pallställ till Anna", vem: "Anna")
            Prov.kolla(!a.liknar(c), "men någon annan är fortfarande någon annan")
        }

        do {   // briefen: väntat, försenat, och inget mejl från personen sedan dess
            let idag = Uppgift.dag("2026-09-10")!
            func mejl(_ från: String, _ dag: String, skickat: Bool = false) -> Mailen.Mejl {
                Mailen.Mejl(datum: Uppgift.dag(dag), datumText: dag, avsändare: från, ämne: "x",
                            meddelandeID: UUID().uuidString, konto: "a", låda: "INBOX",
                            riktning: skickat ? "till" : "fran")
            }
            let väntad = Uppgift(vad: "Ritningen", vem: "Anna Berg", senast: Uppgift.dag("2026-09-05"),
                                 riktning: .väntar)
            let mitt = Uppgift(vad: "Offerten", vem: "jag", senast: Uppgift.dag("2026-09-05"))
            let framtida = Uppgift(vad: "Beslutet", vem: "Bo", senast: Uppgift.dag("2026-09-20"),
                                   riktning: .väntar)
            let b1 = Briefing.bygg(kund: "Acme", möte: nil, inspelningar: [],
                                   uppgifter: [väntad, mitt, framtida], mejl: [], idag: idag)
            Prov.lika(b1.väntarUtanSvar.map(\.vad), ["Ritningen"],
                      "bara det väntade och försenade tas upp, inte mitt eget och inte framtida")

            let b2 = Briefing.bygg(kund: "Acme", möte: nil, inspelningar: [],
                                   uppgifter: [väntad], mejl: [mejl("Anna Berg <anna@acme.se>", "2026-09-08")], idag: idag)
            Prov.kolla(b2.väntarUtanSvar.isEmpty, "har personen mejlat efter datumet nämns det inte")

            let b3 = Briefing.bygg(kund: "Acme", möte: nil, inspelningar: [],
                                   uppgifter: [väntad], mejl: [mejl("Anna Berg <anna@acme.se>", "2026-09-01")], idag: idag)
            Prov.lika(b3.väntarUtanSvar.count, 1, "ett mejl före datumet räknas inte som svar")

            let b4 = Briefing.bygg(kund: "Acme", möte: nil, inspelningar: [],
                                   uppgifter: [väntad], mejl: [mejl("Anna Berg <anna@acme.se>", "2026-09-08", skickat: true)], idag: idag)
            Prov.lika(b4.väntarUtanSvar.count, 1, "ett mejl jag själv skickat till henne räknas inte")

            Prov.kolla(Briefing.avsändare("Anna Berg <anna.berg@acme.se>", är: "Anna"), "förnamnet matchar avsändaren")
            Prov.kolla(!Briefing.avsändare("Annika Berg <ab@acme.se>", är: "Anna"), "men inte ett namn som bara börjar lika")
            Prov.kolla(!Briefing.avsändare("Bo Ek <bo@acme.se>", är: "Bo"), "ett tvåbokstavsnamn matchar aldrig, för osäkert")
        }
    }
}

private extension Uppgift {
    func with(_ ändra: (inout Uppgift) -> Void) -> Uppgift { var k = self; ändra(&k); return k }
}

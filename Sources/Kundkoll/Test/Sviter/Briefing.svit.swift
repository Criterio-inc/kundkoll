import Foundation

extension Tester {
    static func briefing() {
        Prov.svit("Briefing")

        func inspelning(_ titel: String, _ dag: String, öppet: [String] = []) -> (Inspelning, URL) {
            var i = Inspelning(titel: titel, inledd: Uppgift.dag(dag)!, längd: 60, kund: "Acme",
                               projekt: nil, mikrofon: nil, liveYttranden: [], arkivYttranden: nil)
            if !öppet.isEmpty {
                i.sammanfattning = Mötessammanfattning(kärna: "Kärnan i \(titel)", beslut: [],
                                                       åtaganden: [], öppet: öppet)
            }
            return (i, URL(fileURLWithPath: "/x/\(titel) \(dag)"))
        }
        func mejl(_ ämne: String, _ dag: String) -> Mailen.Mejl {
            Mailen.Mejl(datum: Uppgift.dag(dag), datumText: dag,
                        avsändare: "Anna <anna@acme.se>", ämne: ämne,
                        meddelandeID: ämne, konto: "a", låda: "INBOX",
                        riktning: "från")
        }
        let möte = Kalendern.Möte(id: "m1", titel: "magnus 1on1 20261001",
                                  start: Date().addingTimeInterval(3600),
                                  slut: Date().addingTimeInterval(7200),
                                  deltagare: [], plats: nil, möteslänk: nil)

        let senaste = inspelning("Styrgrupp", "2026-08-28")
        let iSerien = inspelning("magnus 1on1 20260901", "2026-09-01", öppet: ["Priset?"])
        let b = Briefing.bygg(kund: "Acme", möte: möte,
                              inspelningar: [senaste, iSerien],
                              uppgifter: [Uppgift(vad: "Skicka offerten"),
                                          Uppgift(vad: "Klar sak", läge: .klart)],
                              mejl: [mejl("Efter mötet", "2026-09-02"),
                                     mejl("Före mötet", "2026-08-15")])

        Prov.lika(b.senaste?.0.titel, "magnus 1on1 20260901",
                  "serien går före det allra senaste mötet")
        Prov.lika(b.öppnaFrågor, ["Priset?"], "de obesvarade frågorna följer med")
        Prov.lika(b.öppnaUppgifter.map(\.vad), ["Skicka offerten"],
                  "bara öppna uppgifter tas med")
        Prov.lika(b.mejlSedanSist.map(\.ämne), ["Efter mötet"],
                  "bara mejl efter senaste mötet räknas som nya")
        Prov.kolla(!b.tom, "briefen har innehåll")

        let utanMöte = Briefing.bygg(kund: "Acme", möte: nil,
                                     inspelningar: [senaste, iSerien],
                                     uppgifter: [], mejl: [])
        Prov.lika(utanMöte.senaste?.0.titel, "Styrgrupp",
                  "utan kalendermöte gäller det senaste mötet rakt av")

        let tom = Briefing.bygg(kund: "Acme", möte: nil, inspelningar: [],
                                uppgifter: [], mejl: [])
        Prov.kolla(tom.tom, "utan material är briefen tom och säger det")
    }
}

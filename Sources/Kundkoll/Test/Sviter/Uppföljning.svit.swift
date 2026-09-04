import Foundation

extension Tester {
    static func uppföljning() {
        Prov.svit("Uppföljningsmejl")

        var i = Inspelning(titel: "Avstämning", inledd: Date(), längd: 60, kund: "Acme",
                           projekt: nil, mikrofon: nil, liveYttranden: [], arkivYttranden: nil)
        i.sammanfattning = Mötessammanfattning(
            kärna: "Vi gick igenom offerten.",
            beslut: ["Offerten skickas i veckan"],
            åtaganden: [.init(vad: "Skicka offerten", vem: "Anders", när: "före fredag")],
            öppet: ["Priset på pallställ"])
        let text = Uppföljning.brödtext(för: i)
        Prov.kolla(text.contains("Offerten skickas i veckan"), "besluten kommer med")
        Prov.kolla(text.contains("Skicka offerten (Anders, före fredag)"),
                   "åtagandet med vem och när")
        Prov.kolla(text.contains("Priset på pallställ"), "öppna frågor kommer med")
        Prov.kolla(!text.contains("null"), "inget null läcker in i texten")

        var utan = i
        utan.sammanfattning = nil
        Prov.lika(Uppföljning.brödtext(för: utan), "", "utan sammanfattning finns inget mejl")

        i.röstnamn = [0: "Anna Svensson", 1: "Anders Bjarby"]
        let kontakter = [Kontakt(namn: "Anna Svensson", epost: ["anna@acme.se"]),
                         Kontakt(namn: "Bo Ek", epost: ["bo@acme.se"])]
        Prov.lika(Uppföljning.mottagare(för: i, kontakter: kontakter), ["anna@acme.se"],
                  "deltagarna blir mottagare, andra kontakter inte")
        Prov.lika(Uppföljning.mottagare(för: utan, kontakter: kontakter), [],
                  "utan namngivna röster förifylls ingen adress")

        Prov.lika(Uppföljning.fly(#"sa "hej" \ hejdå"#), #"sa \"hej\" \\ hejdå"#,
                  "citattecken och bakstreck flys åt AppleScript")
    }

    /// Att en fil som sparats en gång går att läsa igen nästa gång appen har
    /// blivit ett fält rikare.
    ///
    /// Swift använder inte standardvärden när en nyckel saknas. Ett nytt fält
    /// på en typ som ligger på disk gör därför alla tidigare filer oläsbara —
    /// och eftersom de läses med `try?` försvinner de utan ett ord. Det har
    /// hänt två gånger i det här projektet: mejlcachen tömdes, och en
    /// inspelning slutade synas i listan.
    ///
    /// Varje typ som skrivs till disk provas här mot den minsta JSON som en
    /// äldre version kan ha lämnat efter sig.
}

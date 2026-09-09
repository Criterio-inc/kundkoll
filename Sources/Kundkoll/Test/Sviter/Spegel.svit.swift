import Foundation

extension Tester {
    /// Spegeln till Cowork: en mapp Kundkoll äger, med lägesbild, tavla,
    /// möten och anteckningar men utan råmaterial.
    static func spegel() {
        Prov.svit("Spegeln till Cowork")
        let fm = FileManager.default
        let (arkiv, rot) = tillfälligt()
        defer { try? fm.removeItem(at: rot) }
        let kund = try! arkiv.skapaKund(namn: "Acme")
        let projekt = try! arkiv.skapaProjekt(namn: "Uppdraget", hos: kund)
        let mål = rot.appending(path: "cowork/Kundkoll")
        try! fm.createDirectory(at: rot.appending(path: "cowork"), withIntermediateDirectories: true)

        Prov.kolla(Spegel.mapp(för: projekt) == nil, "utan val finns ingen spegel")
        var utanVal: Spegel.Utfall? = Spegel.Utfall()
        do { utanVal = try Spegel.skriv(kund: kund, projekt: projekt, arkiv: arkiv) } catch { utanVal = Spegel.Utfall() }
        Prov.kolla(utanVal == nil, "och då skrivs inget")

        try! Spegel.sätt(mål, för: projekt)
        Prov.lika(Spegel.mapp(för: projekt), mål.standardizedFileURL, "mappen läses tillbaka")
        Prov.lika(Projekt.läsID(i: projekt.mapp), projekt.id, "projektets id överlever att spegeln sparas")

        // Underlag: ett kort, ett möte med sammanfattning och råtranskript, en anteckning.
        _ = try! arkiv.läggTill([Uppgift(vad: "Skicka offerten", vem: "jag", när: "fredag",
                                          projekt: "Uppdraget", projektID: projekt.id),
                                 Uppgift(vad: "Leverera underlaget", vem: "Anna",
                                         projekt: "Uppdraget", projektID: projekt.id)], för: kund)
        let mötesmapp = try! arkiv.nyInspelningsmapp(placering: .projekt(projekt), titel: "Uppstart", datum: Date())
        let s = Mötessammanfattning(kärna: "Vi kom överens om starten.",
                                    beslut: ["Starten blir i oktober"],
                                    åtaganden: [.init(vad: "Boka lokalen", vem: "Anna", när: "nästa vecka")],
                                    öppet: ["Vem bjuder in?"])
        let i = Inspelning(titel: "Uppstart", inledd: Date(), längd: 600, kund: "Acme", projekt: "Uppdraget",
                           mikrofon: nil, liveYttranden: [],
                           arkivYttranden: [Yttrande(röst: .jag, text: "hemligt yttrande i rummet", start: 0, slut: 2)],
                           sammanfattning: s)
        try! arkiv.spara(i, i: mötesmapp)
        try! arkiv.spara(Anteckning(titel: "Plan", text: "# Plan\n\nFörst det ena.", ändrad: Date(),
                                    fil: projekt.anteckningsmapp.appending(path: "Plan.md")))
        // En fil någon annan lagt i mappen ska aldrig röras.
        try! fm.createDirectory(at: mål, withIntermediateDirectories: true)
        try! "eget".write(to: mål.appending(path: "Eget.md"), atomically: true, encoding: .utf8)

        // Sparningarna ovan har redan skrivit spegeln via översikterna; det
        // är poängen. Den här skrivningen ser då bara oförändrat.
        let u = try! Spegel.skriv(kund: kund, projekt: projekt, arkiv: arkiv)!
        Prov.kolla(u.skrivna + u.oförändrade >= 4, "om, tavla, möte och anteckning finns i spegeln")
        let tavla = (try? String(contentsOf: mål.appending(path: "Att göra.md"), encoding: .utf8)) ?? ""
        Prov.kolla(tavla.contains("## Jag ska") && tavla.contains("Skicka offerten"), "tavlan har det jag ska")
        Prov.kolla(tavla.contains("## Jag väntar på") && tavla.contains("**Anna** Leverera underlaget"), "och det jag väntar på")
        Prov.kolla(!tavla.contains("**jag**"), "«jag» skrivs som namn, inte som jag")
        let möten = (try? fm.contentsOfDirectory(atPath: mål.appending(path: "Möten").path)) ?? []
        Prov.lika(möten.count, 1, "ett möte")
        let möte = möten.first.flatMap { try? String(contentsOf: mål.appending(path: "Möten/\($0)"), encoding: .utf8) } ?? ""
        Prov.kolla(möte.contains("Starten blir i oktober") && möte.contains("Boka lokalen") && möte.contains("Vem bjuder in?"),
                   "mötet har beslut, åtaganden och öppna frågor")
        Prov.kolla(!möte.contains("hemligt yttrande"), "men inte transkriptet")
        Prov.kolla(fm.fileExists(atPath: mål.appending(path: "Anteckningar/Plan.md").path), "anteckningen följer med")
        Prov.kolla(fm.fileExists(atPath: mål.appending(path: "Om den här mappen.md").path), "och en förklaring")
        let senast = (try? String(contentsOf: mål.appending(path: "Senast.md"), encoding: .utf8)) ?? ""
        Prov.kolla(senast.contains("Mötet «Uppstart»") && senast.contains("1 beslut, 1 åtaganden"),
                   "Senast.md säger att mötet sammanfattats")
        Prov.kolla(senast.contains("Anteckningen «Plan»"), "och att anteckningen skrivits")
        Prov.kolla(!fm.fileExists(atPath: mål.appending(path: "Transkript.md").path)
                   && !fm.fileExists(atPath: mål.appending(path: "möte.json").path), "inget råmaterial")

        let igen = try! Spegel.skriv(kund: kund, projekt: projekt, arkiv: arkiv)!
        Prov.lika(igen.skrivna, 0, "oförändrat underlag skriver inget")
        Prov.kolla(igen.oförändrade >= 4, "allt räknas som oförändrat")

        try? fm.removeItem(at: projekt.anteckningsmapp.appending(path: "Plan.md"))
        let efter = try! Spegel.skriv(kund: kund, projekt: projekt, arkiv: arkiv)!
        Prov.lika(efter.borttagna, 1, "en borttagen anteckning tas bort ur spegeln")
        Prov.kolla(!fm.fileExists(atPath: mål.appending(path: "Anteckningar/Plan.md").path), "filen är borta")
        Prov.kolla(fm.fileExists(atPath: mål.appending(path: "Eget.md").path), "andras filer rörs inte")

        Prov.lika(Spegel.filnamn("Möte 09:00 / Erik?"), "Möte 09-00 - Erik-", "filnamnet tål OneDrive")

        try! Spegel.sätt(nil, för: projekt)
        Prov.kolla(Spegel.mapp(för: projekt) == nil, "spegeln går att koppla bort")
        Prov.kolla(fm.fileExists(atPath: mål.appending(path: "Att göra.md").path), "utan att filerna tas bort")
    }
}

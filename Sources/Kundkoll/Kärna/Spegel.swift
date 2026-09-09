import Foundation

/// Spegeln till Cowork.
///
/// Ett projekt kan peka ut en mapp som ett Cowork-projekt läser, till
/// exempel «00 Claude kontext» i kundens OneDrive. Kundkoll skriver dit det
/// den vet om uppdraget och skriver om när underlaget ändras: lägesbilden,
/// tavlan, mötenas sammanfattningar och anteckningarna. Råtranskript, ljud
/// och mejl följer inte med; det är arbetsmaterial som stannar på datorn.
///
/// Kundkoll äger mappen. Den tar bara bort filer den själv skrivit (de
/// står i ett manifest), så det som någon annan lagt där får vara kvar.
@MainActor
enum Spegel {

    static let manifestnamn = ".kundkoll-spegel.json"

    // MARK: - Var spegeln är

    /// Samma fil som projektets id: `.kundkoll/projekt.json` i projektmappen.
    private struct Projektpost: Codable {
        var id: String
        var spegel: String?
    }

    private static func projektfil(_ projekt: Projekt) -> URL {
        projekt.mapp.appending(path: ".kundkoll/projekt.json")
    }

    static func mapp(för projekt: Projekt) -> URL? {
        guard let data = try? Data(contentsOf: projektfil(projekt)),
              let p = try? JSONDecoder().decode(Projektpost.self, from: data),
              let väg = p.spegel, !väg.isEmpty else { return nil }
        return URL(fileURLWithPath: väg)
    }

    /// nil kopplar bort spegeln. Mappen rörs inte.
    static func sätt(_ mapp: URL?, för projekt: Projekt) throws {
        let fil = projektfil(projekt)
        var p = (try? Data(contentsOf: fil)).flatMap { try? JSONDecoder().decode(Projektpost.self, from: $0) }
            ?? Projektpost(id: projekt.id)
        p.spegel = mapp?.standardizedFileURL.path
        try FileManager.default.createDirectory(at: fil.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(p).write(to: fil, options: .atomic)
    }

    // MARK: - Skriva

    struct Utfall: Equatable {
        var skrivna = 0
        var oförändrade = 0
        var borttagna = 0
        var rad: String {
            "\(skrivna) skrivna, \(oförändrade) oförändrade" + (borttagna > 0 ? ", \(borttagna) borttagna" : "")
        }
    }

    /// Skriver spegeln för projektet. nil när projektet inte har någon
    /// spegel, eller när mappens förälder inte finns: en molnmapp som inte
    /// är hemma ska inte återskapas på disk.
    @discardableResult
    static func skriv(kund: Kund, projekt: Projekt, arkiv: Arkivet, till mål: URL? = nil) throws -> Utfall? {
        guard let rot = mål ?? mapp(för: projekt) else { return nil }
        let fm = FileManager.default
        guard fm.fileExists(atPath: rot.deletingLastPathComponent().path) else { return nil }
        try fm.createDirectory(at: rot, withIntermediateDirectories: true)

        let filer = innehåll(kund: kund, projekt: projekt, arkiv: arkiv)
        var utfall = Utfall()
        for (väg, text) in filer {
            let url = rot.appending(path: väg)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? String(contentsOf: url, encoding: .utf8)) == text {
                utfall.oförändrade += 1
                continue
            }
            try text.write(to: url, atomically: true, encoding: .utf8)
            utfall.skrivna += 1
        }
        // Det spegeln skrev förra gången men som inte finns längre: ett möte
        // som tagits bort, en anteckning som bytt namn.
        for väg in läsManifest(rot) where filer[väg] == nil {
            let url = rot.appending(path: väg)
            if fm.fileExists(atPath: url.path) {
                try? fm.removeItem(at: url)
                utfall.borttagna += 1
            }
        }
        try skrivManifest(filer.keys.sorted(), i: rot)
        return utfall
    }

    /// Filerna som spegeln består av: relativ väg → innehåll.
    static func innehåll(kund: Kund, projekt: Projekt, arkiv: Arkivet) -> [String: String] {
        var filer: [String: String] = [:]
        filer["Om den här mappen.md"] = om(kund: kund, projekt: projekt)
        filer["Senast.md"] = senast(kund: kund, projekt: projekt, arkiv: arkiv)
        if let bild = Läget.läs(kund: kund, projekt: projekt) {
            filer["Läget.md"] = läget(bild, kund: kund, projekt: projekt)
        }
        let kort = arkiv.uppgifter(för: kund).filter { $0.projektID == projekt.id }
        filer["Att göra.md"] = attGöra(kort, kund: kund, projekt: projekt)
        for m in arkiv.inspelningar(för: kund) where projekt.innehåller(m.mapp) {
            guard let s = m.inspelning.sammanfattning else { continue }
            let namn = filnamn(DateFormatter.dag.string(from: m.inspelning.inledd) + " " + m.inspelning.titel)
            filer["Möten/\(namn).md"] = möte(m.inspelning, s)
        }
        for a in arkiv.anteckningar(i: projekt.anteckningsmapp) {
            filer["Anteckningar/\(filnamn(a.titel)).md"] = a.text
        }
        return filer
    }

    // MARK: - Texterna

    private static func om(kund: Kund, projekt: Projekt) -> String {
        """
        # Om den här mappen

        Mappen skrivs av Kundkoll för uppdraget **\(projekt.namn)** hos **\(kund.namn)**. \
        Den skrivs om när underlaget ändras, så ändra inte i filerna här: ändringen \
        försvinner vid nästa skrivning. Det som ska ändras ändras i Kundkoll.

        - **Senast.md**: vad som hänt de senaste två veckorna, nyast först. Frågan «vad hände senast?» besvaras här.
        - **Läget.md**: lägesbilden, skriven av modellen ur möten, tavla, mejl och dokument.
        - **Att göra.md**: tavlan. Det jag ska göra, det jag väntar på, det som pågår och det som är klart.
        - **Möten/**: en fil per möte med sammanfattning, beslut, åtaganden och öppna frågor.
        - **Anteckningar/**: anteckningarna som hör till uppdraget.

        Transkript, ljud och mejl följer inte med. De är arbetsmaterial och stannar på datorn.
        """
    }

    /// Vad som hänt, nyast först: möten som sammanfattats, rundor som lagt
    /// kort på tavlan, lägesbilder, anteckningar som ändrats och kort som
    /// bockats klara. Bara tidpunkter ur underlaget, aldrig «nu», så att
    /// filen bara skrivs om när något faktiskt hänt.
    static let senastFönster: TimeInterval = 14 * 86400

    private static func senast(kund: Kund, projekt: Projekt, arkiv: Arkivet,
                               idag: Date = Date()) -> String {
        let gräns = idag.addingTimeInterval(-senastFönster)
        var händelser: [(när: Date, text: String)] = []

        for m in arkiv.inspelningar(för: kund) where projekt.innehåller(m.mapp) {
            guard let s = m.inspelning.sammanfattning, s.skriven > gräns else { continue }
            händelser.append((s.skriven,
                              "Mötet «\(m.inspelning.titel)» (\(DateFormatter.dag.string(from: m.inspelning.inledd))) sammanfattat: "
                              + "\(s.beslut.count) beslut, \(s.åtaganden.count) åtaganden, \(s.öppet.count) öppna frågor"))
        }
        let kort = arkiv.uppgifter(för: kund).filter { $0.projektID == projekt.id }
        // Kort som flyttats samma minut är en handling, till exempel en
        // rundas femton historiska kort rakt in i Klart.
        for läge in [Uppgift.Läge.klart, .pågår] {
            let flyttade = kort.filter { $0.läge == läge && $0.ändrad > gräns }
            let perMinut = Dictionary(grouping: flyttade) { Int($0.ändrad.timeIntervalSince1970 / 60) }
            for grupp in perMinut.values {
                let när = grupp.map(\.ändrad).max()!
                if grupp.count == 1 {
                    händelser.append((när, "\(läge.namn): \(grupp[0].vad)"))
                } else {
                    händelser.append((när, "\(grupp.count) kort lagda i \(läge.namn)"))
                }
            }
        }
        for a in arkiv.anteckningar(i: projekt.anteckningsmapp) where a.ändrad > gräns {
            händelser.append((a.ändrad, "Anteckningen «\(a.titel)» skriven eller ändrad"))
        }
        let visade: Set<Arbeten.Slag> = [.uppgiftsrunda, .anteckningsrunda, .lägesbild, .efterbearbetning, .diktat, .görKlart]
        for k in Arbeten.senasteKvitton(i: kund.mapp, antal: 300)
        where k.klar > gräns && k.fel == nil && visade.contains(k.slag) {
            var text = k.slag.namn
            if let r = k.resultat, !r.isEmpty { text += ": \(r)" }
            if let m = k.modell { text += " (\(m))" }
            händelser.append((k.klar, text))
        }

        var ut = "# Senast · \(projekt.namn)\n\n*\(kund.namn) · de senaste två veckorna, nyast först. Tider ur Kundkoll.*\n"
        guard !händelser.isEmpty else { return ut + "\nInget har hänt de senaste två veckorna.\n" }
        var dag = ""
        for h in händelser.sorted(by: { $0.när > $1.när }).prefix(80) {
            let d = veckodag.string(from: h.när)
            if d != dag { ut += "\n## \(d)\n\n"; dag = d }
            ut += "- \(DateFormatter.klocka.string(from: h.när)) · \(h.text)\n"
        }
        return ut
    }

    private static let veckodag: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "sv_SE")
        f.dateFormat = "EEEE d MMMM"
        return f
    }()

    private static func läget(_ bild: Lägesbild, kund: Kund, projekt: Projekt) -> String {
        """
        # Läget · \(projekt.namn)

        *\(kund.namn) · skriven \(DateFormatter.dag.string(from: bild.skriven))\(bild.modell.map { " · \($0)" } ?? "")*

        \(bild.text)
        """
    }

    private static func attGöra(_ kort: [Uppgift], kund: Kund, projekt: Projekt) -> String {
        var text = "# Att göra · \(projekt.namn)\n\n*\(kund.namn)*\n"
        let öppna = kort.filter { $0.läge == .attGöra }
        let mina = öppna.filter(\.mitt).sorted(by: ordning)
        let väntar = öppna.filter { !$0.mitt }.sorted(by: ordning)
        let pågår = kort.filter { $0.läge == .pågår }.sorted(by: ordning)
        let klara = kort.filter { $0.läge == .klart }.sorted { $0.ändrad > $1.ändrad }

        func lista(_ rubrik: String, _ u: [Uppgift], bock: Bool = false) {
            guard !u.isEmpty else { return }
            text += "\n## \(rubrik)\n\n"
            for k in u {
                let vem = k.vem.map { "**\(namn($0))** " } ?? ""
                let när = k.när.map { " *(\($0))*" } ?? ""
                let varifrån = k.källtitel.map { " · ur \($0)" } ?? ""
                text += "- [\(bock ? "x" : " ")] \(vem)\(k.vad)\(när)\(varifrån)\n"
            }
        }
        lista("Jag ska", mina)
        lista("Jag väntar på", väntar)
        lista("Pågår", pågår)
        lista("Klart", Array(klara.prefix(30)), bock: true)
        if klara.count > 30 { text += "\n*… och \(klara.count - 30) till i Kundkoll.*\n" }
        if öppna.isEmpty && pågår.isEmpty && klara.isEmpty { text += "\nTavlan är tom.\n" }
        return text
    }

    private static func möte(_ i: Inspelning, _ s: Mötessammanfattning) -> String {
        var text = "# \(i.titel)\n\n*\(DateFormatter.dag.string(from: i.inledd)) · \(Int(i.längd / 60)) min"
        if let m = s.modell { text += " · sammanfattad av \(m)" }
        text += "*\n\n\(s.kärna)\n"
        if !s.beslut.isEmpty {
            text += "\n## Beslut\n\n" + s.beslut.map { "- \($0)\n" }.joined()
        }
        if !s.åtaganden.isEmpty {
            text += "\n## Åtaganden\n\n"
            for å in s.åtaganden {
                let när = å.när.map { " *(\($0))*" } ?? ""
                text += "- [\(å.klart ? "x" : " ")] **\(namn(å.vem ?? "jag"))** \(å.vad)\(när)\n"
            }
        }
        if !s.öppet.isEmpty {
            text += "\n## Öppna frågor\n\n" + s.öppet.map { "- \($0)\n" }.joined()
        }
        if !s.besvarade.isEmpty {
            text += "\n## Besvarat från förra mötet\n\n" + s.besvarade.map { "- \($0)\n" }.joined()
        }
        return text
    }

    // MARK: - Hjälp

    /// «jag» är den som använder appen; i Cowork ska namnet stå.
    private static func namn(_ vem: String) -> String {
        Uppgift.gissaRiktning(vem) == .jag && vem.lowercased() == "jag" ? Inställningar.användarnamn : vem
    }

    private static func ordning(_ a: Uppgift, _ b: Uppgift) -> Bool {
        switch (a.senast, b.senast) {
        case let (x?, y?): x < y
        case (_?, nil): true
        case (nil, _?): false
        default: a.skapad < b.skapad
        }
    }

    /// Ett filnamn OneDrive och Finder tål.
    static func filnamn(_ s: String) -> String {
        var ut = s
        for tecken in ["/", ":", "\\", "*", "?", "\"", "<", ">", "|"] {
            ut = ut.replacingOccurrences(of: tecken, with: "-")
        }
        ut = ut.trimmingCharacters(in: .whitespacesAndNewlines)
        while ut.hasSuffix(".") { ut.removeLast() }
        return ut.isEmpty ? "namnlös" : ut
    }

    private static func läsManifest(_ rot: URL) -> [String] {
        guard let data = try? Data(contentsOf: rot.appending(path: manifestnamn)),
              let vägar = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return vägar
    }

    private static func skrivManifest(_ vägar: [String], i rot: URL) throws {
        try JSONEncoder().encode(vägar).write(to: rot.appending(path: manifestnamn), options: .atomic)
    }
}

import Foundation

/// Ett kommandoradsläge: `Kundkoll --prov-ljud fil.wav` och de andra.
///
/// Alla lägen körs på samma sätt (se `Ingång.kör`): jobbet startar som en
/// uppgift på huvudaktören och huvudtråden pumpar körslingan tills det är
/// klart. En semafor på huvudtråden låste förr ljudprovet, eftersom arbetet
/// behövde huvudtråden för att köra; körslingan gör det inte, och tål både
/// arbete på huvudaktören (lägesbilden, uppgiftsletaren) och arbete vid sidan
/// av (ljud, röster, import).
struct Provläge {
    let flagga: String
    /// Argumenten som de skrivs i hjälpen, «<fil> [motor] [modell]».
    let bruk: String
    let vad: String
    /// Så många argument måste finnas, annars skrivs hjälpen och koden blir 2.
    let minst: Int
    let kör: @MainActor ([String]) async throws -> Int32

    init(_ flagga: String, _ bruk: String = "", minst: Int = 0, vad: String,
         kör: @escaping @MainActor ([String]) async throws -> Int32) {
        self.flagga = flagga; self.bruk = bruk; self.minst = minst; self.vad = vad; self.kör = kör
    }
}

enum Provlägen {
    static let alla: [Provläge] = [
        Provläge("--test", vad: "provsviten, alla enhetsprov") { _ in Logg.tyst = true; return Tester.kör() },
        Provläge("--prov-datum", vad: "relativa tidsuttryck → riktiga datum") { _ in
            await Datumprov.kör()
        },
        Provläge("--prov-ljud", "<fil.wav>", minst: 1,
                 vad: "hela kedjan ljud → fönster → whisper → text, skarpt") { a in
            await Ljudprov.kör(fil: a[0])
        },
        Provläge("--prov-transkribering", "<fil.wav> [motor] [modell]", minst: 1,
                 vad: "en fil genom vald transkriberingsmotor") { a in
            await Transkriberingsprov.kör(fil: a[0], motor: a[sä: 1], modell: a[sä: 2])
        },
        Provläge("--prov-röst", "<ljud.wav> <whisper.json> [facit.json]", minst: 2,
                 vad: "röstanalysen mot en inspelning, med facit om det finns") { a in
            await Röstprov.kör(ljud: a[0], whisper: a[1], facit: a[sä: 2])
        },
        Provläge("--prov-omröst", "<inspelningsmapp> [antal röster]", minst: 1,
                 vad: "röstanalysen om igen på ett färdigt möte") { a in
            await Omröstprov.kör(mapp: a[0], förväntat: a[sä: 1].flatMap(Int.init))
        },
        Provläge("--prov-import", "<fil> …", vad: "import av ljud- och videofiler") { a in
            await Importprov.kör(filer: a)
        },
        Provläge("--transkribera-om", "<inspelningsmapp> [språk|auto]", minst: 1,
                 vad: "skriver om ett möte ur dess ljudfil med dagens motor och modell") { a in
            try await transkriberaOm(mapp: a[0], språk: a[sä: 1])
        },
        Provläge("--prov-bilaga", "<fil> …", vad: "textutdrag ur bilagor: pdf, docx, bilder") { a in
            await Bilageprov.kör(filer: a)
        },
        Provläge("--prov-bilagehämtning", "<adress> [mapp]", minst: 1,
                 vad: "hämtar bilagor ur Mail från en avsändare") { a in
            await Bilageprov.hämtning(adress: a[0], mapp: a[sä: 1])
        },
        Provläge("--prov-dokument", "<mapp>", minst: 1,
                 vad: "hur många filer i en mapp som ger text, per typ") { a in
            await Dokumentprov.kör(mapp: a[0])
        },
        Provläge("--prov-chatt", "[leverantör] [modell]", vad: "en fråga till vald modell, skarpt") { a in
            await Chattprov.kör(argument: a)
        },
        Provläge("--prov-insikter", "[modell …]", vad: "liveinsikter med en eller flera modeller") { a in
            await Insiktsprov.kör(modeller: a)
        },
        Provläge("--prov-kodagent", "<mapp> \"<fråga>\"", minst: 2,
                 vad: "kodagenten (Claude Code) mot en mapp") { a in
            await Kodagentprov.kör(mapp: a[0], fråga: a[1])
        },
        Provläge("--prov-läget", "<kund> <projekt>", minst: 2,
                 vad: "skriver en lägesbild för ett projekt, skarpt") { a in
            try await läget(kund: a[0], projekt: a[1])
        },
        Provläge("--mejlrunda", "<kund>", minst: 1,
                 vad: "letar åtaganden i alla kundens sparade mejl med vald modell, som menyn «Leta åtaganden i alla mejl»") { a in
            try await mejlrunda(kund: a[0])
        },
        Provläge("--anteckningsrunda", "<kund>", minst: 1,
                 vad: "letar åtaganden i kundens och projektens anteckningar som ändrats sedan sist") { a in
            try await anteckningsrunda(kund: a[0])
        },
        Provläge("--sammanfatta", "<inspelningsmapp>", minst: 1,
                 vad: "skriver mötets sammanfattning på nytt ur transkriptet, som knappen i mötesvyn") { a in
            try await sammanfatta(mapp: a[0])
        },
        Provläge("--prov-diktat", "<ljudfil>", minst: 1,
                 vad: "hela diktatkedjan mot ett tillfälligt arkiv med kunderna Acme och Beta") { a in
            try await diktat(fil: a[0])
        },
        Provläge("--prov-uppgifter", "<textfil> [projektnamn …]", minst: 1,
                 vad: "uppgiftsletaren på en text, med modellens råsvar om inget hittas") { a in
            try await uppgifter(fil: a[0], projekt: Array(a.dropFirst()))
        },
    ]

    static var hjälp: String {
        let bredd = alla.map { ($0.flagga + " " + $0.bruk).count }.max() ?? 0
        var rader = ["Kundkoll utan argument startar appen. Provlägen:", ""]
        for l in alla {
            let vänster = (l.flagga + " " + l.bruk).padding(toLength: bredd + 2, withPad: " ", startingAt: 0)
            rader.append("  \(vänster)\(l.vad)")
        }
        rader.append("")
        rader.append("Koden är 0 när provet gick, 1 när det föll, 2 vid fel argument och 124 när")
        rader.append("provet inte blev klart inom KUNDKOLL_PROVTID sekunder (annars 1800).")
        return rader.joined(separator: "\n")
    }

    // MARK: - Lägen som behöver arkivet och huvudaktören

    @MainActor
    static func transkriberaOm(mapp väg: String, språk angivet: String?) async throws -> Int32 {
        let mapp = URL(fileURLWithPath: väg)
        let språk: String? = angivet.map { $0 == "auto" ? nil : $0 } ?? "sv"
        guard let data = try? Data(contentsOf: mapp.appending(path: "möte.json")),
              let gammal = try? JSONDecoder.kundkoll.decode(Inspelning.self, from: data),
              let kund = Arkivet.shared.kunder.first(where: { $0.namn == gammal.kund })
        else { throw Enkeltfel("Hittar ingen läsbar inspelning i \(mapp.path)") }
        let placering: Placering = gammal.projekt.flatMap { namn in
            Arkivet.shared.projekt(för: kund).first { $0.namn == namn }.map { Placering.projekt($0) }
        } ?? .kund(kund)
        let profiler = Arkivet.shared.röstprofiler(för: kund)
        print("Modell: \(Modellval.läs().etikett)")
        let ny = try await Import().slutför(
            mapp: mapp, placering: placering, profiler: profiler,
            titel: gammal.titel, språk: språk,
            vidLäge: { l in print("  \(l.steg)") })
        print("Klar: \(ny.yttranden.count) yttranden")
        for y in ny.yttranden.prefix(4) { print("  · \(y.text.prefix(80))") }
        return ny.yttranden.isEmpty ? 1 : 0
    }

    @MainActor
    static func läget(kund kundnamn: String, projekt projektnamn: String) async throws -> Int32 {
        guard let kund = Arkivet.shared.kunder.first(where: { $0.namn == kundnamn }),
              let projekt = Arkivet.shared.projekt(för: kund).first(where: { $0.namn == projektnamn })
        else { throw Enkeltfel("Hittar inte \(kundnamn) / \(projektnamn)") }
        print("Modell: \(Modellval.läs().etikett)")
        let bild = try await Läget.skriv(kund: kund, projekt: projekt)
        print(bild.text)
        Prov.svit("Lägesbilden skarpt")
        Prov.kolla(!bild.text.isEmpty, "modellen skrev en lägesbild")
        return Prov.sammanfatta()
    }

    @MainActor
    static func kunden(_ namn: String) throws -> Kund {
        guard let kund = Arkivet.shared.kunder.first(where: { $0.namn == namn }) else {
            throw Enkeltfel("Hittar ingen kund som heter «\(namn)». Kunder: \(Arkivet.shared.kunder.map(\.namn).joined(separator: ", "))")
        }
        return kund
    }

    /// Mejlrundan över allt sparat, som menyn i mejlfliken. Modellen är den valda.
    @MainActor
    static func mejlrunda(kund namn: String) async throws -> Int32 {
        let kund = try kunden(namn)
        let mejl = Arkivet.shared.mailcache(för: kund)?.mejl ?? []
        print("Modell: \(Modellval.läs().etikett) · \(mejl.count) mejl sparade")
        let t0 = Date()
        let u = await Uppgiftssamling.frånMejl(mejl, kund: kund, alla: true) { i, n in
            print("  mejl \(i) av \(n)")
        }
        print(String(format: "Klart på %.0f s: %d genomgångna, %d nya på tavlan, %d gamla i Klart, %d hoppade%@",
                     Date().timeIntervalSince(t0), u.genomgångna, u.nya, u.historiska, u.hoppade,
                     u.fel.map { " · fel: \($0)" } ?? ""))
        return u.fel == nil ? 0 : 1
    }

    /// Anteckningsrundan över kundens och projektens anteckningar.
    @MainActor
    static func anteckningsrunda(kund namn: String) async throws -> Int32 {
        let kund = try kunden(namn)
        let arkiv = Arkivet.shared
        var mappar = [kund.anteckningsmapp]
        mappar += arkiv.projekt(för: kund).map(\.anteckningsmapp)
        let noter = mappar.flatMap { arkiv.anteckningar(i: $0) }
        print("Modell: \(Modellval.läs().etikett) · \(noter.count) anteckningar")
        var nya = 0, fel = 0
        for a in noter {
            let u = await Uppgiftssamling.frånAnteckning(a, kund: kund)
            print("  \(a.titel): \(u.genomgångna == 0 ? "oförändrad" : "\(u.nya) nya")\(u.fel.map { " · fel: \($0)" } ?? "")")
            nya += u.nya
            if u.fel != nil { fel += 1 }
        }
        print("Klart: \(nya) nya på tavlan")
        return fel == 0 ? 0 : 1
    }

    /// Samma sak som «Sammanfatta mötet» i mötesvyn, från terminalen: för
    /// ett möte vars sammanfattning föll, utan att skriva om transkriptet.
    @MainActor
    static func sammanfatta(mapp väg: String) async throws -> Int32 {
        let mapp = URL(fileURLWithPath: väg)
        guard var inspelning = Arkivet.shared.inspelning(i: mapp),
              let kund = Arkivet.shared.kund(innehållande: mapp)
        else { throw Enkeltfel("Hittar ingen läsbar inspelning i \(mapp.path)") }
        // KUNDKOLL_MODELL provar en annan lokal modell; KUNDKOLL_TORRT=1 skriver
        // ut utan att spara, för mätningar mot ett riktigt möte.
        var val = Modellval.läs()
        if let m = ProcessInfo.processInfo.environment["KUNDKOLL_MODELL"], !m.isEmpty { val.modell = m }
        let torrt = ProcessInfo.processInfo.environment["KUNDKOLL_TORRT"] == "1"
        if let d = ProcessInfo.processInfo.environment["KUNDKOLL_DELSTORLEK"].flatMap(Int.init) {
            Sammanfattare.delstorlekLokalt = d
            print("Delstorlek: \(d) tecken")
        }
        print("Modell: \(val.etikett) · \(inspelning.yttranden.count) rader\(torrt ? " · torrkörning, sparas inte" : "")")
        let t0 = Date()
        let förra = Uppgiftssamling.förra(för: inspelning, mapp: mapp)
        let s = try await Sammanfattare(chatt: Chatt(val: val)).skriv(för: inspelning, kund: kund.namn, automatiskt: true, förra: förra)
        if !torrt {
            inspelning.sammanfattning = s
            try Arkivet.shared.spara(inspelning, i: mapp)
            Uppgiftssamling.frånMöte(s, inspelning: inspelning, mapp: mapp)
        }
        print(String(format: "Klart på %.0f s", Date().timeIntervalSince(t0)))
        print("\n\(s.kärna)\n")
        for b in s.beslut { print("  beslut: \(b)") }
        for å in s.åtaganden { print("  åtagande: \(å.vad)\(å.vem.map { " — \($0)" } ?? "")\(å.när.map { " (\($0))" } ?? "")") }
        for f in s.öppet { print("  öppet: \(f)") }
        Prov.svit("Sammanfattning skarpt")
        Prov.kolla(!s.kärna.isEmpty, "modellen skrev en kärna")
        return Prov.sammanfatta()
    }

    /// Ett diktat genom whisper och modellen, mot ett tillfälligt arkiv så
    /// att inga riktiga kunder får påhittade reflektioner.
    @MainActor
    static func diktat(fil: String) async throws -> Int32 {
        let rot = FileManager.default.temporaryDirectory.appending(path: "kundkoll-diktat-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: rot) }
        let arkiv = Arkivet(rot: rot)
        let acme = try arkiv.skapaKund(namn: "Acme")
        let beta = try arkiv.skapaKund(namn: "Beta")
        print("Modell: \(Modellval.läs().etikett)")
        let t0 = Date()
        let u = try await Diktat.behandla(URL(fileURLWithPath: fil), arkiv: arkiv) { print("  \($0)") }
        print(String(format: "Klart på %.0f s · kunder: %@ · %d åtaganden · egen dagbok: %@",
                     Date().timeIntervalSince(t0), u.kunder.joined(separator: ", "), u.åtaganden, u.egen ? "ja" : "nej"))
        for kund in [acme, beta] {
            for a in arkiv.anteckningar(i: kund.anteckningsmapp) {
                print("\n— \(kund.namn) / \(a.titel):\n\(a.text)")
            }
            for k in arkiv.uppgifter(för: kund) { print("  · kort hos \(kund.namn): \(k.vad)") }
        }
        for a in arkiv.anteckningar(i: rot.appending(path: "Reflektioner")) { print("\n— Egen dagbok / \(a.titel):\n\(a.text)") }
        Prov.svit("Diktat skarpt")
        Prov.kolla(!u.kunder.isEmpty || u.egen, "något sparades")
        return Prov.sammanfatta()
    }

    /// Kör uppgiftsletaren på en textfil och skriver ut vad modellen svarade,
    /// eller felet: det som rundan i appen annars döljer.
    @MainActor
    static func uppgifter(fil: String, projekt: [String] = []) async throws -> Int32 {
        let text = try String(contentsOfFile: fil, encoding: .utf8)
        print("Modell: \(Modellval.läs().etikett)")
        let t0 = Date()
        // KUNDKOLL_MODELL=qwen3:4b provar en annan lokal modell utan att röra inställningen.
        var val = Modellval.läs()
        if let m = ProcessInfo.processInfo.environment["KUNDKOLL_MODELL"], !m.isEmpty { val.modell = m }
        let letare = Uppgiftsletare(chatt: Chatt(val: val))
        print("Letare: \(val.etikett)")
        let u = try await letare.leta(i: text, sammanhang: "ett mejl jag fått", kund: "Provkunden", projekt: projekt)
        print(String(format: "%d uppgifter på %.1f s", u.count, Date().timeIntervalSince(t0)))
        for x in u { print("  · \(x.vad)\(x.vem.map { " — \($0)" } ?? "")\(x.när.map { " (\($0))" } ?? "")\(x.projekt.map { " [\($0)]" } ?? "")") }
        if u.isEmpty { print("Råsvar:\n\(await letare.senasteSvar)") }
        return 0
    }
}

private extension Array where Element == String {
    /// Elementet om det finns, annars nil: valfria argument.
    subscript(sä i: Int) -> String? { i < count ? self[i] : nil }
}

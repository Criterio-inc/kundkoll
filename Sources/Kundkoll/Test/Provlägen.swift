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
        Provläge("--test", vad: "provsviten, alla enhetsprov") { _ in Tester.kör() },
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
        Provläge("--prov-uppgifter", "<textfil>", minst: 1,
                 vad: "uppgiftsletaren på en text, med modellens råsvar om inget hittas") { a in
            try await uppgifter(fil: a[0])
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
        rader.append("Koden är 0 när provet gick, 1 när det föll och 2 vid fel argument.")
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

    /// Kör uppgiftsletaren på en textfil och skriver ut vad modellen svarade,
    /// eller felet: det som rundan i appen annars döljer.
    @MainActor
    static func uppgifter(fil: String) async throws -> Int32 {
        let text = try String(contentsOfFile: fil, encoding: .utf8)
        print("Modell: \(Modellval.läs().etikett)")
        let t0 = Date()
        let letare = Uppgiftsletare()
        let u = try await letare.leta(i: text, sammanhang: "ett mejl jag fått", kund: "Provkunden")
        print(String(format: "%d uppgifter på %.1f s", u.count, Date().timeIntervalSince(t0)))
        for x in u { print("  · \(x.vad)\(x.vem.map { " — \($0)" } ?? "")\(x.när.map { " (\($0))" } ?? "")") }
        if u.isEmpty { print("Råsvar:\n\(await letare.senasteSvar)") }
        return 0
    }
}

private extension Array where Element == String {
    /// Elementet om det finns, annars nil: valfria argument.
    subscript(sä i: Int) -> String? { i < count ? self[i] : nil }
}

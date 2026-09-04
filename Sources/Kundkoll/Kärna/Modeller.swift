import Foundation

// Filsystemet är sanningen. De här typerna är bara läsbara vyer av det som
// ligger på disk, så att en mapp som skapats för hand i Finder eller Obsidian
// dyker upp i appen utan vidare.

struct Kund: Identifiable, Hashable {
    var id: String { mapp.path }
    var namn: String
    var mapp: URL

    var projektmapp: URL { mapp.appending(path: "Projekt") }
    var samtalsmapp: URL { mapp.appending(path: "Samtal") }
    var kontaktmapp: URL { mapp.appending(path: "Kontakter") }
    var mailmapp: URL { mapp.appending(path: "Mail") }
    var anteckningsmapp: URL { mapp.appending(path: "Anteckningar") }
}

struct Projekt: Identifiable, Hashable {
    /// Ett fast id som bor i projektmappen (.kundkoll/projekt.json), så att
    /// kort, tid, samtal och lägesbild följer med när mappen byter namn.
    /// Namnet är etiketten, id:t är nyckeln.
    var id: String
    var namn: String
    var mapp: URL
    var kundnamn: String

    init(id: String? = nil, namn: String, mapp: URL, kundnamn: String) {
        self.id = id ?? Self.läsID(i: mapp)
        self.namn = namn
        self.mapp = mapp
        self.kundnamn = kundnamn
    }

    /// Läser id:t ur mappen, eller skriver ett nytt om det saknas: en mapp
    /// som skapats i Finder får sitt id första gången appen ser den.
    static func läsID(i mapp: URL) -> String {
        let fil = mapp.appending(path: ".kundkoll/projekt.json")
        struct Post: Codable { var id: String }
        if let data = try? Data(contentsOf: fil),
           let p = try? JSONDecoder().decode(Post.self, from: data), !p.id.isEmpty {
            return p.id
        }
        let nytt = UUID().uuidString
        try? FileManager.default.createDirectory(at: fil.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(Post(id: nytt)),
           (try? data.write(to: fil, options: .atomic)) != nil {
            return nytt
        }
        // Går filen inte att skriva (skrivskyddad mapp, en molnmapp som inte
        // hämtats hem) vore ett nytt slumpat id per läsning värre än inget:
        // varje länk skulle lossna vid nästa omläsning. Då härleds id:t ur
        // sökvägen i stället, stabilt tills mappen byter namn.
        var h: UInt64 = 14_695_981_039_346_656_037
        for b in mapp.standardizedFileURL.path.utf8 { h = (h ^ UInt64(b)) &* 1_099_511_628_211 }
        return "väg-" + String(h, radix: 16)
    }

    /// Om en mapp (ett möte, en anteckning) ligger i projektet.
    func innehåller(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(mapp.standardizedFileURL.path + "/")
    }

    var inspelningsmapp: URL { mapp.appending(path: "Inspelningar") }
    var dokumentmapp: URL { mapp.appending(path: "Dokument") }
    var anteckningsmapp: URL { mapp.appending(path: "Anteckningar") }
}

/// Var en inspelning hamnar: hos kunden i stort, eller i ett av kundens projekt.
enum Placering: Hashable {
    case kund(Kund)
    case projekt(Projekt)

    var kundnamn: String {
        switch self {
        case .kund(let k): k.namn
        case .projekt(let p): p.kundnamn
        }
    }

    var etikett: String {
        switch self {
        case .kund(let k): k.namn
        case .projekt(let p): "\(p.kundnamn) › \(p.namn)"
        }
    }

    /// Kundens eller projektets egen mapp.
    var mapp: URL {
        switch self {
        case .kund(let k): k.mapp
        case .projekt(let p): p.mapp
        }
    }

    /// Mappen där inspelningsmappen skapas.
    var inspelningsrot: URL {
        switch self {
        case .kund(let k): k.samtalsmapp
        case .projekt(let p): p.inspelningsmapp
        }
    }
}

/// Ett hållet möte som det ligger på disk: inspelningen ur möte.json och
/// mappen den bor i. Det är paret som skickas runt i appen, från arkivets
/// lista till mötesvyn, paletten och briefingen.
struct Möte: Identifiable, Hashable {
    let inspelning: Inspelning
    let mapp: URL
    var id: UUID { inspelning.id }
}

/// Vem som talar. Följer av vilket ljudspår raden kom från, inte av diarisering.
enum Röst: String, Codable, Hashable {
    case jag
    case motpart

    var etikett: String {
        switch self {
        case .jag: "Jag"
        case .motpart: "Motpart"
        }
    }
}

/// En rad i transkriptet.
struct Yttrande: Identifiable, Hashable, Codable {
    var id = UUID()
    var röst: Röst
    var text: String
    /// Vilken röstgrupp yttrandet tillhör på motpartsspåret. Namnet slås upp
    /// i inspelningens `röstnamn`, så att en omdöpning slår igenom överallt
    /// på en gång.
    var röstgrupp: Int?
    /// Sekunder från inspelningens start.
    var start: Double
    var slut: Double

    var tidsstämpel: String {
        let t = Int(start)
        return String(format: "%02d:%02d", t / 60, t % 60)
    }

    /// Det som visas när ingen namntabell finns till hands.
    var etikett: String { röst.etikett }

    func etikett(_ namn: [Int: String]) -> String {
        guard röst == .motpart, let g = röstgrupp else { return röst.etikett }
        return namn[g] ?? "Röst \(g + 1)"
    }

    /// I en importerad inspelning finns ingen "motpart" — bara röster.
    func etikett(_ namn: [Int: String], enspårig: Bool) -> String {
        guard enspårig else { return etikett(namn) }
        guard let g = röstgrupp else { return "Röst" }
        return namn[g] ?? "Röst \(g + 1)"
    }
}

/// Metadata som sparas som möte.json bredvid ljudet.
///
/// Avkodningen är skriven för hand av samma skäl som för `Mailen.Mejl`: Swift
/// använder inte standardvärden när en nyckel saknas, så ett nytt fält skulle
/// annars göra alla tidigare inspelningar oläsbara.
struct Inspelning: Codable, Identifiable, Hashable {
    var id = UUID()
    var titel: String
    var inledd: Date
    var längd: Double
    var kund: String
    var projekt: String?
    /// Namnet på mikrofonen som användes, för felsökning i efterhand.
    var mikrofon: String?
    var liveYttranden: [Yttrande]
    /// Fylls i när KB-Whisper har gått igenom ljudet.
    var arkivYttranden: [Yttrande]?
    /// Namn på röstgrupperna på motpartsspåret. Tomma platser betyder att
    /// gruppen ännu inte har fått något namn.
    var röstnamn: [Int: String] = [:]
    /// De som var kallade till mötet, när inspelningen startats från kalendern.
    /// Används som förslag när rösterna ska märkas.
    var kallade: [String] = []
    /// Sant för inspelningar som importerats från en färdig fil. Där finns
    /// ingen uppdelning i mitt spår och motpartens — alla röster ligger i ett,
    /// och en av dem kan vara jag.
    var enspårig = false
    /// Namnet på filen den importerades från.
    var källfil: String?
    /// Mötets språk: "sv", "en" eller nil för att låta motorn avgöra.
    var språk: String?
    /// Vad mötet landade i. Skrivs efter efterbearbetningen.
    var sammanfattning: Mötessammanfattning?
    var efterbearbetad: Bool { arkivYttranden != nil }

    /// Bästa tillgängliga transkript: arkivkvalitet om det finns, annars live.
    var yttranden: [Yttrande] { arkivYttranden ?? liveYttranden }

    init(id: UUID = UUID(), titel: String, inledd: Date, längd: Double, kund: String,
         projekt: String?, mikrofon: String?, liveYttranden: [Yttrande],
         arkivYttranden: [Yttrande]?, röstnamn: [Int: String] = [:],
         kallade: [String] = [], enspårig: Bool = false, källfil: String? = nil,
         språk: String? = nil,
         sammanfattning: Mötessammanfattning? = nil) {
        self.id = id
        self.titel = titel
        self.inledd = inledd
        self.längd = längd
        self.kund = kund
        self.projekt = projekt
        self.mikrofon = mikrofon
        self.liveYttranden = liveYttranden
        self.arkivYttranden = arkivYttranden
        self.röstnamn = röstnamn
        self.kallade = kallade
        self.enspårig = enspårig
        self.källfil = källfil
        self.språk = språk
        self.sammanfattning = sammanfattning
    }

    init(from avkodare: Decoder) throws {
        let c = try avkodare.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        titel = try c.decodeIfPresent(String.self, forKey: .titel) ?? "Samtal"
        inledd = try c.decodeIfPresent(Date.self, forKey: .inledd) ?? Date()
        längd = try c.decodeIfPresent(Double.self, forKey: .längd) ?? 0
        kund = try c.decodeIfPresent(String.self, forKey: .kund) ?? ""
        projekt = try c.decodeIfPresent(String.self, forKey: .projekt)
        mikrofon = try c.decodeIfPresent(String.self, forKey: .mikrofon)
        liveYttranden = try c.decodeIfPresent([Yttrande].self, forKey: .liveYttranden) ?? []
        arkivYttranden = try c.decodeIfPresent([Yttrande].self, forKey: .arkivYttranden)
        röstnamn = try c.decodeIfPresent([Int: String].self, forKey: .röstnamn) ?? [:]
        kallade = try c.decodeIfPresent([String].self, forKey: .kallade) ?? []
        enspårig = try c.decodeIfPresent(Bool.self, forKey: .enspårig) ?? false
        källfil = try c.decodeIfPresent(String.self, forKey: .källfil)
        språk = try c.decodeIfPresent(String.self, forKey: .språk)
        sammanfattning = try c.decodeIfPresent(Mötessammanfattning.self, forKey: .sammanfattning)
    }
}

import Foundation
import AppKit

/// Reflektioner dikterade på hemvägen.
///
/// Appen bevakar en mapp. En ljudfil som dyker upp där skrivs rent på
/// datorn, delas per kund av modellen och sparas som anteckningen
/// «Reflektion <dag>» hos varje kund den nämner. Åtaganden hamnar på
/// tavlan och briefen visar reflektionen inför nästa möte. Det som inte
/// handlar om någon kund blir en egen dagbok i Reflektioner/. Inget lämnar
/// datorn: whisper och modellen körs lokalt, som allt som sker av sig självt.
@MainActor
enum Diktat {

    static let ljudformat: Set<String> = ["m4a", "mp3", "wav", "aac", "aif", "aiff", "caf", "flac", "mp4", "mov"]

    /// En del av reflektionen: en kund, eller ingen.
    struct Del: Equatable {
        var kund: String?
        var text: String
    }

    /// Mappen som bevakas: den valda, annars Diktat/ bredvid kunderna.
    static func mapp(arkiv: Arkivet = .shared) -> URL {
        Inställningar.diktatmapp ?? arkiv.rot.appending(path: "Diktat")
    }

    /// Ljudfiler i mappen som inte bokförts som klara. Storleken jämförs med
    /// förra gången: en fil som ännu synkas från telefonen växer, och tas
    /// först när den stått stilla ett varv.
    static func nya(i mapp: URL, klara: [String: Int], senastSedda: inout [String: Int]) -> [URL] {
        guard let filer = try? FileManager.default.contentsOfDirectory(
            at: mapp, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else { return [] }
        var ut: [URL] = []
        for f in filer.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where ljudformat.contains(f.pathExtension.lowercased()) {
            let namn = f.lastPathComponent
            guard klara[namn] == nil else { continue }
            let storlek = (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if senastSedda[namn] == storlek, storlek > 0 { ut.append(f) }
            senastSedda[namn] = storlek
        }
        return ut
    }

    // MARK: - Dela per kund

    /// Det modellen behöver veta om en kund för att känna igen den i en
    /// reflektion som aldrig nämner kundens namn: uppdragen och personerna.
    struct Kundbild {
        var namn: String
        var projekt: [String] = []
        var personer: [String] = []

        var rad: String {
            var ut = "«\(namn)»"
            if !projekt.isEmpty { ut += ": uppdraget \(projekt.map { "«\($0)»" }.joined(separator: ", "))" }
            if !personer.isEmpty { ut += ". Personer: \(personer.prefix(30).joined(separator: ", "))" }
            return ut
        }
    }

    static func kundbilder(arkiv: Arkivet) -> [Kundbild] {
        arkiv.kunder.map { kund in
            Kundbild(namn: kund.namn,
                     projekt: arkiv.projekt(för: kund).map(\.namn),
                     personer: arkiv.kontakter(för: kund).map(\.namn))
        }
    }

    static func uppdrag(text: String, kunder: [String]) -> String {
        uppdrag(text: text, kunder: kunder.map { Kundbild(namn: $0) })
    }

    /// En reflektion nämner sällan kundens namn; den nämner människorna och
    /// det man håller på med. Därför får modellen uppdragen och kontakterna,
    /// och regeln att en reflektion oftast handlar om en enda kund. Utan det
    /// hamnade en hel Boråsdag hos Landskrona för att ordet «utbildning» föll.
    static func uppdrag(text: String, kunder: [Kundbild]) -> String {
        """
        Här är en reflektion jag dikterat i bilen efter arbetsdagen. Mina kunder:

        \(kunder.map { "- " + $0.rad }.joined(separator: "\n"))

        Dela upp texten i delar efter vilken kund den handlar om. Kundens namn \
        nämns sällan: personerna och uppdragen ovan säger vilken kund som avses. \
        En reflektion handlar oftast om en enda kund, så dela bara när texten \
        tydligt byter till en annan kund; ett stycke som fortsätter samma dag \
        och samma människor hör till samma kund. Det som inte gäller någon av \
        kunderna får "kund": null. Behåll mina formuleringar och min ordning; \
        ta bara bort talspråkets upprepningar och «eh». Hitta inte på något. \
        Svara som JSON:

        {"delar": [{"kund": "namn exakt som ovan, eller null", "text": "…"}]}

        Reflektionen:
        \(text)
        """
    }

    /// nil när svaret inte gick att tolka. Ett kundnamn som inte är någon av
    /// kunderna blir null, så en felhörning inte skapar en kund som inte finns.
    static func tolka(_ svar: String, kunder: [String]) -> [Del]? {
        guard let data = Modellsvar.json(ur: svar) else { return nil }
        struct Rå: Decodable {
            struct D: Decodable { let kund: String?; let text: String? }
            let delar: [D]?
        }
        guard let rå = try? JSONDecoder().decode(Rå.self, from: data) else { return nil }
        return (rå.delar ?? []).compactMap { d in
            guard let text = Modellsvar.tomSomNil(d.text) else { return nil }
            let kund = Modellsvar.tomSomNil(d.kund).flatMap { namn in
                kunder.first { $0.compare(namn, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
            }
            return Del(kund: kund, text: text)
        }
    }

    // MARK: - Spara

    /// «Reflektion 7 sep», utan punkten: den blev «Reflektion 7 sep..md».
    static func titel(_ dag: Date) -> String {
        "Reflektion " + DateFormatter.kortdag.string(from: dag).trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    /// Där reflektionen sparas hos kunden: i det enda projektet när det
    /// bara finns ett, annars hos kunden.
    static func anteckningsmapp(för kund: Kund, arkiv: Arkivet) -> URL {
        arkiv.standardprojekt(för: kund)?.anteckningsmapp ?? kund.anteckningsmapp
    }

    /// Anteckningen «Reflektion <dag>» i mappen: ny, eller påfylld med en
    /// tidsrubrik när dagen redan har en. Två diktat samma kväll blir en sida.
    static func spara(_ text: String, i mapp: URL, dag: Date, arkiv: Arkivet = .shared) throws -> Anteckning {
        try FileManager.default.createDirectory(at: mapp, withIntermediateDirectories: true)
        let namn = titel(dag)
        let fil = mapp.appending(path: "\(namn).md")
        let klocka = DateFormatter.timme.string(from: dag)
        let innehåll: String
        if let befintlig = try? String(contentsOf: fil, encoding: .utf8) {
            innehåll = befintlig.trimmingCharacters(in: .newlines) + "\n\n## \(klocka)\n\n\(text)\n"
        } else {
            innehåll = "# \(namn)\n\n*Dikterat \(klocka).*\n\n\(text)\n"
        }
        let a = Anteckning(titel: namn, text: innehåll, ändrad: dag, fil: fil)
        try arkiv.spara(a)
        return a
    }

    // MARK: - Hela kedjan

    struct Utfall {
        var kunder: [String] = []
        var åtaganden = 0
        var egen = false
        /// Letaren gick inte att köra på någon del; syns i kvittot.
        var letarfel: String?
    }

    /// Ljudfil → text → delar → anteckningar → åtaganden.
    static func behandla(_ fil: URL, arkiv: Arkivet = .shared,
                         vidLäge: @escaping @MainActor (String) -> Void) async throws -> Utfall {
        let dag = (try? fil.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        vidLäge("Läser \(fil.lastPathComponent)")
        let wav = FileManager.default.temporaryDirectory.appending(path: "kundkoll-diktat-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: wav) }
        let längd = try await Import.tillWhisperformat(fil, mål: wav)

        vidLäge("Skriver rent \(Int(längd / 60)) min")
        let rader = try await Arkivtranskribering.kör(fil: wav, röst: .jag, språk: "sv", totalLängd: längd)
        let text = rader.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw Enkeltfel("Inget tal i \(fil.lastPathComponent).") }

        vidLäge("Delar per kund")
        let kunder = arkiv.kunder
        var delar: [Del]
        if kunder.isEmpty {
            delar = [Del(kund: nil, text: text)]
        } else {
            let svar = try await Chatt().fråga(uppdrag(text: text, kunder: kundbilder(arkiv: arkiv)),
                                              om: "", projekt: nil, träffar: [], historik: [],
                                              automatiskt: true, uppdrag: .utdrag)
            // Ett svar utan lista är inte skäl att tappa reflektionen: hela
            // texten sparas då som egen dagbok, med kundnamnen orörda i texten.
            delar = tolka(svar.text, kunder: kunder.map(\.namn)) ?? [Del(kund: nil, text: text)]
        }

        var utfall = Utfall()
        for del in delar {
            if let namn = del.kund, let kund = kunder.first(where: { $0.namn == namn }) {
                let a = try spara(del.text, i: anteckningsmapp(för: kund, arkiv: arkiv), dag: dag, arkiv: arkiv)
                let u = await Uppgiftssamling.frånAnteckning(a, kund: kund)
                utfall.åtaganden += u.nya
                if let fel = u.fel { utfall.letarfel = fel }
                if !utfall.kunder.contains(namn) { utfall.kunder.append(namn) }
            } else {
                _ = try spara(del.text, i: arkiv.rot.appending(path: "Reflektioner"), dag: dag, arkiv: arkiv)
                utfall.egen = true
            }
        }
        return utfall
    }
}

/// Bevakningen: tittar i mappen varje minut och när appen får fokus, tar en
/// fil i taget, bokför det som är klart så att inget körs två gånger.
@MainActor
final class Diktatvakt: ObservableObject {
    static let delad = Diktatvakt()

    @Published private(set) var pågår: String?
    private var senastSedda: [String: Int] = [:]
    private var klocka: Timer?
    private var kör = false

    private var bokföringsfil: URL { Arkivet.shared.rot.appending(path: ".kundkoll/diktat.json") }

    private var klara: [String: Int] {
        get {
            guard let d = try? Data(contentsOf: bokföringsfil),
                  let k = try? JSONDecoder().decode([String: Int].self, from: d) else { return [:] }
            return k
        }
        set {
            try? FileManager.default.createDirectory(at: bokföringsfil.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let d = try? JSONEncoder().encode(newValue) { try? d.write(to: bokföringsfil, options: .atomic) }
        }
    }

    func starta() {
        guard Inställningar.diktatPå else { return }
        try? FileManager.default.createDirectory(at: Diktat.mapp(), withIntermediateDirectories: true)
        sök()
        klocka?.invalidate()
        klocka = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sök() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sök() }
        }
    }

    func sök() {
        guard Inställningar.diktatPå, !kör else { return }
        let nya = Diktat.nya(i: Diktat.mapp(), klara: klara, senastSedda: &senastSedda)
        guard let fil = nya.first else { return }
        kör = true
        let arkiv = Arkivet.shared
        let värd = arkiv.kunder.first
        let jobb = värd.flatMap { arkiv_ in
            Arbeten.delad.starta(.diktat, kund: arkiv_, titel: "Reflektion ur \(fil.lastPathComponent)")
        }
        pågår = fil.lastPathComponent
        Task {
            defer { kör = false; pågår = nil }
            do {
                let u = try await Diktat.behandla(fil) { [jobb] steg in jobb?.steg(steg) }
                var k = klara
                k[fil.lastPathComponent] = (try? fil.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                klara = k
                let vilka = u.kunder.isEmpty ? "ingen kund, sparad som egen dagbok" : u.kunder.joined(separator: ", ")
                let rad = "\(vilka)" + (u.åtaganden > 0 ? " · \(u.åtaganden) nya på tavlan" : "")
                    + (u.letarfel.map { " · letaren: \($0)" } ?? "")
                jobb?.klart(rad)
                Notiser.skicka(titel: "Reflektionen är på plats", text: rad, kund: u.kunder.first)
            } catch {
                jobb?.föll(error.localizedDescription)
                Logg.fel("Diktat \(fil.lastPathComponent): \(error.localizedDescription)", i: "Diktat")
                // Bokförs ändå, med storlek 0: annars försöker vakten igen varje minut.
                var k = klara; k[fil.lastPathComponent] = 0; klara = k
            }
            sök()
        }
    }
}

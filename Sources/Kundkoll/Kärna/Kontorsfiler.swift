import Foundation

/// Text ur Word, PowerPoint och Excel.
///
/// Alla tre är zip-arkiv med XML inuti, men de bär sin text olika.
///
/// Word och PowerPoint har löpande text i sina delar och går att läsa genom
/// att strippa taggarna. Excel gör inte det: cellernas texter ligger i en
/// egen strängtabell och cellerna pekar på den med index. Ett strippat
/// kalkylblad blir därför en rad indexsiffror utan mening, och läser man
/// bara strängtabellen får man en osorterad hög med ord utan rader,
/// kolumner eller bladnamn. En riskmatris med 54 rader blir ordgröt.
///
/// Uppmätt på en riktig kundmapp: av 593 filer gav den gamla läsningen text
/// ur 219. Kalkylbladen var den stora förlusten, och därefter
/// PowerPoints talarnoteringar och Words kommentarer — i ett granskat
/// underlag är kommentarerna ofta det som betyder mest.
///
/// Därför: Excel läses cell för cell med `XMLParser`, och Word och
/// PowerPoint fick fler delar med.
enum Kontorsfiler {

    /// Så mycket text per fil. Ett kalkylblad med tiotusentals rader är inte
    /// värt mer plats än så i ett index, och stycken bortom det säger sällan
    /// något nytt.
    static let maxTecken = 200_000

    struct Utfall {
        var text: String
        /// Varför det inte blev någon text. Nil när det blev.
        var skäl: String?

        static func tom(_ skäl: String) -> Utfall { Utfall(text: "", skäl: skäl) }
    }

    /// Läser texten ur en docx, pptx eller xlsx.
    static func text(ur url: URL) -> Utfall {
        let ändelse = url.pathExtension.lowercased()
        guard ["docx", "pptx", "xlsx", "docm", "pptm", "xlsm", "potx", "xltx"]
            .contains(ändelse) else {
            return .tom("formatet \(ändelse) läses inte här")
        }

        let temp = FileManager.default.temporaryDirectory
            .appending(path: "kundkoll-kontor-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temp) }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = ["-qq", "-o", url.path, "-d", temp.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return .tom("unzip gick inte att starta") }
        p.waitUntilExit()
        // unzip svarar 1 på varningar men packar ändå upp; bara högre koder
        // betyder att det inte gick.
        guard p.terminationStatus <= 1 else {
            return .tom("gick inte att packa upp (unzip \(p.terminationStatus)): "
                        + Filsignatur.beskriv(url))
        }

        let text: String
        switch ändelse {
        case "xlsx", "xlsm", "xltx": text = urKalkylblad(temp)
        case "pptx", "pptm", "potx": text = urPresentation(temp)
        default: text = urTextdokument(temp)
        }

        let rent = String(text.prefix(maxTecken))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Golvet är lågt med flit. Det gamla på 20 tecken kastade korta
        // dokument som ändå sa något, till exempel ett blad med bara en
        // rubrikrad och tre värden.
        guard rent.count >= 3 else { return .tom("inget textinnehåll i filen") }
        return Utfall(text: rent, skäl: nil)
    }

    // MARK: - Word

    /// Word: brödtexten, noterna, kommentarerna och sidhuvudena.
    ///
    /// Kommentarerna är med av ett skäl: i ett underlag som gått på
    /// granskning ligger invändningarna där, inte i brödtexten.
    private static func urTextdokument(_ rot: URL) -> String {
        var delar: [(ordning: Int, text: String)] = []
        for f in filer(i: rot, ändelse: "xml") {
            let väg = f.path.lowercased()
            let ordning: Int
            if väg.hasSuffix("/word/document.xml") { ordning = 0 }
            else if väg.contains("/word/footnotes.xml") { ordning = 1 }
            else if väg.contains("/word/endnotes.xml") { ordning = 2 }
            else if väg.contains("/word/comments.xml") { ordning = 3 }
            else if väg.contains("/word/header") || väg.contains("/word/footer") { ordning = 4 }
            else { continue }
            guard let xml = try? String(contentsOf: f, encoding: .utf8) else { continue }
            let text = strippa(xml)
            guard !text.isEmpty else { continue }
            let rubrik = ordning == 3 ? "Kommentarer: " : ""
            delar.append((ordning, rubrik + text))
        }
        return delar.sorted { $0.ordning < $1.ordning }
            .map(\.text)
            .joined(separator: "\n\n")
    }

    // MARK: - PowerPoint

    /// PowerPoint: bilderna i nummerordning, var och en följd av sin
    /// talarnotering. Noteringarna är ofta det som faktiskt sades.
    private static func urPresentation(_ rot: URL) -> String {
        var bilder: [Int: String] = [:]
        var noter: [Int: String] = [:]
        for f in filer(i: rot, ändelse: "xml") {
            let väg = f.path.lowercased()
            guard let n = nummer(i: f.lastPathComponent) else { continue }
            guard let xml = try? String(contentsOf: f, encoding: .utf8) else { continue }
            if väg.contains("/ppt/slides/slide") {
                bilder[n] = strippa(xml)
            } else if väg.contains("/ppt/notesslides/notesslide") {
                noter[n] = strippa(xml)
            }
        }
        var ut: [String] = []
        for n in bilder.keys.sorted() {
            var stycke = "Bild \(n): \(bilder[n] ?? "")"
            // Noteringen upprepar bildnumret; det bär ingen information.
            if let not = noter[n]?.trimmingCharacters(in: .whitespaces),
               !not.isEmpty, not != String(n) {
                stycke += "\nTalarnotering: \(not)"
            }
            ut.append(stycke)
        }
        return ut.joined(separator: "\n\n")
    }

    // MARK: - Excel

    /// Excel: bladen i ordning, en rad text per rad i bladet med cellerna
    /// åtskilda av tabb. Strängtabellen slås upp så att texten står där
    /// den hör hemma i stället för i en hög.
    ///
    /// Förbehåll: datum lagras som serienummer och vilka tal som är datum
    /// står i `styles.xml`. Att gissa på talets storlek skulle förvandla
    /// «45 000 kr» till ett datum, så datumceller blir tal. Formler ger
    /// sitt senast beräknade värde, vilket är det Excel visade.
    private static func urKalkylblad(_ rot: URL) -> String {
        let strängar = strängtabell(i: rot)
        let namn = bladnamn(i: rot)

        var blad: [(nummer: Int, text: String)] = []
        for f in filer(i: rot, ändelse: "xml")
        where f.path.lowercased().contains("/xl/worksheets/sheet") {
            guard let n = nummer(i: f.lastPathComponent),
                  let data = try? Data(contentsOf: f) else { continue }
            let rader = Bladläsare(strängar: strängar).läs(data)
            guard !rader.isEmpty else { continue }
            // Bladen numreras från 1 i workbook.xml:s ordning.
            let rubrik = namn.indices.contains(n - 1) ? namn[n - 1] : "Blad \(n)"
            blad.append((n, "Blad: \(rubrik)\n" + rader.joined(separator: "\n")))
        }
        return blad.sorted { $0.nummer < $1.nummer }
            .map(\.text)
            .joined(separator: "\n\n")
    }

    /// Bladens namn, i den ordning de står i arbetsboken.
    private static func bladnamn(i rot: URL) -> [String] {
        guard let f = filer(i: rot, ändelse: "xml")
            .first(where: { $0.path.lowercased().hasSuffix("/xl/workbook.xml") }),
              let xml = try? String(contentsOf: f, encoding: .utf8) else { return [] }
        // <sheet name="Risker" sheetId="1" r:id="rId1"/>
        var ut: [String] = []
        var kvar = Substring(xml)
        while let start = kvar.range(of: "<sheet ") {
            kvar = kvar[start.upperBound...]
            guard let slut = kvar.firstIndex(of: ">") else { break }
            let tagg = kvar[..<slut]
            if let n = kvar.range(of: "name=\"", range: tagg.startIndex..<tagg.endIndex),
               let q = kvar[n.upperBound...].firstIndex(of: "\"") {
                ut.append(avkoda(String(kvar[n.upperBound..<q])))
            }
            kvar = kvar[slut...]
        }
        return ut
    }

    /// Strängtabellen: all text i arbetsboken, i indexordning.
    private static func strängtabell(i rot: URL) -> [String] {
        guard let f = filer(i: rot, ändelse: "xml")
            .first(where: { $0.path.lowercased().hasSuffix("/xl/sharedstrings.xml") }),
              let data = try? Data(contentsOf: f) else { return [] }
        let läsare = Strängläsare()
        let tolk = XMLParser(data: data)
        tolk.delegate = läsare
        tolk.parse()
        return läsare.strängar
    }

    // MARK: - Delar

    /// Filerna i det uppackade arkivet, i bestämd ordning.
    private static func filer(i rot: URL, ändelse: String) -> [URL] {
        guard let vandring = FileManager.default.enumerator(
            at: rot, includingPropertiesForKeys: nil) else { return [] }
        return vandring.compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == ändelse }
            .sorted { $0.path < $1.path }
    }

    /// Siffran i «slide12.xml» eller «sheet3.xml». Filnamnen sorterar
    /// annars lexikalt, och då kommer bild 10 före bild 2.
    static func nummer(i filnamn: String) -> Int? {
        let siffror = filnamn.drop { !$0.isNumber }.prefix { $0.isNumber }
        return Int(siffror)
    }

    /// Tar bort taggarna men lämnar texten, med blanksteg där taggen stod så
    /// att två ord inte klistras ihop.
    static func strippa(_ xml: String) -> String {
        var ut = ""
        var iTagg = false
        for tecken in xml {
            if tecken == "<" { iTagg = true; ut += " " }
            else if tecken == ">" { iTagg = false }
            else if !iTagg { ut.append(tecken) }
        }
        return avkoda(ut.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " "))
    }

    /// XML-entiteter blir annars kvar mitt i texten. `&amp;` sist, annars
    /// blir «&amp;lt;» till «<» i två steg.
    static func avkoda(_ text: String) -> String {
        text.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#10;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

// MARK: - XML-läsare

/// Läser `sharedStrings.xml`. Ett `<si>` är en sträng och kan vara delad i
/// flera `<t>` när delar av den är formaterade olika.
private final class Strängläsare: NSObject, XMLParserDelegate {
    var strängar: [String] = []
    private var iPost = false
    private var iText = false
    /// Fonetisk hjälptext för japanska. Den ska inte med i strängen.
    private var iFonetik = false
    private var nuvarande = ""

    func parser(_ parser: XMLParser, didStartElement element: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        switch element {
        case "si": iPost = true; nuvarande = ""
        case "rPh": iFonetik = true
        case "t": iText = !iFonetik
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if iPost && iText { nuvarande += string }
    }

    func parser(_ parser: XMLParser, didEndElement element: String,
                namespaceURI: String?, qualifiedName: String?) {
        switch element {
        case "si": strängar.append(nuvarande); iPost = false
        case "rPh": iFonetik = false
        case "t": iText = false
        default: break
        }
    }
}

/// Läser ett kalkylblad rad för rad och slår upp strängcellerna.
///
/// En cell ser ut som `<c r="B4" t="s"><v>17</v></c>` — typ `s` betyder att
/// `17` är ett index i strängtabellen, inte talet sjutton. Utan den
/// uppslagningen blir ett blad en rad indexsiffror.
private final class Bladläsare: NSObject, XMLParserDelegate {
    private let strängar: [String]
    private var rader: [String] = []
    private var celler: [String] = []
    private var typ: String?
    private var värde = ""
    private var iVärde = false

    init(strängar: [String]) {
        self.strängar = strängar
        super.init()
    }

    func läs(_ data: Data) -> [String] {
        let tolk = XMLParser(data: data)
        tolk.delegate = self
        tolk.parse()
        return rader
    }

    func parser(_ parser: XMLParser, didStartElement element: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        switch element {
        case "row": celler = []
        case "c": typ = attributes["t"]; värde = ""
        // `v` är cellens värde, `t` texten i en inline-sträng.
        case "v", "t": iVärde = true
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if iVärde { värde += string }
    }

    func parser(_ parser: XMLParser, didEndElement element: String,
                namespaceURI: String?, qualifiedName: String?) {
        switch element {
        case "v", "t":
            iVärde = false
        case "c":
            celler.append(text(av: värde, typ: typ))
            typ = nil
        case "row":
            // En rad med bara tomma celler bär ingenting.
            let rad = celler.map { $0.trimmingCharacters(in: .whitespaces) }
            if rad.contains(where: { !$0.isEmpty }) {
                rader.append(rad.joined(separator: "\t")
                    .trimmingCharacters(in: .whitespaces))
            }
            celler = []
        default: break
        }
    }

    private func text(av värde: String, typ: String?) -> String {
        switch typ {
        case "s":
            guard let i = Int(värde.trimmingCharacters(in: .whitespaces)),
                  strängar.indices.contains(i) else { return "" }
            return strängar[i]
        case "b":
            return värde == "1" ? "ja" : "nej"
        // `inlineStr` och `str` bär redan sin text i `värde`.
        default:
            return värde
        }
    }
}

/// Vad en fil egentligen är, när läsningen inte gav något.
///
/// Uppmätt på en OneDrive-mapp: 362 av 583 filer gav ingen text, tvärs över
/// alla format. Det kan ingen läsare förklara — det är filerna. Tre orsaker
/// ser likadana ut utifrån men kräver helt olika åtgärd: en platshållare som
/// OneDrive inte hämtat hem, en Office-fil krypterad med känslighetsetikett
/// (en OLE-behållare, inte ett zip-arkiv), och en inskannad PDF utan
/// textlager. Det här säger vilken.
enum Filsignatur {
    /// SF_DATALESS i st_flags: innehållet ligger i molnet, inte på disken.
    static let dataless: UInt32 = 0x4000_0000

    static func beskriv(_ url: URL) -> String {
        var st = stat()
        guard stat(url.path, &st) == 0 else { return "filen finns inte" }
        if st.st_flags & dataless != 0 {
            return "molnplatshållare — innehållet är inte hämtat till datorn"
        }
        if st.st_size == 0 { return "tom fil" }
        guard let h = FileHandle(forReadingAtPath: url.path) else { return "går inte att öppna" }
        defer { try? h.close() }
        let huvud = [UInt8]((try? h.read(upToCount: 8)) ?? Data())
        if huvud.starts(with: [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]) {
            return "OLE-behållare — krypterad med känslighetsetikett, eller ett gammalt Office-format"
        }
        if huvud.starts(with: [0x50, 0x4B]) { return "zip-arkiv" }
        if huvud.starts(with: Array("%PDF".utf8)) { return "PDF utan textlager — troligen inskannad" }
        let hex = huvud.prefix(4).map { String(format: "%02x", $0) }.joined(separator: " ")
        return "okänt innehåll (\(hex))"
    }
}

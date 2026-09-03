import Foundation

/// Mappar utanför kundmappen som hör till ett projekt.
///
/// En projektmapp med källkod, en delad mapp med ritningar, en katalog med
/// offerter. Mapparna flyttas inte och kopieras inte — appen läser dem där de
/// ligger och tar med innehållet i kunskapsbanken.
struct Kopplad: Codable, Hashable, Identifiable {
    var id: String { väg }
    var väg: String
    /// Namnet som visas. Tomt betyder mappens eget namn.
    var namn: String = ""
    /// Filändelser att ta med. Tom lista betyder de vanliga för text och kod.
    var ändelser: [String] = []
    var tillagd = Date()

    init(väg: String, namn: String = "", ändelser: [String] = [], tillagd: Date = Date()) {
        self.väg = väg
        self.namn = namn
        self.ändelser = ändelser
        self.tillagd = tillagd
    }

    /// Skriven för hand: se `Inspelning`.
    init(from avkodare: Decoder) throws {
        let c = try avkodare.container(keyedBy: CodingKeys.self)
        väg = try c.decodeIfPresent(String.self, forKey: .väg) ?? ""
        namn = try c.decodeIfPresent(String.self, forKey: .namn) ?? ""
        ändelser = try c.decodeIfPresent([String].self, forKey: .ändelser) ?? []
        tillagd = try c.decodeIfPresent(Date.self, forKey: .tillagd) ?? Date()
    }

    var url: URL { URL(fileURLWithPath: väg) }
    var visatNamn: String { namn.isEmpty ? url.lastPathComponent : namn }
    var finns: Bool { FileManager.default.fileExists(atPath: väg) }
}

enum Kopplademappar {

    /// Filer det är någon mening med att indexera. Bilder och binärer ger
    /// ingenting, och att gå igenom dem tar bara tid.
    static let standardändelser: Set<String> = [
        // text och dokument
        "md", "markdown", "txt", "rtf", "csv", "tsv", "json", "yaml", "yml",
        "toml", "xml", "html", "htm", "pdf",
        // kod
        "swift", "py", "js", "jsx", "ts", "tsx", "rb", "go", "rs", "java", "kt",
        "c", "h", "cpp", "hpp", "m", "mm", "cs", "php", "sh", "bash", "zsh",
        "sql", "r", "jl", "lua", "pl", "vue", "svelte", "css", "scss",
    ]

    /// Mappar som aldrig är värda att läsa. Ett `node_modules` ensamt kan
    /// innehålla fler filer än hela resten av projektet.
    static let hoppaÖver: Set<String> = [
        ".git", ".svn", ".hg", "node_modules", ".build", "build", "dist",
        ".next", ".nuxt", "target", "vendor", "__pycache__", ".venv", "venv",
        "env", ".tox", ".mypy_cache", ".pytest_cache", "Pods", "DerivedData",
        ".gradle", ".idea", ".vscode", "coverage", ".cache", "tmp", ".DS_Store",
    ]

    /// Filer större än så här är sällan text man läser.
    static let maxStorlek = 2 * 1024 * 1024

    static func ärIntressant(_ url: URL, ändelser: Set<String>) -> Bool {
        let ändelse = url.pathExtension.lowercased()
        guard ändelser.contains(ändelse) else { return false }
        // Dolda filer är konfiguration, inte innehåll.
        return !url.lastPathComponent.hasPrefix(".")
    }

    /// Kontorsfiler, PDF, text och bilder: det som läses in i kunskapsbanken
    /// när mappen är dokument snarare än kod. Läsarna är Bilagors — Word,
    /// Excel och PowerPoint ur deras XML, PDF via PDFKit, bilder via Vision.
    static let dokumentändelser: Set<String> = [
        "pdf", "docx", "pptx", "xlsx", "docm", "pptm", "xlsm", "potx", "xltx",
        "md", "markdown", "txt", "rtf",
        "csv", "tsv", "html", "htm",
        "png", "jpg", "jpeg", "heic", "tiff", "tif",
    ]

    /// Kodfiler, till skillnad från dokument. En mapp med sådana får också
    /// agentsökningen, som kan följa spår mellan filer.
    static let kodändelser: Set<String> = standardändelser
        .subtracting(dokumentändelser)
        .subtracting(["json", "yaml", "yml", "toml", "xml"])

    /// Dokument får vara större: en PDF med bilder eller en presentation
    /// passerar lätt två megabyte utan att vara mindre värd att läsa.
    static let maxDokumentstorlek = 40 * 1024 * 1024

    /// Går igenom mappen och ger filerna som är värda att indexera.
    static func filer(i kopplad: Kopplad, max antal: Int = 400) -> [URL] {
        let ändelser = kopplad.ändelser.isEmpty
            ? standardändelser
            : Set(kopplad.ändelser.map { $0.lowercased() })
        return vandra(kopplad, ändelser: ändelser, maxStorlek: maxStorlek, max: antal)
    }

    /// Dokumenten i mappen, för kunskapsbanken.
    static func dokument(i kopplad: Kopplad, max antal: Int = 5000) -> [URL] {
        vandra(kopplad, ändelser: dokumentändelser, maxStorlek: maxDokumentstorlek, max: antal)
    }

    /// Om mappen innehåller kod, och därmed är värd en agent per fråga. En
    /// mapp med bara dokument ligger redan i kunskapsbanken; att låta en
    /// agent läsa igenom den på nytt vid varje fråga vore både långsamt och
    /// överflödigt.
    static func harKod(_ kopplad: Kopplad) -> Bool {
        !vandra(kopplad, ändelser: kodändelser, maxStorlek: maxStorlek, max: 1).isEmpty
    }

    /// Om filen bara är en platshållare vars innehåll ligger kvar i molnet.
    /// OneDrive, iCloud och Dropbox visar sådana som vanliga filer i Finder,
    /// men läsning ger ingenting eller väntar på nedladdning. Uppmätt på en
    /// OneDrive-mapp: 361 av 583 filer. Flaggan är SF_DATALESS i stat().
    static func ärPlatshållare(_ url: URL) -> Bool {
        var st = stat()
        guard stat(url.path, &st) == 0 else { return false }
        return st.st_flags & UInt32(SF_DATALESS) != 0
    }

    private static func vandra(_ kopplad: Kopplad, ändelser: Set<String>,
                               maxStorlek: Int, max antal: Int) -> [URL] {
        let fm = FileManager.default
        guard let vandring = fm.enumerator(
            at: kopplad.url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]) else { return [] }

        var ut: [URL] = []
        for fall in vandring {
            guard let url = fall as? URL else { continue }
            if hoppaÖver.contains(url.lastPathComponent) {
                vandring.skipDescendants()
                continue
            }
            let värden = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if värden?.isDirectory == true { continue }
            // Office lämnar låsfiler som «~$Rapport.docx» medan ett dokument
            // är öppet. De är inte dokument.
            if url.lastPathComponent.hasPrefix("~$") { continue }
            guard ärIntressant(url, ändelser: ändelser),
                  (värden?.fileSize ?? 0) <= maxStorlek else { continue }
            ut.append(url)
            if ut.count >= antal { break }
        }
        return ut
    }
}

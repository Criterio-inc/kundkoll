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

    /// Går igenom mappen och ger filerna som är värda att indexera.
    static func filer(i kopplad: Kopplad, max antal: Int = 400) -> [URL] {
        let ändelser = kopplad.ändelser.isEmpty
            ? standardändelser
            : Set(kopplad.ändelser.map { $0.lowercased() })
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
            guard ärIntressant(url, ändelser: ändelser),
                  (värden?.fileSize ?? 0) <= maxStorlek else { continue }
            ut.append(url)
            if ut.count >= antal { break }
        }
        return ut
    }
}

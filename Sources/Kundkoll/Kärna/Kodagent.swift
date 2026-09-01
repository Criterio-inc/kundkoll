import Foundation

/// Låter en agent söka och läsa i en kopplad mapp när en fråga ställs.
///
/// Kopplade mappar indexeras medvetet **inte** i kunskapsbanken. En enda liten
/// kodmapp gav 481 stycken mot 70 för allt annat material om kunden
/// tillsammans — kodträffar skulle dränka varje sökning. Kod ändras dessutom
/// dagligen, så ett index är gammalt nästan direkt, och en kodfråga besvaras
/// sällan av 900 tecken ur en fil: den kräver att man följer spår mellan filer.
///
/// Claude Code kan just det, och finns redan installerad. Den körs med enbart
/// läsande verktyg och i mappen den ska svara om.
actor Kodagent {

    struct Svar {
        var text: String
        var mapp: String
        var sekunder: Double
    }

    private let körbar: URL

    init(körbar: URL? = nil) {
        self.körbar = körbar ?? Self.hitta()
    }

    /// `claude` ligger sällan i det knappa PATH en GUI-app ärver.
    static func hitta() -> URL {
        let hem = FileManager.default.homeDirectoryForCurrentUser
        let kandidater = [
            hem.appending(path: ".local/bin/claude"),
            hem.appending(path: ".claude/local/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude"),
        ]
        return kandidater.first { FileManager.default.isExecutableFile(atPath: $0.path) }
            ?? kandidater[0]
    }

    var finns: Bool { FileManager.default.isExecutableFile(atPath: körbar.path) }

    /// Ställer frågan i en mapp och väntar in svaret.
    func fråga(_ text: String, i mapp: URL, om kund: String, projekt: String?) async throws -> Svar {
        guard finns else { throw Fel.saknas }
        guard FileManager.default.fileExists(atPath: mapp.path) else { throw Fel.ingenMapp }

        let uppdrag = """
        Du svarar på en fråga om mappen du står i. Den hör till projektet \
        \(projekt ?? kund) hos kunden \(kund).

        Fråga: \(text)

        Sök i filerna och svara på svenska, kort och konkret. Hänvisa till filer \
        med sökväg och radnummer där det är relevant. Hittar du inte svaret i \
        mappen säger du det rent ut i stället för att gissa.
        """

        let p = Process()
        p.executableURL = körbar
        p.currentDirectoryURL = mapp
        // Enbart läsande verktyg: agenten ska svara på frågor om mappen,
        // aldrig ändra i den.
        p.arguments = ["-p", uppdrag, "--allowedTools", "Read Grep Glob"]
        var miljö = ProcessInfo.processInfo.environment
        miljö["PATH"] = (miljö["PATH"] ?? "") + ":/opt/homebrew/bin:/usr/local/bin"
        p.environment = miljö

        let ut = Pipe(), fel = Pipe()
        p.standardOutput = ut
        p.standardError = fel

        let t0 = Date()
        try p.run()
        let data = ut.fileHandleForReading.readDataToEndOfFile()
        let felData = fel.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()

        let svar = (String(data: data, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard p.terminationStatus == 0, !svar.isEmpty else {
            let text = String(data: felData, encoding: .utf8) ?? ""
            throw Fel.misslyckades(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return Svar(text: svar, mapp: mapp.lastPathComponent,
                    sekunder: Date().timeIntervalSince(t0))
    }

    enum Fel: LocalizedError {
        case saknas, ingenMapp, misslyckades(String)
        var errorDescription: String? {
            switch self {
            case .saknas:
                "Claude Code hittades inte. Utan den kan kopplade mappar inte genomsökas."
            case .ingenMapp: "Den kopplade mappen finns inte längre."
            case .misslyckades(let f):
                f.isEmpty ? "Genomsökningen av mappen misslyckades." : "Mappen kunde inte läsas: \(f)"
            }
        }
    }
}

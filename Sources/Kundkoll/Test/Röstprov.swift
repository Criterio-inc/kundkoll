import Foundation

/// Kör röstanalysen mot en färdig whisper-utdata och jämför med ett facit.
///
///     Kundkoll --prov-röst <ljud.wav> <whisper.json> [facit.json]
///
/// Facit är valfritt och ser ut så här, en post per talare:
///     [{"namn": "Anders", "start": 0.0, "slut": 19.8}, ...]
/// Utan facit skrivs bara grupperingen ut för ögonbedömning.
enum Röstprov {

    struct Facit: Decodable { let namn: String; let start: Double; let slut: Double }

    static func kör(ljud: String, whisper: String, facit: String?) async -> Int32 {
        let ljudURL = URL(fileURLWithPath: ljud)
        guard FileManager.default.fileExists(atPath: ljudURL.path) else {
            print("Hittar inte \(ljud)"); return 1
        }
        guard let wdata = try? Data(contentsOf: URL(fileURLWithPath: whisper)) else {
            print("Hittar inte \(whisper)"); return 1
        }

        // Skriptet ligger i källträdet när provet körs från bygget.
        let sökvägar = Röstanalys.Sökvägar(
            python: FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Projekt/transcriber/venv/bin/python"),
            skript: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appending(path: "scripts/rostanalys.py"))
        if !sökvägar.brister.isEmpty {
            for b in sökvägar.brister { print("· \(b)") }
            return 1
        }

        let yttranden = Whisper.tolka(wdata, röst: .motpart, förskjutning: 0)
        print("\(yttranden.count) yttranden ur whisper")

        let turer = Röstanalys.turer(av: yttranden)
        let total = turer.reduce(0.0) { $0 + $1.längd }
        print("\(turer.count) turer, \(String(format: "%.0f", total)) s tal, "
              + "median \(String(format: "%.1f", median(turer.map(\.längd)))) s")

        let analys = Röstanalys(sökvägar: sökvägar)
        print("Hämtar röstavtryck …")
        let t0 = Date()
        let par: [(Röstanalys.Tur, Avtryck)]
        do { par = try await analys.avtryck(fil: ljudURL, turer: turer) } catch {
            print("  gick inte: \(error.localizedDescription)"); return 1
        }
        print("  \(par.count) avtryck på \(String(format: "%.1f", Date().timeIntervalSince(t0))) s")
        guard !par.isEmpty else { print("Inga avtryck."); return 1 }

        // Med --väntade <n> provas ledtråden från kalendern, utan den
        // gissningen ur likheterna.
        let väntade = CommandLine.arguments.firstIndex(of: "--väntade")
            .flatMap { $0 + 1 < CommandLine.arguments.count ? Int(CommandLine.arguments[$0 + 1]) : nil }
        // Samma väg som appen tar: pyannote först, klustring som reserv.
        var grupper: [Röstanalys.Röstgrupp] = []
        var metod = "klustring"
        if let segment = try? await analys.diarisera(fil: ljudURL, antal: väntade) {
            var perTur: [Röstanalys.Tur: Avtryck] = [:]
            for (t, a) in par { perTur[t] = a }
            let ut = Röstanalys.gruppera(turer: turer, avtryck: perTur, enligt: segment)
            if !ut.isEmpty {
                grupper = ut
                metod = "pyannote, \(segment.count) segment"
            }
        }
        if grupper.isEmpty { grupper = Röstanalys.gruppera(par, väntade: väntade) }
        print("\nGrupperade till \(grupper.count) röster med \(metod)\(väntade.map { ", väntade \($0)" } ?? ""):")
        for (i, g) in grupper.enumerated() {
            print(String(format: "  Röst %d: %2d turer, %5.0f s  «%@»",
                         i + 1, g.turer.count, g.längd, String(g.exempel.prefix(56))))
        }

        guard let facit, let fdata = try? Data(contentsOf: URL(fileURLWithPath: facit)),
              let rader = try? JSONDecoder().decode([Facit].self, from: fdata) else {
            print("\n(inget facit angivet — ingen bedömning)")
            return 0
        }

        // Vem säger facit att den här turen är?
        func sant(_ t: Röstanalys.Tur) -> String? {
            let mitt = (t.start + t.slut) / 2
            return rader.first { mitt >= $0.start && mitt < $0.slut }?.namn
        }

        print("\nMot facit:")
        var rätt = 0, totalt = 0
        var förvirring: [String: [Int: Int]] = [:]
        for (i, g) in grupper.enumerated() {
            for t in g.turer {
                guard let namn = sant(t) else { continue }
                förvirring[namn, default: [:]][i, default: 0] += 1
                totalt += 1
            }
        }
        // Varje grupp får den talare den mest består av
        var gruppNamn: [Int: String] = [:]
        for (namn, fördelning) in förvirring {
            for (g, n) in fördelning where n == fördelning.values.max() {
                if gruppNamn[g] == nil { gruppNamn[g] = namn }
            }
        }
        for (namn, fördelning) in förvirring.sorted(by: { $0.key < $1.key }) {
            let rader = fördelning.sorted { $0.value > $1.value }
                .map { "Röst \($0.key + 1): \($0.value)" }.joined(separator: ", ")
            let egna = fördelning.filter { gruppNamn[$0.key] == namn }.values.reduce(0, +)
            rätt += egna
            print("  \(namn.padding(toLength: 10, withPad: " ", startingAt: 0)) \(rader)")
        }
        let andel = totalt == 0 ? 0 : Double(rätt) / Double(totalt) * 100
        print(String(format: "\n%d av %d turer i rätt grupp (%.0f %%)", rätt, totalt, andel))

        Prov.svit("Röstanalys")
        Prov.kolla(!grupper.isEmpty, "ljudet gav röstgrupper")
        Prov.kolla(grupper.count >= 2, "flera röster hittades (\(grupper.count))")
        Prov.kolla(andel >= 70, String(format: "minst 70 %% av turerna hamnar rätt (%.0f %%)", andel))
        Prov.kolla(grupper.count <= rader.count * 2,
                   "rösterna splittras inte oöverskådligt (\(grupper.count) mot \(rader.count) i facit)")
        return Prov.sammanfatta()
    }

    private static func median(_ v: [Double]) -> Double {
        guard !v.isEmpty else { return 0 }
        let s = v.sorted()
        return s[s.count / 2]
    }
}

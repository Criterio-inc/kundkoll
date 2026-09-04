import SwiftUI
import AppKit

/// `Kundkoll --test` kör provsviten i terminalen, annars startar appen.
/// Testramverken följer inte med Command Line Tools, så testerna bor i appen.
@main
struct Ingång {
    static func main() {
        if let i = CommandLine.arguments.firstIndex(of: "--prov-insikter") {
            let modeller = Array(CommandLine.arguments.dropFirst(i + 1))
            let sem = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var kod: Int32 = 1
            Task.detached { kod = await Insiktsprov.kör(modeller: modeller); sem.signal() }
            sem.wait()
            exit(kod)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--prov-transkribering"),
           i + 1 < CommandLine.arguments.count {
            let a = CommandLine.arguments
            let motor = i + 2 < a.count ? a[i + 2] : nil
            let modell = i + 3 < a.count ? a[i + 3] : nil
            let sem = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var kod: Int32 = 1
            Task.detached {
                kod = await Transkriberingsprov.kör(fil: a[i + 1], motor: motor, modell: modell)
                sem.signal()
            }
            sem.wait()
            exit(kod)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--transkribera-om"),
           i + 1 < CommandLine.arguments.count {
            let a = CommandLine.arguments
            let mapp = URL(fileURLWithPath: a[i + 1])
            let språk = i + 2 < a.count ? (a[i + 2] == "auto" ? nil : a[i + 2]) : "sv"
            nonisolated(unsafe) var kod: Int32? = nil
            Task { @MainActor in
                do {
                    guard let data = try? Data(contentsOf: mapp.appending(path: "möte.json")),
                          let gammal = try? JSONDecoder.kundkoll.decode(Inspelning.self, from: data),
                          let kund = Arkivet.shared.kunder.first(where: { $0.namn == gammal.kund })
                    else { throw Enkeltfel("Hittar ingen läsbar inspelning i \(mapp.path)") }
                    let placering: Placering = gammal.projekt.flatMap { namn in
                        Arkivet.shared.projekt(för: kund).first { $0.namn == namn }
                            .map { Placering.projekt($0) }
                    } ?? .kund(kund)
                    let profiler = Arkivet.shared.röstprofiler(för: kund)
                    print("Modell: \(Modellval.läs().etikett)")
                    let ny = try await Import().slutför(
                        mapp: mapp, placering: placering, profiler: profiler,
                        titel: gammal.titel, språk: språk,
                        vidLäge: { l in print("  \(l.steg)") })
                    print("Klar: \(ny.yttranden.count) yttranden")
                    for y in ny.yttranden.prefix(4) { print("  · \(y.text.prefix(80))") }
                    kod = ny.yttranden.isEmpty ? 1 : 0
                } catch {
                    print("Gick inte: \(error.localizedDescription)")
                    kod = 1
                }
            }
            while kod == nil {
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
            }
            exit(kod ?? 1)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--prov-läget"),
           i + 2 < CommandLine.arguments.count {
            let a = CommandLine.arguments
            // Läget.skriv är huvudaktörsbunden, så huvudtråden kan inte stå i
            // en semafor — den pumpar körslingan tills jobbet är klart.
            nonisolated(unsafe) var kod: Int32? = nil
            Task { @MainActor in
                do {
                    guard let kund = Arkivet.shared.kunder.first(where: { $0.namn == a[i + 1] }),
                          let projekt = Arkivet.shared.projekt(för: kund)
                            .first(where: { $0.namn == a[i + 2] })
                    else { throw Enkeltfel("Hittar inte \(a[i + 1]) / \(a[i + 2])") }
                    print("Modell: \(Modellval.läs().etikett)")
                    let bild = try await Läget.skriv(kund: kund, projekt: projekt)
                    print(bild.text)
                    Prov.svit("Lägesbilden skarpt")
                    Prov.kolla(!bild.text.isEmpty, "modellen skrev en lägesbild")
                    kod = Prov.sammanfatta()
                } catch {
                    print("Gick inte: \(error.localizedDescription)")
                    kod = 1
                }
            }
            while kod == nil {
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
            }
            exit(kod ?? 1)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--prov-uppgifter"),
           i + 1 < CommandLine.arguments.count {
            // Kör uppgiftsletaren på en textfil och skriver ut vad modellen
            // svarade, eller felet — det som rundan i appen annars döljer.
            let fil = CommandLine.arguments[i + 1]
            nonisolated(unsafe) var kod: Int32? = nil
            Task { @MainActor in
                do {
                    let text = try String(contentsOfFile: fil, encoding: .utf8)
                    print("Modell: \(Modellval.läs().leverantör.namn) · \(Modellval.läs().modell)")
                    let t0 = Date()
                    let letare = Uppgiftsletare()
                    let u = try await letare.leta(i: text, sammanhang: "ett mejl jag fått",
                                                  kund: "Provkunden")
                    print(String(format: "%d uppgifter på %.1f s", u.count, Date().timeIntervalSince(t0)))
                    for x in u { print("  · \(x.vad)\(x.vem.map { " — \($0)" } ?? "")\(x.när.map { " (\($0))" } ?? "")") }
                    if u.isEmpty { print("Råsvar:\n\(await letare.senasteSvar)") }
                    kod = 0
                } catch {
                    print("Gick inte: \(error.localizedDescription)")
                    kod = 1
                }
            }
            while kod == nil { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1)) }
            exit(kod ?? 1)
        }
        if CommandLine.arguments.contains("--prov-datum") {
            let sem = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var kod: Int32 = 1
            Task.detached { kod = await Datumprov.kör(); sem.signal() }
            sem.wait()
            exit(kod)
        }
        if CommandLine.arguments.contains("--test") {
            exit(MainActor.assumeIsolated { Tester.kör() })
        }
        if let i = CommandLine.arguments.firstIndex(of: "--prov-omröst"),
           i + 1 < CommandLine.arguments.count {
            let a = CommandLine.arguments
            let förväntat = i + 2 < a.count ? Int(a[i + 2]) : nil
            let sem = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var kod: Int32 = 1
            Task.detached { kod = await Omröstprov.kör(mapp: a[i + 1], förväntat: förväntat); sem.signal() }
            sem.wait()
            exit(kod)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--prov-chatt") {
            let arg = Array(CommandLine.arguments.dropFirst(i + 1))
            let sem = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var kod: Int32 = 1
            Task.detached { kod = await Chattprov.kör(argument: arg); sem.signal() }
            sem.wait()
            exit(kod)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--prov-kodagent"),
           i + 2 < CommandLine.arguments.count {
            let a = CommandLine.arguments
            let sem = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var kod: Int32 = 1
            Task.detached { kod = await Kodagentprov.kör(mapp: a[i + 1], fråga: a[i + 2]); sem.signal() }
            sem.wait()
            exit(kod)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--prov-bilagehämtning"),
           i + 1 < CommandLine.arguments.count {
            let a = CommandLine.arguments
            let mapp = i + 2 < a.count ? a[i + 2] : nil
            let sem = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var kod: Int32 = 1
            Task.detached { kod = await Bilageprov.hämtning(adress: a[i + 1], mapp: mapp); sem.signal() }
            sem.wait()
            exit(kod)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--prov-dokument"),
           i + 1 < CommandLine.arguments.count {
            let mapp = CommandLine.arguments[i + 1]
            let sem = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var kod: Int32 = 1
            Task.detached { kod = await Dokumentprov.kör(mapp: mapp); sem.signal() }
            sem.wait()
            exit(kod)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--prov-bilaga") {
            let filer = Array(CommandLine.arguments.dropFirst(i + 1))
            let sem = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var kod: Int32 = 1
            Task.detached { kod = await Bilageprov.kör(filer: filer); sem.signal() }
            sem.wait()
            exit(kod)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--prov-import") {
            let filer = Array(CommandLine.arguments.dropFirst(i + 1))
            let sem = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var kod: Int32 = 1
            Task.detached { kod = await Importprov.kör(filer: filer); sem.signal() }
            sem.wait()
            exit(kod)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--prov-röst"),
           i + 2 < CommandLine.arguments.count {
            let a = CommandLine.arguments
            let facit = i + 3 < a.count ? a[i + 3] : nil
            let sem = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var kod: Int32 = 1
            Task.detached {
                kod = await Röstprov.kör(ljud: a[i + 1], whisper: a[i + 2], facit: facit)
                sem.signal()
            }
            sem.wait()
            exit(kod)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--prov-ljud"),
           i + 1 < CommandLine.arguments.count {
            let fil = CommandLine.arguments[i + 1]
            let sem = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var kod: Int32 = 1
            Task.detached { kod = await Ljudprov.kör(fil: fil); sem.signal() }
            sem.wait()
            exit(kod)
        }
        Kundkoll.main()
    }
}

/// Frågar innan appen avslutas mitt i ett arbete som skulle gå förlorat.
final class Appdelegat: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let s = Inspelningssession.delad
        let kö = Importkö.delad
        let vad: String?
        if s.pågår {
            vad = "Inspelningen «\(s.titel)» pågår."
        } else if s.arbetar {
            vad = "Renskrivningen av «\(s.titel)» pågår, \(Int(s.efterbearbetningsandel * 100)) %. Avslutas appen står mötet kvar utan sammanfattning och utan åtaganden på tavlan."
        } else if kö.pågår {
            vad = "En import pågår: \(kö.steg)."
        } else {
            vad = nil
        }
        guard let vad else { return .terminateNow }
        let ruta = NSAlert()
        ruta.messageText = "Avsluta ändå?"
        ruta.informativeText = vad
        ruta.addButton(withTitle: "Avbryt")
        ruta.addButton(withTitle: "Avsluta ändå")
        return ruta.runModal() == .alertFirstButtonReturn ? .terminateCancel : .terminateNow
    }
}

struct Kundkoll: App {
    @NSApplicationDelegateAdaptor(Appdelegat.self) private var delegat
    @StateObject private var arkiv = Arkivet.shared
    @StateObject private var session = Inspelningssession.delad
    @StateObject private var adressbok = Adressboken.shared
    @StateObject private var kalender = Kalendern.shared

    init() {
        // Whisper-servern hålls varm mellan inspelningar, men ska inte
        // överleva appen. Vakten i Whisper.startaServer tar krascherna;
        // det här tar den vanliga avslutningen utan att vänta på vakten.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            Task { await Whisper.delad.avsluta() }
        }
    }

    var body: some Scene {
        WindowGroup {
            Huvudvy()
                .environmentObject(arkiv)
                .environmentObject(session)
                .environmentObject(adressbok)
                .environmentObject(kalender)
                .frame(minWidth: 900, minHeight: 560)
                .task {
                    Notiser.startaMottagning()
                    // Kalendern frågas direkt: mötena är det första man vill
                    // se. Kontakter och Mail frågas först när de används.
                    if kalender.behörighet == .notDetermined {
                        await kalender.begärTillgång()
                    }
                    // Modellen tar omkring tio sekunder att ladda. Görs det nu
                    // står den redo när någon trycker på «Spela in».
                    await Whisper.delad.värmUpp()
                }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Ny kund …") { NotificationCenter.default.post(name: .nyKund, object: nil) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                Button("Sök …") { NotificationCenter.default.post(name: .sök, object: nil) }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                Button("Hoppa till …") { NotificationCenter.default.post(name: .palett, object: nil) }
                    .keyboardShortcut("k", modifiers: .command)
            }
            CommandGroup(after: .appSettings) {
                Button("Inställningar …") {
                    NotificationCenter.default.post(name: .visaNyckel, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let nyKund = Notification.Name("kundkoll.nyKund")
    static let visaNyckel = Notification.Name("kundkoll.visaNyckel")
    static let sök = Notification.Name("kundkoll.sök")
    static let palett = Notification.Name("kundkoll.palett")
    /// Skickas när ett notisklick vill öppna en kund; objektet är kundnamnet
    /// och userInfo kan bära mötets id för en briefing.
    static let öppnaKund = Notification.Name("kundkoll.öppnaKund")
}

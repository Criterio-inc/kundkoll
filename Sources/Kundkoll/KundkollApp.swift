import SwiftUI

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

struct Kundkoll: App {
    @StateObject private var arkiv = Arkivet.shared
    @StateObject private var session = Inspelningssession.delad
    @StateObject private var adressbok = Adressboken.shared
    @StateObject private var kalender = Kalendern.shared

    var body: some Scene {
        WindowGroup {
            Huvudvy()
                .environmentObject(arkiv)
                .environmentObject(session)
                .environmentObject(adressbok)
                .environmentObject(kalender)
                .frame(minWidth: 900, minHeight: 560)
                .task {
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
            }
            CommandGroup(after: .appSettings) {
                Button("AI-modell och nyckel …") {
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
}

import SwiftUI
import AppKit

/// `Kundkoll --test` kör provsviten i terminalen, `--hjälp` listar de andra
/// provlägena, annars startar appen. Testramverken följer inte med Command
/// Line Tools, så proven bor i appen. Lägena står i Test/Provlägen.swift.
@main
struct Ingång {
    static func main() {
        let a = CommandLine.arguments.dropFirst()
        if let första = a.first, första.hasPrefix("--") {
            if första == "--hjälp" || första == "--help" {
                print(Provlägen.hjälp); exit(0)
            }
            guard let läge = Provlägen.alla.first(where: { $0.flagga == första }) else {
                print("Okänt läge: \(första)\n\n\(Provlägen.hjälp)"); exit(2)
            }
            let argument = Array(a.dropFirst())
            guard argument.count >= läge.minst else {
                print("\(läge.flagga) behöver: \(läge.bruk)"); exit(2)
            }
            kör(läge, argument)
        }
        Kundkoll.main()
    }

    /// Kör ett provläge till slut och avslutar med dess kod. Huvudtråden
    /// pumpar körslingan i stället för att stå i en semafor, så jobbet får
    /// använda huvudaktören utan att låsa (se Provläge).
    static func kör(_ läge: Provläge, _ argument: [String]) -> Never {
        nonisolated(unsafe) var kod: Int32? = nil
        Task { @MainActor in
            do { kod = try await läge.kör(argument) }
            catch {
                print("Gick inte: \(error.localizedDescription)")
                kod = 1
            }
        }
        // Ett prov som hänger, på en server som aldrig svarar, får inte
        // hänga bygget för evigt: efter taket (KUNDKOLL_PROVTID sekunder,
        // annars en halvtimme) slutar det med kod 124, som timeout gör.
        let tak = Double(ProcessInfo.processInfo.environment["KUNDKOLL_PROVTID"] ?? "") ?? 1800
        let slut = Date().addingTimeInterval(tak)
        while kod == nil {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
            if Date() > slut {
                print("\n\(läge.flagga) blev inte klart på \(Int(tak)) sekunder och avbryts.")
                exit(124)
            }
        }
        exit(kod ?? 1)
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

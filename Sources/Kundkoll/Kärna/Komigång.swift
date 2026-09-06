import Foundation
import AVFoundation
import CoreGraphics

/// Arbetssättet i åtta steg, i den ordning man jobbar, med en bock som
/// appen sätter själv när steget är gjort. Sidan «Kom igång» visar dem.
///
/// Kund är relationen, projekt är ett betalt uppdrag; det som kommer in
/// hamnar på uppdraget; tavlan och Min vecka är där dagen börjar, briefen
/// där mötet börjar. Stegen lär ut just det, och säger var man står.
@MainActor
enum Komigång {

    /// Vart «Visa mig» tar en.
    enum Mål {
        case nyKund
        case kund(Kund, flik: String?)
        case spelaIn(Kund)
        case minVecka
        case inställningar
    }

    struct Steg: Identifiable {
        let id: String
        let rubrik: String
        /// Varför steget är värt att göra, en eller två meningar.
        let varför: String
        let klar: Bool
        let mål: Mål
    }

    static func steg(arkiv: Arkivet) -> [Steg] {
        let kunder = arkiv.kunder
        let första = kunder.first
        let medProjekt = kunder.first { !arkiv.projekt(för: $0).isEmpty }
        let harKontakter = kunder.contains { !arkiv.kontakter(för: $0).isEmpty }
        let harMejl = kunder.contains { arkiv.mailcache(för: $0) != nil }
        let harInspelning = kunder.contains { !arkiv.inspelningar(för: $0).isEmpty }
        let harKlart = kunder.contains { arkiv.uppgifter(för: $0).contains { $0.läge == .klart } }
        let mik = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let skärm = CGPreflightScreenCaptureAccess()
        let redo = Diagnos.lokala().allSatisfy { $0.läge != .saknas } && mik && skärm

        return [
            Steg(id: "kund",
                 rubrik: "Skapa kunden och uppdraget",
                 varför: "Kunden är relationen, projektet är ett betalt uppdrag. Med ett enda uppdrag hamnar allt som kommer in där av sig självt; ett nytt uppdrag blir ett nytt projekt.",
                 klar: medProjekt != nil,
                 mål: första.map { .kund($0, flik: nil) } ?? .nyKund),
            Steg(id: "kontakter",
                 rubrik: "Lägg in kundens kontakter",
                 varför: "Adresserna är det appen söker mejl på, och namnen är de rösterna får. Dra personerna från Outlook till Finder och importera filen under Hantera.",
                 klar: harKontakter,
                 mål: första.map { .kund($0, flik: "översikt") } ?? .nyKund),
            Steg(id: "mejl",
                 rubrik: "Hämta mejlen",
                 varför: "Åtaganden ur mejlen läggs på tavlan utan att du gör något; de tio nyaste går igenom vid varje hämtning. «Leta åtaganden i alla mejl» tar historiken en gång.",
                 klar: harMejl,
                 mål: första.map { .kund($0, flik: "mail") } ?? .nyKund),
            Steg(id: "brief",
                 rubrik: "Läs på inför mötet",
                 varför: "Med kalendern beviljad kommer en notis en kvart före kundmötet: förra mötet i serien, det som lämnades öppet, vad du väntar på och mejlen sedan sist.",
                 klar: Kalendern.shared.harTillgång,
                 mål: .inställningar),
            Steg(id: "inspelning",
                 rubrik: "Spela in ett möte",
                 varför: "Ditt spår och motpartens spelas in var för sig, skrivs rent på datorn och blir en sammanfattning med beslut, åtaganden och öppna frågor. Inget lämnar maskinen.",
                 klar: harInspelning,
                 mål: första.map { .spelaIn($0) } ?? .nyKund),
            Steg(id: "tavlan",
                 rubrik: "Håll tavlan levande",
                 varför: "Bocka det som är gjort, dra det som pågår. När nästa möte i serien säger att något är klart föreslår appen det med belägg, och du bekräftar.",
                 klar: harKlart,
                 mål: (medProjekt ?? första).map { .kund($0, flik: "attGöra") } ?? .nyKund),
            Steg(id: "minVecka",
                 rubrik: "Börja dagen i Min vecka",
                 varför: "Allt öppet hos alla kunder i två spalter: det du ska göra och det du väntar på från andra, försenat överst.",
                 klar: markerad("minVecka"),
                 mål: .minVecka),
            Steg(id: "diagnos",
                 rubrik: "Se att allt finns",
                 varför: "Inställningar › Diagnos provar whisper, Python, Ollama och behörigheterna, och säger vad som saknas och hur det ordnas.",
                 klar: redo,
                 mål: .inställningar),
        ]
    }

    // MARK: - Det appen inte kan se på disk

    private static func nyckel(_ id: String) -> String { "kundkoll.komIgång.\(id)" }

    /// Steg som bockas när sidan besökts: Min vecka.
    static func markera(_ id: String) {
        UserDefaults.standard.set(true, forKey: nyckel(id))
    }

    static func markerad(_ id: String) -> Bool {
        UserDefaults.standard.bool(forKey: nyckel(id))
    }

    /// Dold i sidopanelen på egen begäran; nås ändå under Hjälp.
    static var dold: Bool {
        get { UserDefaults.standard.bool(forKey: "kundkoll.komIgångDold") }
        set { UserDefaults.standard.set(newValue, forKey: "kundkoll.komIgångDold") }
    }

    /// Sidan visas i sidopanelen tills allt är gjort, om den inte dolts.
    static func visasISidopanelen(arkiv: Arkivet) -> Bool {
        !dold && steg(arkiv: arkiv).contains { !$0.klar }
    }
}

import Foundation

/// Importer i bakgrunden, en i taget.
///
/// Att lägga till en 40-minutersinspelning tar minuter, och det låste
/// tidigare hela appen bakom ett modalt blad. Nu stängs bladet direkt:
/// jobbet hamnar i kön, en rad längst ned i fönstret visar var det står,
/// och fler filer kan läggas på hög under tiden. Notisen när mötet är klart
/// kommer som vanligt.
@MainActor
final class Importkö: ObservableObject {
    static let delad = Importkö()

    struct Jobb: Identifiable {
        let id = UUID()
        let källa: URL
        let placering: Placering
        let titel: String
        let kund: Kund
        let språk: String?
        let inledd: Date?
    }

    @Published private(set) var aktuell: Jobb?
    @Published private(set) var väntande: [Jobb] = []
    @Published private(set) var steg = ""
    @Published private(set) var andel: Double?
    /// Senaste felet. Ligger kvar tills det stängs — ett jobb som föll i
    /// bakgrunden får inte försvinna spårlöst.
    @Published private(set) var fel: String?

    var pågår: Bool { aktuell != nil }

    func köa(källa: URL, placering: Placering, titel: String,
             kund: Kund, språk: String?, inledd: Date? = nil) {
        väntande.append(Jobb(källa: källa, placering: placering,
                             titel: titel, kund: kund, språk: språk, inledd: inledd))
        kör()
    }

    func stängFel() { fel = nil }

    private func kör() {
        guard aktuell == nil, !väntande.isEmpty else { return }
        let jobb = väntande.removeFirst()
        aktuell = jobb
        steg = "Förbereder"
        andel = nil

        Task {
            do {
                // Profilerna hämtas här och inte vid köandet: ett jobb som
                // väntat ska känna igen röster som märkts under tiden.
                let profiler = Arkivet.shared.röstprofiler(för: jobb.kund)
                _ = try await Import().importera(
                    jobb.källa, placering: jobb.placering, titel: jobb.titel,
                    kund: jobb.kund, profiler: profiler, språk: jobb.språk,
                    inledd: jobb.inledd,
                    vidLäge: { l in
                        Task { @MainActor in
                            self.steg = l.steg
                            self.andel = l.andel
                        }
                    })
            } catch {
                fel = "\(jobb.titel): \(error.localizedDescription)"
            }
            aktuell = nil
            kör()
        }
    }
}

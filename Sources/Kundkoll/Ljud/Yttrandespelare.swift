import Foundation
import AVFoundation

/// Spelar upp ett enskilt yttrande ur en inspelning.
///
/// Transkriptet är whispers ord; ljudet är vad som faktiskt sades. När en rad
/// ser konstig ut är det snabbare att höra efter än att gissa vem som sa fel
/// — modellen eller människan.
@MainActor
final class Yttrandespelare: ObservableObject {

    /// Yttrandet som just nu hörs.
    @Published private(set) var spelar: UUID?

    private var spelare: AVAudioPlayer?
    private var stopp: Task<Void, Never>?

    /// Vilket spår ett yttrande ligger på. Tvåspåriga inspelningar har mitt
    /// ljud för sig; i en importerad fil ligger alla röster i motpart.wav.
    static func fil(för yttrande: Yttrande, enspårig: Bool) -> String {
        yttrande.röst == .jag && !enspårig ? "jag.wav" : "motpart.wav"
    }

    /// Spelar yttrandet, eller tystnar om det redan hörs.
    func växla(_ yttrande: Yttrande, i mapp: URL, enspårig: Bool) {
        let hördes = spelar == yttrande.id
        sluta()
        guard !hördes else { return }

        let fil = mapp.appending(path: Self.fil(för: yttrande, enspårig: enspårig))
        guard let p = try? AVAudioPlayer(contentsOf: fil) else { return }
        spelare = p
        p.currentTime = max(0, yttrande.start)
        p.play()
        spelar = yttrande.id

        let längd = max(0.2, yttrande.slut - yttrande.start)
        stopp = Task { [weak self] in
            try? await Task.sleep(for: .seconds(längd))
            guard !Task.isCancelled else { return }
            self?.sluta()
        }
    }

    func sluta() {
        stopp?.cancel()
        stopp = nil
        spelare?.stop()
        spelare = nil
        spelar = nil
    }
}

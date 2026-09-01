import Foundation
import AVFoundation

/// Kör importens formatläsning skarpt.
///
///     Kundkoll --prov-import <fil> [fil …]
///
/// Konverteringen är den riskabla delen: filerna kommer från Teams, Zoom,
/// telefoner och diktafoner, och formaten varierar.
enum Importprov {

    static func kör(filer: [String]) async -> Int32 {
        Prov.svit("Import")
        guard !filer.isEmpty else { print("Ange minst en fil."); return 1 }

        for väg in filer {
            let källa = URL(fileURLWithPath: väg)
            guard FileManager.default.fileExists(atPath: källa.path) else {
                Prov.kolla(false, "\(källa.lastPathComponent) finns")
                continue
            }
            let mål = FileManager.default.temporaryDirectory
                .appending(path: "kundkoll-prov-\(UUID().uuidString).wav")
            defer { try? FileManager.default.removeItem(at: mål) }

            let t0 = Date()
            do {
                let längd = try await Import.tillWhisperformat(källa, mål: mål)
                let tid = Date().timeIntervalSince(t0)

                let ljud = try AVAudioFile(forReading: mål)
                let namn = källa.lastPathComponent
                Prov.kolla(längd > 0, "\(namn): \(String(format: "%.1f", längd)) s ljud "
                           + "på \(String(format: "%.1f", tid)) s")
                Prov.lika(ljud.fileFormat.sampleRate, 16_000, "\(namn): 16 kHz")
                Prov.lika(ljud.fileFormat.channelCount, 1, "\(namn): mono")
                let filsekunder = Double(ljud.length) / ljud.fileFormat.sampleRate
                Prov.kolla(abs(filsekunder - längd) < 0.1,
                           "\(namn): filen är lika lång som den rapporterade längden")

                // Ljudet ska innehålla något, inte bara nollor
                let buf = AVAudioPCMBuffer(pcmFormat: ljud.processingFormat,
                                           frameCapacity: AVAudioFrameCount(min(ljud.length, 160_000)))!
                try ljud.read(into: buf)
                var topp: Float = 0
                if let k = buf.floatChannelData?[0] {
                    for i in 0..<Int(buf.frameLength) { topp = max(topp, abs(k[i])) }
                }
                Prov.kolla(topp > 0.01, "\(namn): ljudet har innehåll (topp \(String(format: "%.2f", topp)))")
            } catch {
                Prov.kolla(false, "\(källa.lastPathComponent): \(error.localizedDescription)")
            }
        }
        // Framstegen läses ur whispers egen utskrift, och det som fungerar mot
        // en teststräng kan fungera dåligt mot den riktiga strömmen.
        if let första = filer.first {
            await provaFramsteg(URL(fileURLWithPath: första))
        }
        return Prov.sammanfatta()
    }

    private static func provaFramsteg(_ källa: URL) async {
        let mål = FileManager.default.temporaryDirectory
            .appending(path: "kundkoll-prov-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: mål) }
        guard let längd = try? await Import.tillWhisperformat(källa, mål: mål) else { return }

        print("\nTranskriberar \(källa.lastPathComponent) och följer framstegen:")
        nonisolated(unsafe) var andelar: [Double] = []
        nonisolated(unsafe) var rader = 0
        let whisper = Whisper()
        let rapporterade = (try? await whisper.arkivtranskribera(
            fil: mål, röst: .motpart, totalLängd: längd,
            vidFramsteg: { f in
                andelar.append(f.andel)
                rader += 1
                if rader % 3 == 1 {
                    print(String(format: "  %3.0f %%  «%@»", f.andel * 100,
                                 String(f.senasteRad.prefix(52))))
                }
            })) ?? []

        Prov.kolla(!andelar.isEmpty, "framsteg rapporterades under körningen (\(andelar.count) gånger)")
        Prov.kolla(andelar.allSatisfy { $0 >= 0 && $0 <= 1 },
                   "andelen håller sig mellan 0 och 1")
        Prov.kolla(zip(andelar, andelar.dropFirst()).allSatisfy { $0 <= $1 + 0.001 },
                   "andelen går bara framåt")
        Prov.kolla((andelar.last ?? 0) > 0.5,
                   String(format: "sista rapporten är nära slutet (%.0f %%)", (andelar.last ?? 0) * 100))
        Prov.kolla(!rapporterade.isEmpty, "transkriptet kom med trots att utdata lästes")
    }
}

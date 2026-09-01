import Foundation
import AVFoundation

/// Kör en riktig ljudfil genom hela kedjan: buffring → fönster → KB-Whisper →
/// yttranden. Startar en skarp whisper-server, så det här är det prov som
/// faktiskt visar att transkriberingen fungerar.
///
///     Kundkoll --prov-ljud <fil.wav>
///
/// Ligger medvetet utanför huvudaktören: provet väntar in resultatet
/// synkront, och då måste huvudtråden vara fri att köra arbetet.
enum Ljudprov {

    static func kör(fil: String) async -> Int32 {
        let url = URL(fileURLWithPath: fil)
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("Hittar inte \(url.path)")
            return 1
        }

        let sökvägar = Whisper.Sökvägar.standard
        if !sökvägar.brister.isEmpty {
            print("Kan inte köra provet:")
            for b in sökvägar.brister { print("  · \(b)") }
            return 1
        }

        print("Läser \(url.lastPathComponent)")
        guard let ljud = try? AVAudioFile(forReading: url) else {
            print("Kunde inte öppna filen som ljud"); return 1
        }
        let längd = Double(ljud.length) / ljud.processingFormat.sampleRate
        print("  \(String(format: "%.1f", längd)) s, \(Int(ljud.processingFormat.sampleRate)) Hz, \(ljud.processingFormat.channelCount) kanal(er)")

        let whisper = Whisper(sökvägar: sökvägar)
        print("Startar whisper-server med \(sökvägar.livemodell) …")
        let t0 = Date()
        do { try await whisper.startaServer() } catch {
            print("  gick inte: \(error.localizedDescription)"); return 1
        }
        print("  klar efter \(String(format: "%.1f", Date().timeIntervalSince(t0))) s")

        // Mata ljudet genom buffringen precis som under en inspelning.
        let buffring = Ljudbuffring()
        var fönster: [Ljudbuffring.Fönster] = []
        let bit: AVAudioFrameCount = 4096
        var tid = 0.0
        while true {
            guard let buf = AVAudioPCMBuffer(pcmFormat: ljud.processingFormat, frameCapacity: bit) else { break }
            do { try ljud.read(into: buf, frameCount: bit) } catch { break }
            if buf.frameLength == 0 { break }
            let (_, f) = buffring.mata(Ljudram(röst: .motpart, buffert: buf, tid: tid))
            if let f { fönster.append(f) }
            tid += Double(buf.frameLength) / ljud.processingFormat.sampleRate
        }
        if let sista = buffring.spola() { fönster.append(sista) }

        print("Buffringen delade ljudet i \(fönster.count) fönster:")
        for (i, f) in fönster.enumerated() {
            print(String(format: "  %2d. %5.1f–%5.1f s  (%.1f s)", i + 1, f.start, f.slut, f.slut - f.start))
        }
        guard !fönster.isEmpty else {
            print("Inga fönster — buffringen släppte igenom ingenting."); await whisper.stoppaServer(); return 1
        }

        print("Transkriberar …")
        var rader: [Yttrande] = []
        var totalTid = 0.0
        for f in fönster {
            let s = Date()
            let text = (try? await whisper.transkribera(prov: f.prov)) ?? ""
            let d = Date().timeIntervalSince(s)
            totalTid += d
            guard !text.isEmpty else { continue }
            rader.append(Yttrande(röst: .motpart, text: text, start: f.start, slut: f.slut))
            print(String(format: "  [%5.1f s, tog %.2f s] %@", f.start, d, text))
        }
        await whisper.stoppaServer()

        print("")
        let ord = rader.reduce(0) { $0 + $1.text.split(separator: " ").count }
        print("\(rader.count) rader, \(ord) ord.")
        print(String(format: "Transkribering tog %.1f s för %.1f s ljud (%.0f× realtid).",
                     totalTid, längd, längd / max(totalTid, 0.001)))

        // Det som faktiskt måste hålla för att kedjan ska duga.
        Prov.svit("Hela kedjan")
        Prov.kolla(!rader.isEmpty, "ljudet gav text")
        Prov.kolla(ord > Int(längd / 3), "rimlig mängd ord för längden (\(ord) ord på \(Int(längd)) s)")
        Prov.kolla(totalTid < längd, "transkriberingen hinner före uppspelningen")
        Prov.kolla(rader.allSatisfy { $0.slut >= $0.start }, "tiderna går framåt")
        Prov.kolla(zip(rader, rader.dropFirst()).allSatisfy { $0.start <= $1.start }, "raderna kommer i ordning")
        return Prov.sammanfatta()
    }
}

import Foundation
import AVFoundation

extension Tester {
    static func ljud() {
        Prov.svit("Ljud")

        func u32(_ d: Data, _ o: Int) -> UInt32 { d[o..<o+4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } }
        func u16(_ d: Data, _ o: Int) -> UInt16 { d[o..<o+2].withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) } }
        func i16(_ d: Data, _ o: Int) -> Int16 { d[o..<o+2].withUnsafeBytes { $0.loadUnaligned(as: Int16.self) } }

        do {   // WAV-huvud
            let d = Wav.data(av: [Float](repeating: 0.5, count: 16_000))
            Prov.lika(d.count, 44 + 32_000, "WAV får rätt total storlek")
            Prov.lika(String(data: d[0..<4], encoding: .ascii), "RIFF", "filen inleds med RIFF")
            Prov.lika(String(data: d[8..<12], encoding: .ascii), "WAVE", "formatet är WAVE")
            Prov.lika(u16(d, 20), 1, "kodningen är PCM")
            Prov.lika(u16(d, 22), 1, "ljudet är mono")
            Prov.lika(u32(d, 24), 16_000, "frekvensen är 16 kHz, som whisper vill ha")
            Prov.lika(u16(d, 34), 16, "provdjupet är 16 bitar")
            Prov.lika(u32(d, 40), 32_000, "datalängden stämmer")
        }

        do {   // klippning
            let d = Wav.data(av: [2.0, -2.0])
            Prov.lika(i16(d, 44), 32767, "för höga prov klipps i stället för att vika runt")
            Prov.lika(i16(d, 46), -32767, "detsamma åt andra hållet")
        }

        do {   // spårskrivaren
            let fil = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).wav")
            defer { try? FileManager.default.removeItem(at: fil) }
            let s = try! Spårskrivare(fil: fil)
            s.skriv([Float](repeating: 0.1, count: 8_000))
            s.skriv([Float](repeating: 0.1, count: 8_000))
            s.stäng()
            let d = try! Data(contentsOf: fil)
            Prov.lika(u32(d, 40), 32_000, "huvudets datalängd lagas när filen stängs")
            Prov.lika(u32(d, 4), UInt32(36 + 32_000), "RIFF-längden lagas också")
            let ljud = try! AVAudioFile(forReading: fil)
            Prov.lika(ljud.length, 16_000, "filen går att öppna som ljud, inte bara se rätt ut")
            Prov.lika(ljud.fileFormat.sampleRate, 16_000, "med rätt frekvens")
        }

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

        // Testljudet ska likna tal, inte en konstant nivå. Det var just en
        // konstant som förde kalibreringen vilse en gång: en syntetisk fil med
        // tal på RMS 0,2 gav trösklar som slängde allt den inbyggda
        // mikrofonen spelade in, där tal ligger på 0,005–0,016.
        var frö: UInt64 = 12345
        func slump() -> Float {
            frö = frö &* 6364136223846793005 &+ 1442695040888963407
            return Float(Int32(truncatingIfNeeded: frö >> 33)) / Float(Int32.max)
        }
        /// En bit ljud på ungefär `nivå` i RMS ovanpå en bakgrund. Ljudet
        /// pulserar i stavelsetakt, som tal gör: det är i pauserna mellan
        /// orden bakgrunden går att se.
        var stavelse = 0
        func ram(_ nivå: Float, _ sekunder: Double, _ tid: Double,
                 bakgrund: Float = 0.0003) -> Ljudram {
            let antal = AVAudioFrameCount(16_000 * sekunder)
            let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: antal)!
            buf.frameLength = antal
            let period = 16_000 / 45 * 10          // ~4,5 stavelser i sekunden
            for i in 0..<Int(antal) {
                stavelse = (stavelse + 1) % period
                let ljudande = Double(stavelse) < Double(period) * 0.65
                let n = ljudande ? nivå * 1.25 : 0
                buf.floatChannelData![0][i] = slump() * (n * 1.7) + slump() * bakgrund * 1.7
            }
            return Ljudram(röst: .jag, buffert: buf, tid: tid)
        }
        func tystnad(_ sekunder: Double, _ tid: Double) -> Ljudram {
            ram(0, sekunder, tid, bakgrund: 0)
        }

        do {   // tystnad stänger fönstret
            let b = Ljudbuffring()
            Prov.kolla(b.mata(ram(0.05, 1.0, 0)).fönster == nil, "tal håller fönstret öppet")
            Prov.kolla(b.mata(ram(0.05, 1.0, 1)).fönster == nil, "fortsatt tal håller det öppet")
            let f = b.mata(tystnad(0.8, 2)).fönster
            Prov.kolla(f != nil, "tystnad längre än 0,6 s stänger fönstret")
            if let f {
                Prov.lika(f.prov.count, 16_000 * 28 / 10, "fönstret innehåller allt ljud fram till tystnaden")
                Prov.lika(f.start, 0, "fönstret börjar där talet började")
            }
        }

        do {   // maxlängd
            let b = Ljudbuffring()
            var fönster: Ljudbuffring.Fönster?
            for i in 0..<20 where fönster == nil {
                fönster = b.mata(ram(0.05, 1.0, Double(i))).fönster
            }
            Prov.kolla(fönster != nil, "den som talar oavbrutet får ändå text")
            if let f = fönster {
                Prov.lika(f.prov.count, 16_000 * 15, "senast efter 15 sekunder")
            }
        }

        do {   // tysta fönster skickas inte vidare
            let b = Ljudbuffring()
            // Ett helt tyst fönster: whisper skulle hitta på text ur det
            var fönster: Ljudbuffring.Fönster?
            for i in 0..<20 where fönster == nil {
                fönster = b.mata(tystnad(1.0, Double(i))).fönster
            }
            Prov.kolla(fönster == nil, "ett tyst fönster skickas aldrig till whisper")

            // Svagt jämnt brus — nivån är mätt ur kalibreringsfilen — ska
            // inte heller nå fram.
            let c = Ljudbuffring()
            var brusfönster: Ljudbuffring.Fönster?
            for i in 0..<20 where brusfönster == nil {
                brusfönster = c.mata(ram(0, 1.0, Double(i), bakgrund: 0.0017)).fönster
            }
            Prov.kolla(brusfönster == nil, "svagt brus räknas inte som tal")

            // Ett rum som brusar starkt ska inte heller göra bruset till tal.
            let e = Ljudbuffring()
            var rumsfönster: Ljudbuffring.Fönster?
            for i in 0..<30 where rumsfönster == nil {
                rumsfönster = e.mata(ram(0, 1.0, Double(i), bakgrund: 0.02)).fönster
            }
            Prov.kolla(rumsfönster == nil, "ett brusigt rum räknas inte heller som tal")
        }

        do {   // samma tal, olika inspelningsnivåer
            // Det här är felet som fanns: mikrofonspåret låg på RMS 0,006 och
            // en fast tröskel slängde varenda fönster, medan datorljudet på
            // 0,2 gick igenom. Detekteringen ska klara hela spannet.
            for nivå in [Float(0.004), 0.006, 0.02, 0.06, 0.2] {
                let b = Ljudbuffring()
                var f: Ljudbuffring.Fönster?
                for i in 0..<4 where f == nil {
                    f = b.mata(ram(nivå, 1.0, Double(i))).fönster
                }
                if f == nil { f = b.mata(tystnad(0.8, 4)).fönster }
                Prov.kolla(f != nil, "tal på RMS \(nivå) släpps igenom")
            }
        }

        do {   // mätaren
            let b = Ljudbuffring()
            _ = b.mata(ram(0.012, 0.5, 0))
            Prov.kolla(b.senasteNivå > 0.3,
                       "mätaren rör sig på tal från den inbyggda mikrofonen (\(b.senasteNivå))")
            let c = Ljudbuffring()
            _ = c.mata(tystnad(0.5, 0))
            Prov.kolla(c.senasteNivå < 0.1, "men ligger stilla vid tystnad (\(c.senasteNivå))")
        }

        do {   // uppspelning: rätt spår för rätt röst
            let mitt = Yttrande(röst: .jag, text: "x", start: 0, slut: 1)
            let deras = Yttrande(röst: .motpart, text: "x", start: 0, slut: 1)
            Prov.lika(Yttrandespelare.fil(för: mitt, enspårig: false), "jag.wav",
                      "mitt yttrande spelas ur mitt spår")
            Prov.lika(Yttrandespelare.fil(för: deras, enspårig: false), "motpart.wav",
                      "motpartens ur deras")
            Prov.lika(Yttrandespelare.fil(för: mitt, enspårig: true), "motpart.wav",
                      "i en importerad fil ligger allt i motpart.wav")
        }

        do {   // nedräkning
            // Omräknaren har en intern fördröjning och håller tillbaka en bit
            // av första bufferten. Det som spelar roll är att inget försvinner
            // över tid, så mät summan över flera bitar i stället för en enda.
            let b = Ljudbuffring()
            let stereo = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false)!
            var summa = 0
            for s in 0..<5 {
                let buf = AVAudioPCMBuffer(pcmFormat: stereo, frameCapacity: 48_000)!
                buf.frameLength = 48_000
                for k in 0..<2 { for i in 0..<48_000 { buf.floatChannelData![k][i] = 0.2 } }
                let (mono, _) = b.mata(Ljudram(röst: .motpart, buffert: buf, tid: Double(s)))
                summa += mono.count
            }
            // Fem sekunder in ska ge fem sekunder ut, på en bråkdel av en sekund när.
            Prov.kolla(abs(summa - 5 * 16_000) < 1_100,
                       "48 kHz stereo blir 16 kHz mono utan att ljud tappas (\(summa) av 80 000 prov)")
        }
    }
}

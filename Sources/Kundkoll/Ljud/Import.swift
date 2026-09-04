import Foundation
import AVFoundation

/// Tar in en färdig ljud- eller videofil och gör den till en inspelning.
///
/// Teams och Zoom sparar möten som mp4, telefonen som m4a, diktafonen som wav.
/// AVFoundation läser dem alla, så filen behöver bara räknas om till det format
/// whisper vill ha.
///
/// Till skillnad från en inspelning gjord i appen finns ingen kanaluppdelning
/// här — allt ligger i ett spår. Röstanalysen får i stället dela upp det, och
/// då kan en av rösterna vara du själv.
actor Import {

    struct Läge {
        var steg: String
        /// 0–1 när det går att veta, annars nil.
        var andel: Double?
        /// Det senaste transkriberade, så att man ser att det rör sig.
        var senaste: String?
    }

    private let whisper: Whisper
    private let röstanalys: Röstanalys

    init(whisper: Whisper = Whisper(), röstanalys: Röstanalys = Röstanalys()) {
        self.whisper = whisper
        self.röstanalys = röstanalys
    }

    /// Format vi tar emot. Listan är bred med flit: hellre försöka och
    /// misslyckas tydligt än att stänga ute en fil som hade fungerat.
    static let format = ["wav", "mp3", "m4a", "aac", "aif", "aiff", "caf", "flac",
                         "mp4", "mov", "m4v", "mpeg", "mpg", "wma", "ogg", "opus", "webm"]

    /// Läser filen och skriver 16 kHz mono, formatet whisper och röstanalysen
    /// båda vill ha.
    static func tillWhisperformat(_ källa: URL, mål: URL) async throws -> Double {
        let tillgång = AVURLAsset(url: källa)
        let spår = try await tillgång.loadTracks(withMediaType: .audio)
        guard let ljudspår = spår.first else { throw Fel.ingetLjud }

        let läsare = try AVAssetReader(asset: tillgång)
        let inställningar: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Ljudbuffring.målfrekvens,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let utgång = AVAssetReaderTrackOutput(track: ljudspår, outputSettings: inställningar)
        guard läsare.canAdd(utgång) else { throw Fel.kanInteLäsa }
        läsare.add(utgång)
        guard läsare.startReading() else { throw Fel.kanInteLäsa }

        let skrivare = try Spårskrivare(fil: mål)
        var antal = 0
        while let buffert = utgång.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffert) else { continue }
            var längd = 0
            var pekare: UnsafeMutablePointer<CChar>?
            guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil,
                                              totalLengthOut: &längd,
                                              dataPointerOut: &pekare) == noErr,
                  let pekare else { continue }
            let prov = pekare.withMemoryRebound(to: Float.self, capacity: längd / 4) {
                Array(UnsafeBufferPointer(start: $0, count: längd / 4))
            }
            skrivare.skriv(prov)
            antal += prov.count
            CMSampleBufferInvalidate(buffert)
        }
        skrivare.stäng()

        if läsare.status == .failed { throw läsare.error ?? Fel.kanInteLäsa }
        guard antal > 0 else { throw Fel.tomtLjud }
        return Double(antal) / Ljudbuffring.målfrekvens
    }

    /// Hela vägen: fil in, färdig inspelning ut.
    func importera(_ källa: URL,
                   placering: Placering,
                   titel: String,
                   kund: Kund?,
                   profiler: [Röstprofil],
                   väntadeRöster: Int? = nil,
                   språk: String? = "sv",
                   inledd angivet: Date? = nil,
                   vidLäge: @Sendable @escaping (Läge) -> Void) async throws -> (Inspelning, URL) {

        await MainActor.run { vidLäge(Läge(steg: "Läser \(källa.lastPathComponent) …", andel: nil)) }

        // Mötesdagen anges i importbladet; annars filens egen tid, som är
        // närmare sanningen än «nu» för ett möte som spelats in tidigare.
        let inledd = angivet
            ?? (try? källa.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? Date()

        let mapp = try await MainActor.run {
            try Arkivet.shared.nyInspelningsmapp(placering: placering, titel: titel, datum: inledd)
        }
        // En avbruten import lämnade tidigare ljudfilen kvar utan möte.json.
        // Mappen syntes inte i appen, gick inte att radera där, och låg kvar i
        // Finder — i ett fall 72 MB.
        var lyckades = false
        defer {
            if !lyckades { try? FileManager.default.removeItem(at: mapp) }
        }

        let wav = mapp.appending(path: "motpart.wav")
        let längd = try await Self.tillWhisperformat(källa, mål: wav)

        await MainActor.run {
            vidLäge(Läge(steg: "Transkriberar \(formateraLängd(längd)) med KB-Whisper", andel: 0))
        }
        let rader = try await Arkivtranskribering.kör(
            fil: wav, röst: .motpart, språk: språk, totalLängd: längd,
            vidFramsteg: { f in
                vidLäge(Läge(steg: "Transkriberar \(formateraLängd(längd))",
                             andel: f.andel, senaste: f.senasteRad))
            })
        guard !rader.isEmpty else { throw Fel.ingetTal }

        let uppdelning = await röstanalys.delaUpp(
            fil: wav, yttranden: rader, antal: väntadeRöster, profiler: profiler,
            vidLäge: { steg in vidLäge(Läge(steg: steg, andel: nil)) })
        let märkta = uppdelning.yttranden
        let namn = uppdelning.namn

        await MainActor.run { vidLäge(Läge(steg: "Sammanfattar mötet", andel: nil)) }
        var inspelning = Inspelning(
            titel: titel, inledd: inledd, längd: längd,
            kund: placering.kundnamn,
            projekt: { if case .projekt(let p) = placering { p.namn } else { nil } }(),
            mikrofon: nil,
            liveYttranden: [],
            arkivYttranden: märkta,
            röstnamn: namn,
            kallade: [],
            enspårig: true,
            källfil: källa.lastPathComponent,
            språk: språk)

        inspelning.sammanfattning = try? await Sammanfattare()
            .skriv(för: inspelning, kund: placering.kundnamn, automatiskt: true)
        let klar = inspelning
        try await MainActor.run {
            try Arkivet.shared.spara(klar, i: mapp)
            // En importerad inspelning ska ge uppgifter på tavlan precis som
            // ett möte som spelats in i appen.
            if let s = klar.sammanfattning {
                Uppgiftssamling.frånMöte(s, inspelning: klar, mapp: mapp)
            }
            Notiser.mötetKlart(klar, mapp: mapp)
        }
        lyckades = true
        return (inspelning, mapp)
    }

    /// Gör klart en inspelning vars ljud finns men vars metadata saknas.
    ///
    /// Ljudet är redan i rätt format, så bara transkribering och röstuppdelning
    /// återstår.
    func slutför(mapp: URL,
                 placering: Placering,
                 profiler: [Röstprofil],
                 titel angiven: String? = nil,
                 språk: String? = "sv",
                 vidLäge: @Sendable @escaping (Läge) -> Void) async throws -> Inspelning {
        let wav = mapp.appending(path: "motpart.wav")
        guard FileManager.default.fileExists(atPath: wav.path) else { throw Fel.ingetLjud }

        let ljud = try AVAudioFile(forReading: wav)
        let längd = Double(ljud.length) / ljud.processingFormat.sampleRate
        // «Transkribera om» bytte förut mötets datum till ljudfilens: ett
        // vårmöte blev ett septembermöte. Finns en möte.json gäller dess datum.
        let tidigare = await MainActor.run { Arkivet.shared.inspelning(i: mapp) }
        let inledd = tidigare?.inledd
            ?? (try? wav.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? Date()

        await MainActor.run {
            vidLäge(Läge(steg: "Transkriberar \(formateraLängd(längd))", andel: 0))
        }
        let rader = try await Arkivtranskribering.kör(
            fil: wav, röst: .motpart, språk: språk, totalLängd: längd,
            vidFramsteg: { f in
                vidLäge(Läge(steg: "Transkriberar \(formateraLängd(längd))",
                             andel: f.andel, senaste: f.senasteRad))
            })
        guard !rader.isEmpty else { throw Fel.ingetTal }

        let uppdelning = await röstanalys.delaUpp(
            fil: wav, yttranden: rader, antal: nil, profiler: profiler,
            vidLäge: { steg in vidLäge(Läge(steg: steg, andel: nil)) })

        // Titeln står i mappnamnet: "2026-08-31 1548 magnus 1on1".
        let namn = mapp.lastPathComponent
        let urMapp = namn.split(separator: " ").dropFirst(2).joined(separator: " ")
        let titel = angiven ?? (urMapp.isEmpty ? namn : urMapp)

        await MainActor.run { vidLäge(Läge(steg: "Sammanfattar mötet", andel: nil)) }
        var inspelning = Inspelning(
            titel: titel,
            inledd: inledd, längd: längd,
            kund: placering.kundnamn,
            projekt: { if case .projekt(let p) = placering { p.namn } else { nil } }(),
            mikrofon: tidigare?.mikrofon,
            liveYttranden: tidigare?.liveYttranden ?? [],
            arkivYttranden: uppdelning.yttranden,
            röstnamn: uppdelning.namn,
            kallade: tidigare?.kallade ?? [],
            enspårig: tidigare?.enspårig ?? true,
            källfil: tidigare?.källfil,
            språk: språk)

        inspelning.sammanfattning = try? await Sammanfattare()
            .skriv(för: inspelning, kund: placering.kundnamn, automatiskt: true)
        let klar = inspelning
        try await MainActor.run {
            try Arkivet.shared.spara(klar, i: mapp)
            if let s = klar.sammanfattning {
                Uppgiftssamling.frånMöte(s, inspelning: klar, mapp: mapp)
            }
            Notiser.mötetKlart(klar, mapp: mapp)
        }
        return inspelning
    }

    enum Fel: LocalizedError {
        case ingetLjud, kanInteLäsa, tomtLjud, ingetTal
        var errorDescription: String? {
            switch self {
            case .ingetLjud: "Filen innehåller inget ljudspår."
            case .kanInteLäsa: "Filformatet gick inte att läsa."
            case .tomtLjud: "Ljudspåret är tomt."
            case .ingetTal: "Hittade inget tal i inspelningen."
            }
        }
    }
}

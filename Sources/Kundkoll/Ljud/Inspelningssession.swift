import Foundation
import AVFoundation
import SwiftUI

/// Håller ihop en pågående inspelning: ljudet in, spåren till disk,
/// fönstren till whisper och raderna ut till gränssnittet.
@MainActor
final class Inspelningssession: ObservableObject {

    /// En och samma session i hela appen: inspelningsfönstret och raden i
    /// huvudfönstret visar samma tillstånd.
    static let delad = Inspelningssession()

    enum Läge: Equatable {
        case vilande
        case förbereder(String)
        case spelarIn
        case avslutar
        case klar(URL)
        case fel(String)
    }

    @Published private(set) var läge: Läge = .vilande
    @Published private(set) var yttranden: [Yttrande] = []
    @Published private(set) var förfluten: Double = 0
    @Published private(set) var nivåJag: Float = 0
    @Published private(set) var nivåMotpart: Float = 0
    /// Sätts när efterbearbetningen med den stora modellen är igång.
    @Published private(set) var efterbearbetar = false
    /// Sätts medan motpartsspåret delas upp i röster.
    @Published private(set) var analyserarRöster = false
    /// Sätts medan mötet sammanfattas.
    @Published private(set) var sammanfattar = false
    /// Hur långt efterbearbetningen kommit, 0–1.
    @Published private(set) var efterbearbetningsandel: Double = 0
    /// Det senast transkriberade, så att man ser att det rör sig.
    @Published private(set) var senasteArkivrad = ""
    /// Mappen vars inspelning just nu efterbearbetas, så att raden i listan
    /// kan visa var arbetet står.
    @Published private(set) var bearbetadMapp: URL?
    @Published private(set) var röstnamn: [Int: String] = [:]
    /// Något gick fel under inspelningen utan att den gick förlorad, till
    /// exempel att ljudinfångningen bröts. Visas på sidan «sparad».
    @Published private(set) var varning: String?
    /// Återinträdesspärr: två klick på stopp ska ge en avslutning, inte två
    /// efterbearbetningar i samma mapp.
    private var stoppar = false

    /// Lyssnar efter frågeställningar medan samtalet pågår.
    let liveinsikter = Liveinsikter()

    private let infångning = Ljudinfångning()
    private let whisper = Whisper.delad
    private let röstanalys = Röstanalys()
    private var buffring: [Röst: Ljudbuffring] = [.jag: Ljudbuffring(), .motpart: Ljudbuffring()]
    private var skrivare: [Röst: Spårskrivare] = [:]

    private var mapp: URL?
    /// Vad inspelningen heter, synligt för raden i huvudfönstret.
    @Published private(set) var titel = ""
    private var placering: Placering?
    private var mikrofonNamn: String?
    private var kallade: [String] = []
    /// Mötets språk: "sv" eller "en". Livefönstren och arkivpasset följer det.
    private var språk = "sv"
    private var start = Date()
    private var klocka: Timer?
    /// En transkribering i taget per spår, annars hamnar raderna i oordning.
    private var köer: [Röst: Task<Void, Never>] = [:]

    var pågår: Bool { if case .spelarIn = läge { true } else { false } }
    /// Sant medan något skulle gå förlorat om appen avslutades.
    var arbetar: Bool { pågår || läge == .avslutar || efterbearbetar }

    // MARK: - Start

    func starta(placering: Placering, titel: String,
                mikrofon: Ljudinfångning.Mikrofon?, kallade: [String] = [],
                språk: String = "sv") async {
        // Från .fel går det att försöka igen: ett nekat tillstånd ska inte
        // kräva omstart av appen.
        switch läge {
        case .vilande, .fel: break
        default: return
        }
        varning = nil
        self.placering = placering
        self.titel = titel.isEmpty ? "Samtal" : titel
        self.mikrofonNamn = mikrofon?.namn
        self.kallade = kallade
        self.språk = språk
        yttranden = []
        förfluten = 0

        do {
            läge = .förbereder("Kontrollerar behörigheter …")
            guard await Ljudinfångning.begärMikrofon() else {
                throw Enkeltfel("Mikrofonen är inte tillåten. Slå på Critero-kundkoll under Systeminställningar → Mikrofon och försök igen.")
            }
            if !Ljudinfångning.harSkärmbehörighet() {
                // Dialogen skriver in appen i listan; själva godkännandet
                // sker i Systeminställningar och gäller efter omstart.
                Ljudinfångning.begärSkärmbehörighet()
                throw Enkeltfel("Datorljudet kräver Skärminspelning. Slå på Critero-kundkoll under Systeminställningar → Skärminspelning, starta om appen och försök igen.")
            }

            Notiser.begär()
            läge = .förbereder("Laddar KB-Whisper …")
            try await whisper.startaServer()

            läge = .förbereder("Skapar mapp …")
            start = Date()
            let m = try Arkivet.shared.nyInspelningsmapp(placering: placering, titel: self.titel, datum: start)
            mapp = m
            skrivare = [
                .jag: try Spårskrivare(fil: m.appending(path: "jag.wav")),
                .motpart: try Spårskrivare(fil: m.appending(path: "motpart.wav")),
            ]

            infångning.vidRam = { [weak self] ram in self?.tog(ram) }
            infångning.vidFel = { [weak self] fel in self?.avbröt(fel) }
            try await infångning.starta(mikrofonID: mikrofon?.id)

            läge = .spelarIn
            if case .kund(let k) = placering {
                liveinsikter.börja(kund: k, projekt: nil)
            } else if case .projekt(let p) = placering,
                      let k = Arkivet.shared.kunder.first(where: { $0.namn == p.kundnamn }) {
                liveinsikter.börja(kund: k, projekt: p)
            }
            klocka = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let s = self, s.pågår else { return }
                    s.förfluten = Date().timeIntervalSince(s.start)
                }
            }
        } catch {
            await städa()
            läge = .fel(error.localizedDescription)
        }
    }

    // MARK: - Under inspelning

    private func tog(_ ram: Ljudram) {
        guard pågår, let b = buffring[ram.röst] else { return }
        let (mono, fönster) = b.mata(ram)
        if !mono.isEmpty { skrivare[ram.röst]?.skriv(mono) }

        switch ram.röst {
        case .jag: nivåJag = b.senasteNivå
        case .motpart: nivåMotpart = b.senasteNivå
        }

        guard let f = fönster else { return }
        köa(f, röst: ram.röst)
    }

    private func köa(_ f: Ljudbuffring.Fönster, röst: Röst) {
        let tidigare = köer[röst]
        köer[röst] = Task { [weak self] in
            await tidigare?.value
            guard let self else { return }
            guard let text = try? await self.whisper.transkribera(prov: f.prov, språk: self.språk),
                  !text.isEmpty else { return }
            await MainActor.run {
                let y = Yttrande(röst: röst, text: text, start: f.start, slut: f.slut)
                self.yttranden.append(y)
                self.yttranden.sort { $0.start < $1.start }
                self.liveinsikter.tog(y)
            }
        }
    }

    private func avbröt(_ fel: Error) {
        Task {
            // Det som hann spelas in är sparat och bearbetas; felet är en
            // varning på sidan «sparad», inte ett tomt formulär.
            if await stoppa() != nil {
                varning = "Ljudet bröts: \(fel.localizedDescription) Det som hann spelas in är sparat och bearbetas."
            } else if case .klar = läge {
            } else if läge != .avslutar {
                läge = .fel(fel.localizedDescription)
            }
        }
    }

    // MARK: - Stopp

    @discardableResult
    func stoppa() async -> URL? {
        guard pågår, !stoppar else { return nil }
        stoppar = true
        defer { stoppar = false }
        läge = .avslutar
        liveinsikter.sluta()
        klocka?.invalidate(); klocka = nil
        let slut = Date().timeIntervalSince(start)

        await infångning.stoppa()

        // Ta hand om det som ligger kvar i buffertarna.
        for (röst, b) in buffring {
            if let f = b.spola() { köa(f, röst: röst) }
        }
        for (_, t) in köer { await t.value }
        köer.removeAll()

        for (_, s) in skrivare { s.stäng() }
        skrivare.removeAll()
        await whisper.stoppaServer()

        guard let mapp, let placering else { läge = .vilande; return nil }
        var inspelning = Inspelning(
            titel: titel,
            inledd: start,
            längd: slut,
            kund: placering.kundnamn,
            projekt: { if case .projekt(let p) = placering { p.namn } else { nil } }(),
            mikrofon: mikrofonNamn,
            liveYttranden: yttranden,
            arkivYttranden: nil,
            kallade: kallade,
            språk: språk
        )
        try? Arkivet.shared.spara(inspelning, i: mapp)
        läge = .klar(mapp)

        // Den stora modellen får gå i bakgrunden; live-transkriptet finns redan sparat.
        efterbearbeta(&inspelning, mapp: mapp)
        return mapp
    }

    /// Kör KB-Whisper medium på båda spåren, delar upp motparten i röster och
    /// ersätter live-raderna. Går i bakgrunden; live-transkriptet är redan sparat.
    private func efterbearbeta(_ inspelning: inout Inspelning, mapp: URL) {
        let i = inspelning
        let kund = Arkivet.shared.kunder.first { $0.namn == i.kund }
        efterbearbetar = true
        bearbetadMapp = mapp
        let jobb = kund.flatMap { Arbeten.delad.starta(.efterbearbetning, kund: $0, titel: i.titel) }
        Task { [weak self] in
            guard let self else { return }
            var rader: [Yttrande] = []
            var transkriptfel: String?
            let spår = [(Röst.jag, "jag.wav"), (Röst.motpart, "motpart.wav")]
            for (n, (röst, fil)) in spår.enumerated() {
                let url = mapp.appending(path: fil)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                // Två spår, så varje spår är halva arbetet.
                let bas = Double(n) / Double(spår.count)
                do {
                    rader += try await Arkivtranskribering.kör(
                        fil: url, röst: röst, språk: i.språk ?? "sv", totalLängd: i.längd,
                        vidFramsteg: { f in
                            jobb?.steg("skriver rent", andel: bas + f.andel / Double(spår.count))
                            Task { @MainActor in
                                self.efterbearbetningsandel = bas + f.andel / Double(spår.count)
                                if !f.senasteRad.isEmpty { self.senasteArkivrad = f.senasteRad }
                            }
                        })
                } catch {
                    // Felet fångades förut med try? och mötet stod kvar som
                    // «live» utan ett ord. Nu står orsaken i kvittot och notisen.
                    transkriptfel = error.localizedDescription
                }
            }
            guard !rader.isEmpty else {
                let orsak = transkriptfel ?? "renskrivningen hittade inget tal"
                Logg.fel("Efterbearbetning av «\(i.titel)»: \(orsak)", i: "Inspelningssession")
                await MainActor.run {
                    self.efterbearbetar = false
                    self.bearbetadMapp = nil
                    self.varning = "Renskrivningen misslyckades: \(orsak) Livetranskriptet är sparat."
                    jobb?.föll(orsak)
                    Notiser.skicka(titel: i.titel, text: "Renskrivningen misslyckades: \(orsak)",
                                   kund: i.kund, mapp: mapp)
                }
                return
            }
            rader.sort { $0.start < $1.start }

            var uppdaterad = i
            uppdaterad.arkivYttranden = rader
            await MainActor.run {
                try? Arkivet.shared.spara(uppdaterad, i: mapp)
                self.yttranden = rader
                self.analyserarRöster = true
            }

            let (märkta, namn) = await self.delaUppRöster(
                rader, motpartsfil: mapp.appending(path: "motpart.wav"), kund: kund)
            uppdaterad.arkivYttranden = märkta
            uppdaterad.röstnamn = namn
            await MainActor.run {
                try? Arkivet.shared.spara(uppdaterad, i: mapp)
                self.yttranden = märkta
                self.röstnamn = namn
                self.analyserarRöster = false
                self.sammanfattar = true
            }

            // Det man vill ha ur ett möte är sällan transkriptet utan vad det
            // landade i. Sammanfattningen skrivs sist, när talarna är kända.
            var sammanfattningsfel: String?
            do {
                let s = try await Sammanfattare().skriv(för: uppdaterad, kund: uppdaterad.kund,
                                                        automatiskt: true)
                uppdaterad.sammanfattning = s
                let inspelning = uppdaterad
                await MainActor.run {
                    try? Arkivet.shared.spara(inspelning, i: mapp)
                    // Mötets åtaganden hamnar på tavlan. De är redan
                    // utplockade av sammanfattningen, så ingen extra runda
                    // behövs här.
                    Uppgiftssamling.frånMöte(s, inspelning: inspelning, mapp: mapp)
                }
            } catch {
                sammanfattningsfel = error.localizedDescription
                Logg.fel("Sammanfattning av «\(i.titel)»: \(error.localizedDescription)", i: "Inspelningssession")
            }
            let klar = uppdaterad
            let fel = sammanfattningsfel
            await MainActor.run {
                self.sammanfattar = false
                self.efterbearbetar = false
                self.bearbetadMapp = nil
                if let fel {
                    self.varning = "Transkriptet är klart, men sammanfattningen misslyckades: \(fel)"
                    jobb?.föll("sammanfattningen misslyckades: \(fel)")
                    Notiser.skicka(titel: klar.titel,
                                   text: "Transkriptet är klart, men sammanfattningen misslyckades: \(fel)",
                                   kund: klar.kund, mapp: mapp)
                } else {
                    let antal = klar.sammanfattning?.åtaganden.count ?? 0
                    jobb?.klart("Sammanfattad, \(antal) åtaganden", modell: klar.sammanfattning?.modell)
                    Notiser.mötetKlart(klar, mapp: mapp)
                }
            }
        }
    }

    /// Delar motpartsspåret i röster och sätter namn på dem som känns igen.
    private func delaUppRöster(_ rader: [Yttrande],
                               motpartsfil: URL,
                               kund: Kund?) async -> ([Yttrande], [Int: String]) {
        let profiler = kund.map { k in
            MainActor.assumeIsolated { Arkivet.shared.röstprofiler(för: k) }
        } ?? []
        // Kalendern vet ofta hur många som talar: de kallade minus jag själv.
        let uppdelning = await röstanalys.delaUpp(
            fil: motpartsfil, yttranden: rader,
            antal: kallade.isEmpty ? nil : kallade.count,
            profiler: profiler)
        return (uppdelning.yttranden, uppdelning.namn)
    }

    func återställ() { if case .spelarIn = läge {} else { läge = .vilande; yttranden = [] } }

    private func städa() async {
        klocka?.invalidate(); klocka = nil
        await infångning.stoppa()
        for (_, s) in skrivare { s.stäng() }
        skrivare.removeAll()
        await whisper.stoppaServer()
        // En mapp utan ljud efter ett misslyckat startförsök ska inte ligga
        // kvar som «påbörjad inspelning, 0 MB» med en knapp som inte kan lyckas.
        if let m = mapp, Self.saknarLjud(m) {
            try? FileManager.default.removeItem(at: m)
        }
        mapp = nil
    }

    /// Sant när ingen av spårfilerna innehåller mer än WAV-huvudet.
    static func saknarLjud(_ mapp: URL) -> Bool {
        for namn in ["jag.wav", "motpart.wav"] {
            let f = mapp.appending(path: namn)
            if let n = try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize, n > 44 { return false }
        }
        return true
    }
}

/// Skriver ett spår till en 16 kHz mono-WAV medan inspelningen pågår.
/// Samma format som både whisper och röstanalysen vill ha.
final class Spårskrivare {
    private let handtag: FileHandle
    private let url: URL
    private var antalProv = 0
    /// Prov sedan huvudet senast skrevs om.
    private var sedanHuvud = 0
    /// Huvudet skrivs om var tionde sekund ljud. Kraschar appen mitt i
    /// mötet påstår filen då högst tio sekunder för lite, i stället för noll.
    static let huvudintervall = 16_000 * 10

    init(fil: URL) throws {
        FileManager.default.createFile(atPath: fil.path, contents: Wav.data(av: []))
        handtag = try FileHandle(forWritingTo: fil)
        url = fil
        handtag.seekToEndOfFile()
    }

    func skriv(_ prov: [Float]) {
        var d = Data(capacity: prov.count * 2)
        for p in prov {
            let v = Int16(max(-1, min(1, p)) * 32767)
            withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) }
        }
        handtag.write(d)
        antalProv += prov.count
        sedanHuvud += prov.count
        if sedanHuvud >= Self.huvudintervall {
            uppdateraHuvud()
            sedanHuvud = 0
        }
    }

    /// WAV-huvudet innehåller längder; de skrivs om löpande och slutgiltigt här.
    func stäng() {
        uppdateraHuvud()
        try? handtag.close()
    }

    private func uppdateraHuvud() {
        let dataBytes = UInt32(antalProv * 2)
        skrivUInt32(dataBytes + 36, vid: 4)      // RIFF-chunkens längd
        skrivUInt32(dataBytes, vid: 40)          // data-chunkens längd
    }

    private func skrivUInt32(_ v: UInt32, vid offset: UInt64) {
        try? handtag.seek(toOffset: offset)
        var le = v.littleEndian
        handtag.write(Data(bytes: &le, count: 4))
        handtag.seekToEndOfFile()
    }
}

struct Enkeltfel: LocalizedError {
    let text: String
    init(_ t: String) { text = t }
    var errorDescription: String? { text }
}

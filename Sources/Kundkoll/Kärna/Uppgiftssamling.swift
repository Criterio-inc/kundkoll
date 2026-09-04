import Foundation

/// Samlar in uppgifter från det material som kommer in.
///
/// Möten bidrar med sina åtaganden direkt, eftersom sammanfattningen redan
/// plockat ut dem. Mejl och anteckningar går genom en egen runda, och vad
/// som redan gåtts igenom bokförs per kund så att inget körs två gånger.
@MainActor
enum Uppgiftssamling {

    /// Mötets åtaganden till tavlan.
    static func frånMöte(_ sammanfattning: Mötessammanfattning,
                         inspelning: Inspelning, mapp: URL?) {
        guard let kund = Arkivet.shared.kunder.first(where: { $0.namn == inspelning.kund })
        else { return }
        let nya = sammanfattning.åtaganden.map {
            Uppgift(vad: $0.vad, vem: $0.vem, när: $0.när, senast: $0.senast,
                    läge: $0.klart ? .klart : .attGöra,
                    ursprung: .möte,
                    källa: mapp?.path,
                    källtitel: inspelning.titel,
                    projekt: inspelning.projekt,
                    skapad: inspelning.inledd)
        }
        // Skrivs sammanfattningen om byts mötets orörda kort ut, annars
        // låg gamla och nya formuleringar av samma löfte bredvid varandra.
        if let källa = mapp?.path {
            _ = try? Arkivet.shared.ersätt(kort: nya, ur: källa, för: kund)
        } else {
            _ = try? Arkivet.shared.läggTill(nya, för: kund)
        }
    }

    /// Om en uppgift kom ur ett visst möte. Mappen är det säkra kännetecknet;
    /// titeln finns kvar för uppgifter som lades upp innan mappen sparades.
    static func hör(_ uppgift: Uppgift, till mapp: URL, titel: String) -> Bool {
        guard uppgift.ursprung == .möte else { return false }
        if let källa = uppgift.källa { return källa == mapp.path }
        return uppgift.källtitel == titel
    }

    // MARK: - Vad som redan gåtts igenom

    /// Vilka mejl och anteckningar modellen redan har letat i, per kund.
    /// Ligger i kundmappen så att det följer med om mappen flyttas.
    struct Rundor: Codable, Equatable {
        /// Mejlens id.
        var mejl: Set<String> = []
        /// Anteckningens fil → avtryck av texten när den gicks igenom.
        var anteckningar: [String: String] = [:]
    }

    static func rundor(_ kund: Kund) -> Rundor {
        guard let data = try? Data(contentsOf: rundfil(kund)),
              let r = try? JSONDecoder.kundkoll.decode(Rundor.self, from: data) else { return Rundor() }
        return r
    }

    static func spara(_ rundor: Rundor, _ kund: Kund) {
        let fil = rundfil(kund)
        try? FileManager.default.createDirectory(at: fil.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let data = try? JSONEncoder.kundkoll.encode(rundor) {
            try? data.write(to: fil, options: .atomic)
        }
    }

    private static func rundfil(_ kund: Kund) -> URL {
        kund.mapp.appending(path: ".kundkoll/uppgiftsrundor.json")
    }

    // MARK: - Mejl

    /// De mejl som ska gås igenom: sådana med text som inte redan gåtts
    /// igenom. Med `tak` tas de nyaste och bara de som kommit efter `sedan`;
    /// utan tak tas alla, äldst först, så att tavlan fylls i tidsordning.
    static func attGåIgenom(_ mejl: [Mailen.Mejl], redan: Set<String>,
                            tak: Int?, sedan: Date?) -> [Mailen.Mejl] {
        var ut = mejl
            .filter { !$0.text.isEmpty && !redan.contains($0.id) }
        if let sedan { ut = ut.filter { ($0.datum ?? .distantPast) > sedan } }
        ut.sort { ($0.datum ?? .distantPast) > ($1.datum ?? .distantPast) }
        if let tak { return Array(ut.prefix(tak)) }
        return ut.reversed()
    }

    /// Letar åtaganden i mejl som inte gåtts igenom förut.
    ///
    /// Utan `alla`: bara de tio nyaste från den senaste månaden, för varje
    /// mejl kostar ett modellanrop. Med `alla`: allt som ligger sparat,
    /// äldst först — det är den retroaktiva genomgången. Ett mejl räknas som
    /// genomgånget bara om modellen svarade; nådde vi ingen modell provas det
    /// igen nästa gång.
    ///
    /// Vad en runda gav: nya kort, hur många mejl som gicks igenom, och
    /// felet som stoppade den, om något. Ett fel avbryter: når vi inte
    /// modellen för ett mejl når vi den inte för nästa heller, och ett tyst
    /// «inga nya» efter åttiofem misslyckade anrop är värre än ett fel.
    struct Utfall {
        var nya = 0
        var genomgångna = 0
        var fel: String?
        /// Modellen som gjorde jobbet, för beskedet och kvittot.
        var modell = ""
        /// Åtaganden ur gamla mejl vars datum passerat med marginal. De
        /// läggs i Klart direkt: de är historia, inte försenade.
        var historiska = 0
        /// Mejl där modellen svarade med text i stället för lista. De
        /// bokförs inte och provas igen nästa gång.
        var hoppade = 0
    }

    /// Äldre än så här är ett passerat datum historia, inte en försening.
    static let historiskGräns: TimeInterval = 14 * 86400

    /// `val` styr vilken modell som används. Utan val tas appens: automatiken
    /// (inte `alla`) tvingas då till datorn av `Chatt`, och en retroaktiv
    /// runda får gå dit Pär pekat, till exempel «Kör via Anthropic».
    @discardableResult
    static func frånMejl(_ mejl: [Mailen.Mejl], kund: Kund, alla: Bool = false,
                         val: Modellval? = nil,
                         framsteg: ((Int, Int) -> Void)? = nil) async -> Utfall {
        var rundor = rundor(kund)
        var utfall = Utfall()
        let att = attGåIgenom(mejl, redan: rundor.mejl,
                              tak: alla ? nil : 10,
                              sedan: alla ? nil : Date().addingTimeInterval(-30 * 24 * 3600))
        guard !att.isEmpty else { return utfall }

        let letare = Uppgiftsletare(chatt: val.map { Chatt(val: $0) } ?? Chatt())
        utfall.modell = letare.etikett
        for (i, m) in att.enumerated() {
            framsteg?(i + 1, att.count)
            let text = "Ämne: \(m.ämne)\nFrån: \(m.avsändarnamn)\n\n\(m.text)"
            let u: [Uppgift]
            do {
                u = try await letare.leta(
                    i: text,
                    sammanhang: m.skickat ? "ett mejl jag skickat" : "ett mejl jag fått",
                    kund: kund.namn,
                    datum: m.datum ?? Date(),
                    automatiskt: !alla)
            } catch Uppgiftsletare.Fel.otolkbart {
                // Ett enstaka svar utan JSON är inte skäl att stanna hela
                // rundan; når vi ingen modell alls är det däremot det.
                utfall.hoppade += 1
                continue
            } catch {
                utfall.fel = error.localizedDescription
                return utfall
            }
            utfall.genomgångna += 1
            var uppgifter = u.map {
                Uppgift(vad: $0.vad, vem: $0.vem, när: $0.när, senast: $0.senast,
                        ursprung: .mejl, källtitel: m.ämne, skapad: m.datum ?? Date())
            }
            if alla {
                let gamla = uppgifter.filter { ($0.senast ?? .distantFuture) < Date().addingTimeInterval(-Self.historiskGräns) }
                uppgifter.removeAll { gamla.map(\.id).contains($0.id) }
                try? Arkivet.shared.läggTillKlara(gamla, för: kund)
                utfall.historiska += gamla.count
            }
            let före = Arkivet.shared.uppgifter(för: kund).count
            let efter = (try? Arkivet.shared.läggTill(uppgifter, för: kund))?.count ?? före
            utfall.nya += efter - före
            rundor.mejl.insert(m.id)
            // Sparas efter varje mejl: en lång runda som avbryts ska inte
            // börja om från början.
            spara(rundor, kund)
        }
        return utfall
    }

    // MARK: - Anteckningar

    /// «…/Projekt/<namn>/Anteckningar/x.md» → «<namn>»; annars nil.
    static func projektnamn(ur fil: URL) -> String? {
        let delar = fil.pathComponents
        guard let i = delar.lastIndex(of: "Projekt"), i + 1 < delar.count else { return nil }
        return delar[i + 1]
    }

    /// Ett avtryck av texten, så att samma anteckning inte går genom
    /// modellen två gånger utan att ha ändrats. Stabilt mellan körningar,
    /// till skillnad från `hashValue`.
    static func avtryck(_ text: String) -> String {
        var h: UInt64 = 14_695_981_039_346_656_037
        for b in text.utf8 { h = (h ^ UInt64(b)) &* 1_099_511_628_211 }
        return String(h, radix: 16)
    }

    /// Letar åtaganden i en anteckning, om den ändrats sedan sist.
    /// Anropas när man slutat skriva och när anteckningen stängs.
    /// Utfall: `genomgångna` är 0 när texten var oförändrad eller för kort,
    /// annars 1. `fel` när modellen inte svarade; då bokförs inget, så
    /// anteckningen provas igen nästa gång.
    @discardableResult
    static func frånAnteckning(_ anteckning: Anteckning, kund: Kund) async -> Utfall {
        var utfall = Utfall()
        let text = anteckning.text
        guard text.count > 60 else { return utfall }
        var rundor = rundor(kund)
        let avtryck = avtryck(text)
        guard rundor.anteckningar[anteckning.fil.path] != avtryck else { return utfall }

        let letare = Uppgiftsletare()
        utfall.modell = letare.etikett
        let u: [Uppgift]
        do {
            u = try await letare.leta(
                i: text, sammanhang: "en anteckning jag skrivit",
                kund: kund.namn, datum: anteckning.ändrad, automatiskt: true)
        } catch {
            utfall.fel = error.localizedDescription
            return utfall
        }
        utfall.genomgångna = 1
        // En anteckning i ett projekts mapp hör till projektet, och då ska
        // kortet också göra det.
        let projekt = Self.projektnamn(ur: anteckning.fil)
        let uppgifter = u.map {
            Uppgift(vad: $0.vad, vem: $0.vem, när: $0.när, senast: $0.senast,
                    ursprung: .anteckning, källa: anteckning.fil.path,
                    källtitel: anteckning.titel, projekt: projekt, skapad: anteckning.ändrad)
        }
        let före = Arkivet.shared.uppgifter(för: kund).count
        let efter = (try? Arkivet.shared.läggTill(uppgifter, för: kund))?.count ?? före
        rundor.anteckningar[anteckning.fil.path] = avtryck
        spara(rundor, kund)
        utfall.nya = efter - före
        return utfall
    }
}

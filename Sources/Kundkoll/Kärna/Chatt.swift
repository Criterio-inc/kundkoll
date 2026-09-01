import Foundation

/// Frågor och svar om en kund, med kundens eget material som underlag.
///
/// Modellen nås via OpenRouter, som Anders redan har nyckel till. Bara det som
/// sökningen plockat fram skickas — inte hela kundmappen — och bara när han
/// själv ställer en fråga. Under pågående samtal används den lokala modellen.
actor Chatt {

    /// En källa svaret byggde på.
    struct Hänvisning: Codable, Hashable, Identifiable {
        var id: String { "\(nummer)-\(titel)" }
        var nummer: Int
        var titel: String
        var typ: String
        /// Filen den kommer ur, så att den går att öppna.
        var källa: String
        var datum: Date?

        var beskrivning: String {
            datum.map { "\(titel) · \(DateFormatter.dag.string(from: $0))" } ?? titel
        }

        var ikon: String {
            switch typ {
            case "transkript": "waveform"
            case "anteckning": "note.text"
            case "mejl": "envelope"
            case "bilaga": "paperclip"
            case "chatt": "bubble.left.and.text.bubble.right"
            case "fil": "folder"
            case "sammanfattning": "list.bullet.rectangle"
            case "kontakt": "person"
            default: "doc.text"
            }
        }
    }

    struct Meddelande: Codable, Identifiable, Hashable {
        enum Roll: String, Codable { case människa, assistent }
        /// Varifrån svaret kommer. Kunskapsbanken svarar på sekunder ur det
        /// som sagts och skrivits; en kodagent tar längre tid men har läst
        /// filerna i en kopplad mapp.
        enum Ursprung: String, Codable { case kunskapsbank, mapp }

        var id = UUID()
        var roll: Roll
        var text: String
        var tid = Date()
        /// Vad svaret byggde på.
        var hänvisningar: [Hänvisning] = []
        var ursprung: Ursprung = .kunskapsbank
        /// Mappen svaret kommer ur, när det är en agent som svarat.
        var mapp: String?
    }

    struct Svar {
        var text: String
        var hänvisningar: [Hänvisning]
    }

    private let val: Modellval
    private let session: URLSession

    init(val: Modellval = .läs()) {
        self.val = val
        let k = URLSessionConfiguration.ephemeral
        // En lokal modell på en vanlig laptop kan tänka länge.
        k.timeoutIntervalForRequest = 300
        session = URLSession(configuration: k)
    }

    var färdig: Bool { val.färdig }
    var leverantör: Leverantör { val.leverantör }

    /// Ställer en fråga med utdrag ur kunskapsbanken som underlag.
    func fråga(_ text: String,
               om kund: String,
               projekt: String?,
               träffar: [Kunskapsbank.Träff],
               historik: [Meddelande]) async throws -> Svar {
        guard let url = val.url else { throw Fel.trasigAdress }
        let nyckel = Nyckelring.förLeverantör(val.leverantör)
        if val.leverantör.behöverNyckel && nyckel == nil { throw Fel.ingenNyckel(val.leverantör) }

        let system = Self.systemtext(kund: kund, projekt: projekt, träffar: träffar)
        // Bara de senaste turerna: äldre frågor har sitt eget underlag som
        // inte längre finns med, och drar svaret fel.
        let tidigare = historik.suffix(8)

        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try kropp(system: system, tidigare: Array(tidigare), fråga: text)

        switch val.leverantör {
        case .anthropic:
            r.setValue(nyckel, forHTTPHeaderField: "x-api-key")
            r.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .azure:
            r.setValue(nyckel, forHTTPHeaderField: "api-key")
        case .openrouter:
            r.setValue("Bearer \(nyckel ?? "")", forHTTPHeaderField: "Authorization")
            r.setValue("Kundkoll", forHTTPHeaderField: "X-Title")
        case .openai:
            r.setValue("Bearer \(nyckel ?? "")", forHTTPHeaderField: "Authorization")
        case .lokal:
            if let nyckel { r.setValue("Bearer \(nyckel)", forHTTPHeaderField: "Authorization") }
        }

        let (data, svar): (Data, URLResponse)
        do {
            (data, svar) = try await session.data(for: r)
        } catch {
            // En lokal modell som inte är igång är det vanligaste felet här.
            if val.leverantör == .lokal { throw Fel.nårInteLokal(url.host ?? "") }
            throw error
        }
        guard let http = svar as? HTTPURLResponse else { throw Fel.ingetSvar }
        guard http.statusCode == 200 else {
            throw Fel.frånTjänsten(http.statusCode, Self.felmeddelande(data))
        }

        let innehåll = val.leverantör.talarAnthropic
            ? Self.läsAnthropic(data)
            : Self.läsOpenAI(data)
        guard let innehåll, !innehåll.isEmpty else { throw Fel.tomtSvar }

        return Svar(text: innehåll, hänvisningar: Self.använda(i: innehåll, av: träffar))
    }

    // MARK: - Format

    static func systemtext(kund: String, projekt: String?,
                          träffar: [Kunskapsbank.Träff]) -> String {
        let sammanhang = träffar.enumerated().map { i, t in
            "[\(i + 1)] \(t.typ.uppercased()) — \(t.hänvisning)\n\(t.text)"
        }.joined(separator: "\n\n")

        var ut = """
        Du hjälper Anders att hålla ordning på sitt arbete med kunden \(kund).
        \(projekt.map { "Frågan gäller projektet \($0)." } ?? "")

        Svara på svenska, kort och konkret. Du får bara bygga svaret på
        underlaget nedan. Hittar du inte svaret där säger du det rent ut i
        stället för att gissa — att sakna uppgiften är ett användbart svar,
        ett påhittat är det inte.

        Hänvisa till underlaget med dess nummer i hakparentes, till exempel [2],
        direkt efter det du hämtat därifrån.
        """
        if träffar.isEmpty {
            ut += "\n\nDet finns inget underlag att gå på den här gången. Säg det."
        } else {
            ut += "\n\n# Underlag\n\n\(sammanhang)"
        }
        return ut
    }

    private func kropp(system: String, tidigare: [Meddelande], fråga: String) throws -> Data {
        var turer: [[String: String]] = []
        for m in tidigare {
            turer.append(["role": m.roll == .människa ? "user" : "assistant", "content": m.text])
        }
        turer.append(["role": "user", "content": fråga])

        if val.leverantör.talarAnthropic {
            // Anthropic har systemtexten som eget fält, inte som ett meddelande.
            return try JSONSerialization.data(withJSONObject: [
                "model": val.modell,
                "max_tokens": 2000,
                "system": system,
                "messages": turer,
            ])
        }

        var kropp: [String: Any] = [
            "messages": [["role": "system", "content": system]] + turer,
            "max_tokens": 2000,
        ]
        // Azure får modellen ur adressen, inte ur kroppen.
        if val.leverantör != .azure { kropp["model"] = val.modell }
        if val.leverantör == .openrouter {
            // Anthropic-modeller via OpenRouter kan annars lägga hela utrymmet
            // på att tänka och svara med tomt innehåll.
            kropp["reasoning"] = ["enabled": false]
        }
        return try JSONSerialization.data(withJSONObject: kropp)
    }

    static func läsOpenAI(_ data: Data) -> String? {
        struct Svarskropp: Decodable {
            struct Val: Decodable {
                struct M: Decodable { let content: String? }
                let message: M
            }
            let choices: [Val]
        }
        return (try? JSONDecoder().decode(Svarskropp.self, from: data))?
            .choices.first?.message.content
    }

    static func läsAnthropic(_ data: Data) -> String? {
        struct Svarskropp: Decodable {
            struct Block: Decodable { let type: String; let text: String? }
            let content: [Block]
        }
        guard let k = try? JSONDecoder().decode(Svarskropp.self, from: data) else { return nil }
        return k.content.filter { $0.type == "text" }.compactMap(\.text).joined()
    }

    /// Vilka av underlagen svaret faktiskt hänvisade till.
    static func använda(i text: String, av träffar: [Kunskapsbank.Träff]) -> [Hänvisning] {
        var ut: [Hänvisning] = []
        for (i, t) in träffar.enumerated() where text.contains("[\(i + 1)]") {
            ut.append(Hänvisning(nummer: i + 1, titel: t.titel, typ: t.typ,
                                 källa: t.källa, datum: t.tid))
        }
        return ut
    }

    private static func felmeddelande(_ data: Data) -> String {
        struct F: Decodable { struct I: Decodable { let message: String? }; let error: I? }
        return (try? JSONDecoder().decode(F.self, from: data))?.error?.message
            ?? String(data: data, encoding: .utf8)?.prefix(200).description
            ?? "okänt fel"
    }

    enum Fel: LocalizedError {
        case ingenNyckel(Leverantör), ingetSvar, tomtSvar, trasigAdress
        case nårInteLokal(String), frånTjänsten(Int, String)
        var errorDescription: String? {
            switch self {
            case .ingenNyckel(let l):
                "Ingen API-nyckel för \(l.namn). Lägg in den under Kundkoll → API-nyckel."
            case .ingetSvar: "Fick inget svar från modellen."
            case .tomtSvar: "Modellen svarade utan innehåll."
            case .trasigAdress: "Adressen till modellen går inte att tolka."
            case .nårInteLokal(let värd):
                "Når ingen modell på \(värd). Är Ollama eller LM Studio igång?"
            case .frånTjänsten(let kod, let text): "Modellen svarade \(kod): \(text)"
            }
        }
    }
}

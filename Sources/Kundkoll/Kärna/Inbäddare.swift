import Foundation

/// Bäddar in text med bge-m3 via Ollama, för sökningen på betydelse.
///
/// Uppmätt på det riktiga kundindexet (docs/KUNSKAPSBANK.md): trunkerad BM25
/// träffade 9 av 12, enbart inbäddningar 9 av 12 — men de missar olika
/// frågor, och hybriden tar 11 av 12. Det inbäddningarna ensamma tillför är
/// tvärspråket: svenska frågor mot engelska dokument, som avtal och
/// integrationsflöden, kan aldrig träffas av ordsökning.
///
/// Allt sker lokalt. Är Ollama nere eller modellen inte hämtad söker appen
/// som förut, med enbart BM25 — inbäddningarna är ett tillskott, aldrig ett
/// krav.
actor Inbäddare {
    static let delad = Inbäddare()
    static let modell = "bge-m3"

    /// Samma server som «Lokal modell» pekar på; standardporten om valet är ett moln.
    private var bas: URL { Modellval.läs().lokalBas ?? URL(string: "http://127.0.0.1:11434")! }
    private let session: URLSession
    /// Svaret på "finns modellen?", en liten stund. Utan cache skulle varje
    /// fråga börja med ett extra anrop.
    private var senastTillgänglig: (svar: Bool, när: Date)?

    init() {
        let k = URLSessionConfiguration.ephemeral
        k.timeoutIntervalForRequest = 120
        session = URLSession(configuration: k)
    }

    /// Om Ollama är igång och bge-m3 finns hämtad.
    var tillgänglig: Bool {
        get async {
            if let s = senastTillgänglig, Date().timeIntervalSince(s.när) < 60 {
                return s.svar
            }
            var r = URLRequest(url: bas.appending(path: "api/tags"))
            r.timeoutInterval = 2
            let svar: Bool
            if let (data, _) = try? await session.data(for: r),
               let text = String(data: data, encoding: .utf8) {
                svar = text.contains(Self.modell)
            } else {
                svar = false
            }
            senastTillgänglig = (svar, Date())
            return svar
        }
    }

    /// Vektorer för en bunt texter, i samma ordning.
    func bädda(_ texter: [String]) async throws -> [[Float]] {
        var r = URLRequest(url: bas.appending(path: "api/embed"))
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": Self.modell,
            "input": texter,
        ])
        let (data, svar) = try await session.data(for: r)
        guard (svar as? HTTPURLResponse)?.statusCode == 200 else {
            throw Enkeltfel("Ollama kunde inte bädda in texten.")
        }
        struct Ut: Decodable { let embeddings: [[Float]] }
        return try JSONDecoder().decode(Ut.self, from: data).embeddings
    }

    /// Bäddar in det i banken som ännu saknar vektor. Körs efter indexeringen
    /// och tål att avbrytas — nästa körning tar vid där det slutade.
    static func kör(bank: Kunskapsbank, parti: Int = 16) async {
        guard await delad.tillgänglig else { return }
        while true {
            let rader = bank.utanVektor(max: parti)
            guard !rader.isEmpty else { return }
            guard let vektorer = try? await delad.bädda(rader.map(\.text)) else { return }
            for (rad, v) in zip(rader, vektorer) {
                try? bank.sparaVektor(rad.id, v)
            }
            if rader.count < parti { return }
        }
    }
}

extension Kunskapsbank {
    /// Hybrid när Ollama finns, annars BM25 — anroparen behöver inte veta
    /// vilket det blev.
    func bästaSök(_ fråga: String, max antal: Int = 8) async -> [Träff] {
        if await Inbäddare.delad.tillgänglig,
           let v = try? await Inbäddare.delad.bädda([fråga]).first {
            return hybrid(fråga, vektor: v, max: antal)
        }
        return sök(fråga, max: antal)
    }
}

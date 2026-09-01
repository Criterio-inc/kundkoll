import Foundation
import SQLite3

/// Ett sökbart index över allt material hos en kund.
///
/// SQLite med FTS5, inte vektorer: `NLEmbedding` saknar svenska helt, och
/// molnembeddingar skulle innebära att allt kundmaterial skickas ut. BM25 över
/// trunkerade sökord räcker långt — se `docs/KUNSKAPSBANK.md` för mätningen.
///
/// Indexet är härlett. Går det sönder byggs det om från filerna, som är
/// sanningen.
final class Kunskapsbank {

    struct Träff: Identifiable, Hashable {
        var id: Int64
        var typ: String
        var titel: String
        var text: String
        var källa: String
        var tid: Date?
        var poäng: Double

        /// Det som visas som hänvisning under ett svar.
        var hänvisning: String {
            let datum = tid.map { " · " + DateFormatter.dag.string(from: $0) } ?? ""
            return "\(titel)\(datum)"
        }
    }

    private var db: OpaquePointer?
    private let fil: URL

    init(kund: Kund) throws {
        let mapp = kund.mapp.appending(path: ".kundkoll")
        try FileManager.default.createDirectory(at: mapp, withIntermediateDirectories: true)
        fil = mapp.appending(path: "index.db")
        guard sqlite3_open(fil.path, &db) == SQLITE_OK else { throw Fel.kanInteÖppna }
        try skapaTabeller()
    }

    deinit { sqlite3_close(db) }

    private func kör(_ sql: String) throws {
        var fel: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &fel) == SQLITE_OK else {
            let text = fel.map { String(cString: $0) } ?? "okänt fel"
            sqlite3_free(fel)
            throw Fel.sql(text)
        }
    }

    private func skapaTabeller() throws {
        // remove_diacritics 0: å ä ö är egna bokstäver i svenskan, inte a och o
        // med prickar. "mata" och "mäta" är olika ord.
        try kör("""
            CREATE VIRTUAL TABLE IF NOT EXISTS dokument USING fts5(
                titel, text, typ UNINDEXED, källa UNINDEXED, tid UNINDEXED,
                tokenize='unicode61 remove_diacritics 0'
            );
            CREATE TABLE IF NOT EXISTS källor (
                källa TEXT PRIMARY KEY,
                ändrad REAL NOT NULL
            );
            """)
    }

    // MARK: - Indexering

    /// Har filen ändrats sedan den indexerades?
    func behöverIndexeras(_ url: URL) -> Bool {
        guard let ändrad = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate)?.timeIntervalSince1970 else { return true }
        var s: OpaquePointer?
        defer { sqlite3_finalize(s) }
        guard sqlite3_prepare_v2(db, "SELECT ändrad FROM källor WHERE källa = ?", -1, &s, nil) == SQLITE_OK
        else { return true }
        bind(s, 1, url.path)
        guard sqlite3_step(s) == SQLITE_ROW else { return true }
        return sqlite3_column_double(s, 0) < ändrad - 0.5
    }

    /// Tar bort allt som kommer från en källa, så att omindexering inte dubblar.
    func glöm(källa: String) throws {
        var s: OpaquePointer?
        defer { sqlite3_finalize(s) }
        sqlite3_prepare_v2(db, "DELETE FROM dokument WHERE källa = ?", -1, &s, nil)
        bind(s, 1, källa)
        sqlite3_step(s)
    }

    func läggTill(titel: String, text: String, typ: String, källa: String, tid: Date?) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var s: OpaquePointer?
        defer { sqlite3_finalize(s) }
        guard sqlite3_prepare_v2(db,
            "INSERT INTO dokument(titel, text, typ, källa, tid) VALUES (?,?,?,?,?)",
            -1, &s, nil) == SQLITE_OK else { throw Fel.sql("kunde inte förbereda insert") }
        bind(s, 1, titel)
        bind(s, 2, text)
        bind(s, 3, typ)
        bind(s, 4, källa)
        bind(s, 5, tid.map { String($0.timeIntervalSince1970) } ?? "")
        guard sqlite3_step(s) == SQLITE_DONE else { throw Fel.sql("insert misslyckades") }
    }

    /// Noterar att källan är indexerad i sin nuvarande form.
    func markeraIndexerad(_ url: URL) throws {
        let ändrad = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate)?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
        var s: OpaquePointer?
        defer { sqlite3_finalize(s) }
        sqlite3_prepare_v2(db,
            "INSERT OR REPLACE INTO källor(källa, ändrad) VALUES (?,?)", -1, &s, nil)
        bind(s, 1, url.path)
        sqlite3_bind_double(s, 2, ändrad)
        sqlite3_step(s)
    }

    var antal: Int {
        var s: OpaquePointer?
        defer { sqlite3_finalize(s) }
        sqlite3_prepare_v2(db, "SELECT count(*) FROM dokument", -1, &s, nil)
        return sqlite3_step(s) == SQLITE_ROW ? Int(sqlite3_column_int(s, 0)) : 0
    }

    // MARK: - Sökning

    /// Söker och rangordnar med BM25.
    func sök(_ fråga: String, max antal: Int = 8) -> [Träff] {
        let uttryck = Self.sökuttryck(fråga)
        guard !uttryck.isEmpty else { return [] }

        var s: OpaquePointer?
        defer { sqlite3_finalize(s) }
        // Titeln väger tyngre än brödtexten.
        let sql = """
            SELECT rowid, typ, titel, text, källa, tid, bm25(dokument, 3.0, 1.0)
            FROM dokument WHERE dokument MATCH ?
            ORDER BY bm25(dokument, 3.0, 1.0) LIMIT ?
            """
        guard sqlite3_prepare_v2(db, sql, -1, &s, nil) == SQLITE_OK else { return [] }
        bind(s, 1, uttryck)
        sqlite3_bind_int(s, 2, Int32(antal))

        var ut: [Träff] = []
        while sqlite3_step(s) == SQLITE_ROW {
            let tidText = text(s, 5)
            let typ = text(s, 1)
            ut.append(Träff(
                id: sqlite3_column_int64(s, 0),
                typ: typ,
                titel: text(s, 2),
                text: text(s, 3),
                källa: text(s, 4),
                tid: Double(tidText).map { Date(timeIntervalSince1970: $0) },
                poäng: sqlite3_column_double(s, 6) * vikt(typ)))
        }
        // BM25 är negativ och lägre är bättre, så en vikt över 1 lyfter.
        return ut.sorted { $0.poäng < $1.poäng }
    }

    /// Hur tungt en källa väger.
    ///
    /// Tidigare chattar är härledda: de säger vad modellen svarade, inte vad
    /// som faktiskt hände. Ett svar som en gång sade "jag hittar inte X" blev
    /// annars det bäst rankade underlaget nästa gång samma fråga ställdes, och
    /// slog ut den fil som svaret saknades i. De är fortfarande värda att söka
    /// i — bara inte före primärkällorna.
    ///
    /// BM25 är negativ och lägre är bättre, så en faktor över 1 gör träffen
    /// starkare.
    private func vikt(_ typ: String) -> Double {
        switch typ {
        case "chatt": 0.4          // härlett, hamnar sist
        case "sammanfattning": 1.3 // destillerat, väger tyngst
        case "kontakt": 0.8
        default: 1.0
        }
    }

    /// Bygger FTS-uttrycket ur en fråga i vanlig svenska.
    ///
    /// Svenskan böjer och sätter samman: "leveranstid" hittar inte
    /// "leveranstiden" och "batteri" inte "battericeller". Uppmätt gav rak
    /// sökning träff på 2 av 9 rimliga frågor, trunkerad på 9 av 9. Därför
    /// kapas orden och söks som prefix.
    static func sökuttryck(_ fråga: String, minst: Int = 4, kapa: Int = 2) -> String {
        let ord = fråga
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.lowercased() }
            .filter { $0.count >= 2 && !stoppord.contains($0) }
        guard !ord.isEmpty else { return "" }
        return ord.map { o -> String in
            guard o.count >= minst else { return "\"\(o)\"" }
            return String(o.prefix(max(minst, o.count - kapa))) + "*"
        }
        .joined(separator: " OR ")
    }

    /// Ord som finns i varje text och bara späder ut träffarna.
    static let stoppord: Set<String> = [
        "och", "att", "det", "som", "för", "med", "den", "har", "vi", "är", "en",
        "ett", "på", "av", "till", "om", "från", "var", "vad", "hur", "när", "de",
        "jag", "du", "han", "hon", "man", "kan", "ska", "vill", "inte", "men",
        "eller", "så", "vid", "under", "över", "efter", "före", "mer", "vår",
    ]

    // MARK: - Småsaker

    private func bind(_ s: OpaquePointer?, _ i: Int32, _ v: String) {
        sqlite3_bind_text(s, i, v, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }

    private func text(_ s: OpaquePointer?, _ i: Int32) -> String {
        guard let p = sqlite3_column_text(s, i) else { return "" }
        return String(cString: p)
    }

    enum Fel: LocalizedError {
        case kanInteÖppna, sql(String)
        var errorDescription: String? {
            switch self {
            case .kanInteÖppna: "Kunde inte öppna kunskapsbanken."
            case .sql(let f): "Kunskapsbanken svarade med ett fel: \(f)"
            }
        }
    }
}

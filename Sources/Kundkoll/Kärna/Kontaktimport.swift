import Foundation
import Contacts

/// Läser kontakter ur en fil från Outlook, eller från vad som helst som kan
/// skriva vCard eller CSV.
///
/// vCard är förstahandsvalet: markera personerna i Outlook och dra dem till
/// Finder, så blir det en .vcf-fil, och macOS har inbyggd tolkning av
/// formatet. Outlook på webben exporterar i stället CSV, och det ser olika
/// ut beroende på språk: engelska rubriker med komma, svenska rubriker med
/// semikolon. Kolumnerna hittas därför på rubrikens innehåll, inte på plats.
///
/// Hämtning ur macOS Kontakter provades för M365 och fungerade inte — kontona
/// syns inte där. Därför en fil.
enum Kontaktimport {

    enum Fel: LocalizedError {
        case okäntFormat(String)
        case tomFil
        var errorDescription: String? {
            switch self {
            case .okäntFormat(let ä): "Kan bara läsa vCard (.vcf) och CSV, inte .\(ä)."
            case .tomFil: "Filen innehöll inga kontakter med namn."
            }
        }
    }

    /// Kontakterna i filen, utan dubbletter inom filen. Personer utan namn
    /// hoppas över — ett namn är det enda som alltid krävs.
    static func läs(_ url: URL) throws -> [Kontakt] {
        let data = try Data(contentsOf: url)
        let kontakter: [Kontakt]
        switch url.pathExtension.lowercased() {
        case "vcf", "vcard":
            kontakter = try urVCard(data)
        case "csv", "txt":
            kontakter = urCSV(text(ur: data))
        default:
            throw Fel.okäntFormat(url.pathExtension)
        }
        guard !kontakter.isEmpty else { throw Fel.tomFil }
        return kontakter
    }

    // MARK: - vCard

    static func urVCard(_ data: Data) throws -> [Kontakt] {
        let cn = try CNContactVCardSerialization.contacts(with: data)
        return slåIhop(cn.compactMap { c in
            let namn = [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
            let visat = namn.isEmpty ? c.organizationName : namn
            guard !visat.isEmpty else { return nil }
            return Kontakt(
                namn: visat,
                roll: c.jobTitle.isEmpty ? nil : c.jobTitle,
                epost: c.emailAddresses.map { ($0.value as String).trimmingCharacters(in: .whitespaces) },
                telefon: c.phoneNumbers.map { $0.value.stringValue })
        })
    }

    // MARK: - CSV

    static func urCSV(_ text: String) -> [Kontakt] {
        let rader = csvRader(text)
        guard let rubriker = rader.first else { return [] }
        let kolumner = rubriker.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }

        func index(där passar: (String) -> Bool) -> [Int] {
            kolumner.indices.filter { passar(kolumner[$0]) }
        }
        let förnamn = index { ["first name", "förnamn", "given name"].contains($0) }.first
        let efternamn = index { ["last name", "efternamn", "surname", "family name"].contains($0) }.first
        let heltNamn = index { ["name", "namn", "full name", "display name", "visningsnamn"].contains($0) }.first
        // «Title» och «Titel» är tilltal (Mr, Fru) i Outlook — inte befattningen.
        let roll = index { ["job title", "befattning", "roll", "role", "position"].contains($0) }.first
        let epost = index { $0.contains("e-mail") || $0.contains("email") || $0.contains("e-post") }
        let telefon = index {
            ($0.contains("phone") || $0.contains("telefon") || $0.contains("mobil"))
                && !$0.contains("fax")
        }

        var ut: [Kontakt] = []
        for rad in rader.dropFirst() {
            func fält(_ i: Int?) -> String {
                guard let i, i < rad.count else { return "" }
                return rad[i].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            var namn = [fält(förnamn), fält(efternamn)].filter { !$0.isEmpty }.joined(separator: " ")
            if namn.isEmpty { namn = fält(heltNamn) }
            guard !namn.isEmpty else { continue }
            let r = fält(roll)
            ut.append(Kontakt(
                namn: namn,
                roll: r.isEmpty ? nil : r,
                epost: epost.map(fält).filter { $0.contains("@") },
                telefon: telefon.map(fält).filter { !$0.isEmpty }))
        }
        return slåIhop(ut)
    }

    /// Delar upp CSV i rader och fält. Klarar citattecken med komman och
    /// radbrytningar inuti, dubbla citattecken som escape, och avgör
    /// avskiljaren (komma eller semikolon) på rubrikraden.
    static func csvRader(_ text: String) -> [[String]] {
        let avskiljare: Character = {
            let första = text.prefix(while: { !$0.isNewline })
            return första.filter { $0 == ";" }.count > första.filter { $0 == "," }.count ? ";" : ","
        }()
        var rader: [[String]] = []
        var rad: [String] = []
        var fält = ""
        var iCitat = false
        var tecken = text.makeIterator()
        var nästa = tecken.next()
        while let c = nästa {
            nästa = tecken.next()
            if iCitat {
                if c == "\"" {
                    if nästa == "\"" { fält.append("\""); nästa = tecken.next() }
                    else { iCitat = false }
                } else {
                    fält.append(c)
                }
            } else if c == "\"" {
                iCitat = true
            } else if c == avskiljare {
                rad.append(fält); fält = ""
            } else if c.isNewline {
                // «\r\n» är ett enda tecken i Swift, så ingen särskild hantering.
                rad.append(fält); fält = ""
                if rad.contains(where: { !$0.isEmpty }) { rader.append(rad) }
                rad = []
            } else {
                fält.append(c)
            }
        }
        if !fält.isEmpty || !rad.isEmpty {
            rad.append(fält)
            if rad.contains(where: { !$0.isEmpty }) { rader.append(rad) }
        }
        return rader
    }

    /// Outlook skriver UTF-8 med byteordningsmärke; äldre Windows-exporter
    /// är Latin-1. Märket tas bort, annars hamnar det i första rubriken.
    static func text(ur data: Data) -> String {
        var d = data
        if d.starts(with: [0xEF, 0xBB, 0xBF]) { d = d.dropFirst(3) }
        return String(data: d, encoding: .utf8)
            ?? String(data: d, encoding: .isoLatin1)
            ?? ""
    }

    // MARK: - Dubbletter

    /// Samma person två gånger i filen slås ihop: samma e-postadress eller
    /// samma namn räknas som samma person, och uppgifterna läggs samman.
    static func slåIhop(_ kontakter: [Kontakt]) -> [Kontakt] {
        var ut: [Kontakt] = []
        for k in kontakter {
            if let i = ut.firstIndex(where: { $0.ärSammaPerson(som: k) }) {
                ut[i].taUpp(k)
            } else {
                ut.append(k)
            }
        }
        return ut
    }
}

extension Kontakt {
    /// Samma person: delar identifierare i adressboken, en e-postadress,
    /// eller namnet.
    func ärSammaPerson(som k: Kontakt) -> Bool {
        if let a = systemID, let b = k.systemID, a == b { return true }
        let mina = Set(epost.map { $0.lowercased() })
        if k.epost.contains(where: { mina.contains($0.lowercased()) }) { return true }
        return namn.caseInsensitiveCompare(k.namn) == .orderedSame
    }

    /// Fyller på med det som saknas — befintliga uppgifter skrivs inte över.
    mutating func taUpp(_ k: Kontakt) {
        roll = roll ?? k.roll
        systemID = systemID ?? k.systemID
        bild = bild ?? k.bild
        for e in k.epost where !epost.contains(where: { $0.caseInsensitiveCompare(e) == .orderedSame }) {
            epost.append(e)
        }
        for t in k.telefon where !telefon.contains(t) { telefon.append(t) }
    }
}

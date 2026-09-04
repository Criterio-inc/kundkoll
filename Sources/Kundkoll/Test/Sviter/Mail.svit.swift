import Foundation

extension Tester {
    static func mail() {
        Prov.svit("Mail")

        do {   // tolkning av svaret
            let d = "\u{1F}"
            let rader = [
                "Tuesday, 18 August 2026 at 00:49:37\(d)\"Acme AB\" <faktura@acme.se>\(d)Faktura 1234\(d)<abc@acme.se>\(d)anders@exempel.se\(d)INBOX\(d)från",
                "Monday, 17 August 2026 at 09:00:00\(d)Anna <anna@acme.se>\(d)Re: Offert | version 2\(d)<def@acme.se>\(d)anders@exempel.se\(d)INBOX\(d)från",
            ].joined(separator: "\n")
            let mejl = Mailen.tolka(rader)
            Prov.lika(mejl.count, 2, "båda raderna tolkas")
            Prov.kolla(!(mejl.first?.skickat ?? true), "mejl ur inkorgen räknas som mottagna")
            Prov.lika(mejl.first?.ämne, "Faktura 1234", "ämnet kommer med")
            Prov.lika(mejl.first?.avsändarnamn, "Acme AB", "namnet plockas ur avsändaren")
            Prov.lika(mejl.first?.avsändaradress, "faktura@acme.se", "adressen plockas ur avsändaren")
            Prov.kolla(mejl.contains { $0.ämne == "Re: Offert | version 2" },
                       "ämnen med rörtecken överlever, därav ASCII 31 som avgränsare")
            Prov.kolla((mejl.first?.datum ?? .distantPast) > (mejl.last?.datum ?? .distantFuture),
                       "nyaste mejlet först")
        }

        do {   // datumformatet Mail lämnar
            let d = Mailen.datum(ur: "Tuesday, 18 August 2026 at 00:49:37")
            Prov.kolla(d != nil, "Mails datumsträng går att tolka")
            if let d {
                let delar = Calendar.current.dateComponents([.year, .month, .day, .hour], from: d)
                Prov.lika(delar.year, 2026, "rätt år")
                Prov.lika(delar.month, 8, "rätt månad")
                Prov.lika(delar.day, 18, "rätt dag")
            }
            Prov.kolla(Mailen.datum(ur: "skräp") == nil, "skräp ger nil i stället för fel datum")
        }

        do {   // riktning
            let d = "\u{1F}"
            let rader = [
                "Monday, 3 August 2026 at 09:00:00\(d)Anders <anders@exempel.se>\(d)Re: Offert\(d)<a@x>\(d)anders@exempel.se\(d)Sent Messages\(d)till",
                "Monday, 3 August 2026 at 08:00:00\(d)Anna <anna@acme.se>\(d)Offert\(d)<b@x>\(d)anders@exempel.se\(d)INBOX\(d)fran",
            ].joined(separator: "\n")
            let mejl = Mailen.tolka(rader)
            Prov.lika(mejl.count, 2, "både mottaget och skickat tolkas")
            Prov.kolla(mejl.first?.skickat == true, "det jag skickat känns igen som skickat")
            Prov.kolla(mejl.last?.skickat == false, "det jag fått räknas inte som skickat")
        }

        do {   // cache
            let rot = FileManager.default.temporaryDirectory
                .appending(path: "kundkoll-test-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: rot) }
            let arkiv = Arkivet(rot: rot)
            let kund = try! arkiv.skapaKund(namn: "Acme")
            Prov.kolla(arkiv.mailcache(för: kund) == nil, "ingen cache från början")

            let d = "\u{1F}"
            let mejl = Mailen.tolka(
                "Monday, 3 August 2026 at 09:00:00\(d)Anna <anna@acme.se>\(d)Offert\(d)<a@x>\(d)konto\(d)INBOX\(d)fran")
            try! arkiv.sparaMail(mejl, för: kund)

            let cache = arkiv.mailcache(för: kund)
            Prov.lika(cache?.mejl.count, 1, "mejlen finns kvar efter omstart")
            Prov.lika(cache?.mejl.first?.ämne, "Offert", "med ämnet i behåll")
            Prov.kolla(cache?.färsk == true, "en nyss hämtad cache räknas som färsk")

            let gammal = Arkivet.Mailcache(hämtad: Date().addingTimeInterval(-3600), mejl: mejl)
            Prov.kolla(!gammal.färsk, "en timme gammal cache hämtas om")

            let not = try! String(contentsOf: kund.mailmapp.appending(path: "Mail.md"),
                                  encoding: .utf8)
            Prov.kolla(not.contains("Offert"), "korrespondensen skrivs till Obsidian")
            Prov.kolla(not.contains("[[Acme]]"), "med länk till kunden")
        }

        do {   // trasiga rader
            Prov.lika(Mailen.tolka("").count, 0, "tomt svar ger inga mejl")
            Prov.lika(Mailen.tolka("bara en text utan fält").count, 0, "rader utan fält hoppas över")
            // Äldre rader utan riktningsfält ska inte falla
            let utanRiktning = "Monday, 3 August 2026 at 08:00:00\u{1F}A <a@x.se>\u{1F}Ämne\u{1F}<b@x>\u{1F}konto\u{1F}INBOX"
            Prov.lika(Mailen.tolka(utanRiktning).count, 1, "rader utan riktningsfält tolkas ändå")
        }
    }
}

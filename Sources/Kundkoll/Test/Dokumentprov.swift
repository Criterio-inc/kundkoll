import Foundation

/// Läser alla dokument i en mapp på samma väg som kunskapsbanken gör och
/// säger per filtyp hur många som gav text, och varför de andra inte gjorde
/// det.
///
///     Kundkoll --prov-dokument <mapp>
///
/// Uppmätt på en riktig kundmapp med 593 filer: 219 gav text med den gamla
/// kontorsfilsläsaren, och räknaren i appen sa «219 dokument» som om det
/// vore allt. Det här provet finns för att den siffran ska gå att se innan
/// någon undrar var resten tog vägen.
enum Dokumentprov {

    private struct Rad {
        var antal = 0
        var medText = 0
        var tecken = 0
        var utan: [String] = []
    }

    static func kör(mapp: String) async -> Int32 {
        Prov.svit("Dokument i \(mapp)")
        let kopplad = Kopplad(väg: mapp)
        guard kopplad.finns else { print("Mappen finns inte: \(mapp)"); return 1 }
        let filer = Kopplademappar.dokument(i: kopplad)
        print("\(filer.count) filer att läsa\n")

        var perTyp: [String: Rad] = [:]
        // Varför de utan text saknar den, räknat över alla typer.
        var orsaker: [String: Int] = [:]
        let t0 = Date()
        for (i, url) in filer.enumerated() {
            let ändelse = url.pathExtension.lowercased()
            let storlek = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let bilaga = Bilagor.Bilaga(ämne: "", namn: url.lastPathComponent,
                                        fil: url.path, storlek: storlek)
            let text = await Bilagor.text(ur: bilaga) ?? ""
            var rad = perTyp[ändelse] ?? Rad()
            rad.antal += 1
            if text.isEmpty {
                var skäl = Filsignatur.beskriv(url)
                orsaker[skäl, default: 0] += 1
                if ["docx", "pptx", "xlsx", "docm", "pptm", "xlsm", "potx", "xltx"].contains(ändelse),
                   let k = Kontorsfiler.text(ur: url).skäl {
                    skäl = k
                }
                if rad.utan.count < 5 {
                    rad.utan.append(url.lastPathComponent + (skäl.isEmpty ? "" : " — \(skäl)"))
                }
            } else {
                rad.medText += 1
                rad.tecken += text.count
            }
            perTyp[ändelse] = rad
            if (i + 1) % 50 == 0 { print("  \(i + 1) av \(filer.count) …") }
        }
        let tid = Date().timeIntervalSince(t0)

        print("\ntyp        filer  med text  tecken per fil")
        var totalt = 0
        var medText = 0
        for (typ, rad) in perTyp.sorted(by: { $0.value.antal > $1.value.antal }) {
            let snitt = rad.medText > 0 ? rad.tecken / rad.medText : 0
            print(typ.padding(toLength: 10, withPad: " ", startingAt: 0)
                  + String(rad.antal).padding(toLength: 7, withPad: " ", startingAt: 0)
                  + String(rad.medText).padding(toLength: 10, withPad: " ", startingAt: 0)
                  + String(snitt))
            totalt += rad.antal
            medText += rad.medText
        }
        print(String(format: "\n%d av %d filer gav text på %.1f s", medText, totalt, tid))
        if !orsaker.isEmpty {
            print("\nde utan text, per orsak:")
            for (orsak, n) in orsaker.sorted(by: { $0.value > $1.value }) {
                print("  \(n)  \(orsak)")
            }
        }
        for (typ, rad) in perTyp.sorted(by: { $0.key < $1.key }) where !rad.utan.isEmpty {
            print("\nutan text (\(typ), de första):")
            for u in rad.utan { print("  · \(u)") }
        }
        Prov.kolla(totalt > 0, "mappen innehåller dokument")
        Prov.kolla(medText * 10 >= totalt * 8,
                   "minst åtta av tio filer gav text (\(medText) av \(totalt))")
        return Prov.sammanfatta()
    }
}

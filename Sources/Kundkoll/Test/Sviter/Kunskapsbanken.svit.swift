import Foundation
import SQLite3

extension Tester {
    static func kunskapsbanken() {
        Prov.svit("Kunskapsbanken")

        do {   // sökuttryck
            let u = Kunskapsbank.sökuttryck("leveranstiden")
            Prov.kolla(u.contains("*"), "orden söks som prefix, så böjningar fångas (\(u))")
            Prov.kolla(!Kunskapsbank.sökuttryck("vad har vi sagt om priset").contains("\"vad\""),
                       "stoppord sållas bort")
            Prov.kolla(Kunskapsbank.sökuttryck("och att det som").isEmpty,
                       "en fråga med bara stoppord ger inget uttryck")
            Prov.kolla(Kunskapsbank.sökuttryck("").isEmpty, "tom fråga ger tomt uttryck")
            Prov.kolla(Kunskapsbank.sökuttryck("DNV").contains("dnv"),
                       "korta ord söks exakt, inte som prefix")
        }

        do {   // indexera och söka
            let rot = FileManager.default.temporaryDirectory
                .appending(path: "kundkoll-test-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: rot) }
            let arkiv = Arkivet(rot: rot)
            let kund = try! arkiv.skapaKund(namn: "Acme")
            let bank = try! Kunskapsbank(kund: kund)

            try! bank.läggTill(titel: "Avstämning", text: "Bo undrade över leveranstiden till Göteborg",
                               typ: "transkript", källa: "/a", tid: Date())
            try! bank.läggTill(titel: "Prisdiskussion", text: "Vi gick igenom prisbilden på battericeller",
                               typ: "transkript", källa: "/b", tid: Date())
            Prov.lika(bank.antal, 2, "två stycken i banken")

            // Det böjningsproblem trunkeringen finns till för
            Prov.kolla(!bank.sök("leveranstid").isEmpty,
                       "«leveranstid» hittar «leveranstiden»")
            Prov.kolla(!bank.sök("batteri").isEmpty,
                       "«batteri» hittar «battericeller»")
            Prov.lika(bank.sök("leveranstid").first?.titel, "Avstämning",
                      "rätt stycke kommer först")
            Prov.kolla(bank.sök("segelbåtar").isEmpty, "det som inte finns ger inga träffar")

            try! bank.glöm(källa: "/a")
            Prov.lika(bank.antal, 1, "en källa går att glömma")
            Prov.kolla(bank.sök("leveranstid").isEmpty, "och försvinner ur sökningen")
        }

        do {   // källor väger olika
            let rot = FileManager.default.temporaryDirectory
                .appending(path: "kundkoll-test-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: rot) }
            let arkiv = Arkivet(rot: rot)
            let kund = try! arkiv.skapaKund(namn: "Acme")
            let bank = try! Kunskapsbank(kund: kund)

            // Ett gammalt chattsvar som sade att uppgiften saknades, och
            // fakturan som faktiskt har den.
            try! bank.läggTill(titel: "vad var fakturan på?",
                               text: "Fråga: vad var fakturan på? Svar: Beloppet framgår inte.",
                               typ: "chatt", källa: "/c", tid: nil)
            try! bank.läggTill(titel: "1124 Acme AB.pdf",
                               text: "Faktura fakturanr 1124 belopp 62 500,00 SEK",
                               typ: "bilaga", källa: "/b", tid: nil)

            let träffar = bank.sök("vad var fakturan på")
            Prov.lika(träffar.first?.typ, "bilaga",
                      "primärkällan går före ett tidigare chattsvar")
            Prov.kolla(träffar.contains { $0.typ == "chatt" },
                       "chatten finns kvar bland träffarna, bara längre ner")
        }

        do {   // svenska tecken i sökningen
            let rot = FileManager.default.temporaryDirectory
                .appending(path: "kundkoll-test-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: rot) }
            let arkiv = Arkivet(rot: rot)
            let kund = try! arkiv.skapaKund(namn: "Ängsö")
            let bank = try! Kunskapsbank(kund: kund)
            try! bank.läggTill(titel: "Möte", text: "Vi besökte ÄNGSÖ och såg på pallställen",
                               typ: "anteckning", källa: "/a", tid: nil)
            Prov.kolla(!bank.sök("ängsö").isEmpty, "å ä ö söks utan hänsyn till skiftläge")
            Prov.kolla(!bank.sök("pallställ").isEmpty, "och fungerar mitt i sammansatta ord")
        }

        do {   // styckning av transkript
            var rader: [Yttrande] = []
            for i in 0..<40 {
                rader.append(Yttrande(röst: i % 2 == 0 ? .jag : .motpart,
                                      text: String(repeating: "ord ", count: 12),
                                      start: Double(i) * 5, slut: Double(i) * 5 + 4))
            }
            let i = Inspelning(titel: "Långt möte", inledd: Date(), längd: 200,
                               kund: "Acme", projekt: nil, mikrofon: nil,
                               liveYttranden: rader, arkivYttranden: nil)
            let stycken = Indexering.stycken(av: i)
            Prov.kolla(stycken.count > 1, "ett långt transkript delas i flera stycken (\(stycken.count))")
            Prov.kolla(stycken.allSatisfy { $0.count < Indexering.styckestorlek + 200 },
                       "inget stycke blir orimligt långt")
            Prov.kolla(stycken.first?.contains("Jag:") == true,
                       "talaren följer med in i texten")
            Prov.kolla(stycken.first?.contains("[00:00]") == true,
                       "och tidsstämpeln också, så svaret kan peka på rätt ställe")
        }

        do {   // styckning av text
            let text = "Första stycket.\n\n" + String(repeating: "Fyllnad. ", count: 200)
                + "\n\nSista stycket."
            let delar = Indexering.dela(text, storlek: 400)
            Prov.kolla(delar.count >= 2, "lång text delas (\(delar.count) delar)")
            Prov.kolla(delar.first?.hasPrefix("Första stycket.") == true,
                       "delningen sker vid styckegränser")
            Prov.lika(Indexering.dela("", storlek: 400).count, 0, "tom text ger inga delar")
        }

        do {   // hänvisningar i svaret
            func träff(_ titel: String) -> Kunskapsbank.Träff {
                Kunskapsbank.Träff(id: 1, typ: "transkript", titel: titel, text: "",
                                   källa: "", tid: nil, poäng: 0)
            }
            let träffar = [träff("Avstämning"), träff("Prisdiskussion"), träff("Uppstart")]
            let använda = Chatt.använda(i: "Priset diskuterades [2] och nämndes igen [2].", av: träffar)
            Prov.lika(använda.map(\.titel), ["Prisdiskussion"], "bara det svaret hänvisade till räknas")
            Prov.lika(använda.first?.nummer, 2, "numret följer med, så det går att para ihop med texten")
            Prov.lika(Chatt.använda(i: "Jag hittar inget om det.", av: träffar).count, 0,
                      "ett svar utan hänvisningar ger inga källor")
        }

        do {   // leverantörer
            for l in Leverantör.allCases {
                Prov.kolla(URL(string: l.standardadress) != nil,
                           "\(l.namn) har en giltig standardadress")
            }
            Prov.kolla(Leverantör.anthropic.talarAnthropic, "Anthropic har eget format")
            Prov.kolla(!Leverantör.openai.talarAnthropic, "OpenAI följer sitt eget")
            Prov.kolla(!Leverantör.openrouter.talarAnthropic,
                       "OpenRouter talar OpenAI-formatet även för Claude-modeller")
            Prov.kolla(!Leverantör.lokal.behöverNyckel, "en lokal modell behöver ingen nyckel")
            Prov.kolla(Leverantör.azure.behöverEgenAdress, "Azure kräver egen adress")

            var v = Modellval(leverantör: .lokal, modell: "llama3.1:8b", adress: "")
            Prov.kolla(v.färdig, "en lokal modell är färdig utan nyckel")
            Prov.lika(v.url?.host, "127.0.0.1", "och pekar på datorn")

            v = Modellval(leverantör: .azure, modell: "", adress: "")
            Prov.kolla(!v.färdig, "Azure utan adress är inte färdig")
        }

        do {   // svarsformat
            let openai = """
            {"choices":[{"message":{"role":"assistant","content":"Svaret är 42."}}]}
            """.data(using: .utf8)!
            Prov.lika(Chatt.läsOpenAI(openai), "Svaret är 42.", "OpenAI-svar tolkas")

            let anthropic = """
            {"content":[{"type":"thinking","text":"funderar"},{"type":"text","text":"Svaret är 42."}]}
            """.data(using: .utf8)!
            Prov.lika(Chatt.läsAnthropic(anthropic), "Svaret är 42.",
                      "Anthropic-svar tolkas och tankeblock hoppas över")

            Prov.kolla(Chatt.läsOpenAI(Data("{}".utf8)) == nil, "trasigt svar ger nil")
            Prov.kolla(Chatt.läsAnthropic(Data("{}".utf8)) == nil, "detsamma för Anthropic")
        }

        do {   // systemtexten
            let text = Chatt.systemtext(kund: "Acme", projekt: "Nytt lager", träffar: [])
            Prov.kolla(text.contains("Acme"), "kunden nämns")
            Prov.kolla(text.contains("Nytt lager"), "projektet nämns")
            Prov.kolla(text.contains("inget underlag"),
                       "utan underlag instrueras modellen att säga det")

            let träff = Kunskapsbank.Träff(id: 1, typ: "transkript", titel: "Möte",
                                           text: "Priset är 400 000.", källa: "", tid: nil, poäng: 0)
            let med = Chatt.systemtext(kund: "Acme", projekt: nil, träffar: [träff])
            Prov.kolla(med.contains("[1] TRANSKRIPT"), "underlaget numreras")
            Prov.kolla(med.contains("400 000"), "och innehåller texten")
        }

        do {   // bilagor
            Prov.kolla(Bilagor.ärIntressant("Offert.pdf"), "en PDF är värd att spara")
            Prov.kolla(Bilagor.ärIntressant("Skärmbild 2026-07-09.png"), "en skärmbild också")
            Prov.kolla(!Bilagor.ärIntressant("Mail Attachment.ics"),
                       "kalenderfiler säger inget om kunden")
            Prov.kolla(!Bilagor.ärIntressant("image001.png"),
                       "inbäddade signaturbilder sorteras bort")
            Prov.kolla(Bilagor.ärIntressant("image001-ritning.png"),
                       "men en bild med riktigt namn behålls")
            Prov.kolla(!Bilagor.ärIntressant("smime.p7s"), "signaturfiler sorteras bort")

            let d = "\u{1F}"
            let rader = [
                "Offert våren\(d)Offert.pdf\(d)/tmp/Offert.pdf\(d)102400",
                "Möte\(d)Mail Attachment.ics\(d)/tmp/x.ics\(d)4198",
                "Ritningar\(d)plan.png\(d)/tmp/plan.png\(d)51200",
            ].joined(separator: "\n")
            let b = Bilagor.tolka(rader)
            Prov.lika(b.count, 2, "ointressanta bilagor faller bort vid tolkningen")
            Prov.lika(b.first?.namn, "Offert.pdf", "namnet kommer med")
            Prov.lika(b.first?.storlek, 102400, "storleken tolkas")
            Prov.lika(b.first?.ändelse, "pdf", "ändelsen plockas ur namnet")

            Prov.lika(Bilagor.tolka("").count, 0, "tomt svar ger inga bilagor")
        }

        do {   // text ur kontorsfiler
            let xml = "<w:p><w:r><w:t>Offerten g&amp;auml;ller</w:t></w:r><w:t>400 &lt;pallplatser&gt;</w:t></w:p>"
            let text = Bilagor.strippaTaggar(xml)
            Prov.kolla(text.contains("Offerten"), "texten mellan taggarna kommer med")
            Prov.kolla(text.contains("400"), "och nästa stycke också")
            Prov.kolla(!text.contains("<w:"), "taggarna följer inte med")
            Prov.kolla(!text.contains("&lt;"), "XML-entiteter översätts")

            // Bara filerna som bär text. Utan det kom rader som "Microsoft
            // Office Word 0 406 248" med mitt i innehållet.
            func url(_ v: String) -> URL { URL(fileURLWithPath: v) }
            Prov.kolla(Bilagor.ärInnehåll(url("/t/word/document.xml")), "word/document.xml läses")
            Prov.kolla(Bilagor.ärInnehåll(url("/t/ppt/slides/slide1.xml")), "presentationsbilder läses")
            Prov.kolla(Bilagor.ärInnehåll(url("/t/xl/sharedStrings.xml")), "kalkylbladets texter läses")
            Prov.kolla(!Bilagor.ärInnehåll(url("/t/docProps/app.xml")), "dokumentegenskaper hoppas över")
            Prov.kolla(!Bilagor.ärInnehåll(url("/t/word/theme/theme1.xml")), "teman hoppas över")
            Prov.kolla(!Bilagor.ärInnehåll(url("/t/word/settings.xml")), "inställningar hoppas över")
        }

        do {   // ofullständiga inspelningar
            let rot = FileManager.default.temporaryDirectory
                .appending(path: "kundkoll-test-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: rot) }
            let arkiv = Arkivet(rot: rot)
            let kund = try! arkiv.skapaKund(namn: "Acme")
            let fm = FileManager.default

            // En mapp med ljud men utan möte.json, som en avbruten import
            let halv = try! arkiv.nyInspelningsmapp(placering: .kund(kund),
                                                    titel: "Avbruten", datum: Date())
            fm.createFile(atPath: halv.appending(path: "motpart.wav").path,
                          contents: Data(count: 5000))
            // Och en tom mapp, som inte är värd att visa
            let tom = try! arkiv.nyInspelningsmapp(placering: .kund(kund),
                                                   titel: "Tom", datum: Date())
            _ = tom

            let ofullständiga = arkiv.ofullständiga(för: kund)
            Prov.lika(ofullständiga.count, 1, "bara mappen med ljud räknas som påbörjad")
            Prov.lika(ofullständiga.first?.storlek, 5000, "storleken räknas")
            Prov.lika(arkiv.inspelningar(för: kund).count, 0,
                      "den syns inte bland de färdiga")

            // När den blir klar ska den försvinna ur listan
            let i = Inspelning(titel: "Avbruten", inledd: Date(), längd: 1,
                               kund: "Acme", projekt: nil, mikrofon: nil,
                               liveYttranden: [], arkivYttranden: nil)
            try! arkiv.spara(i, i: halv)
            Prov.lika(arkiv.ofullständiga(för: kund).count, 0,
                      "en färdigställd inspelning räknas inte längre som påbörjad")
        }

        do {   // kopplade mappar
            Prov.kolla(Kopplademappar.hoppaÖver.contains("node_modules"),
                       "node_modules läses inte igenom")
            Prov.kolla(Kopplademappar.hoppaÖver.contains(".git"), "inte heller .git")
            Prov.kolla(Kopplademappar.standardändelser.contains("swift"), "kodfiler tas med")
            Prov.kolla(Kopplademappar.standardändelser.contains("pdf"), "och PDF")
            Prov.kolla(!Kopplademappar.standardändelser.contains("png"),
                       "bilder i en kodmapp är sällan innehåll")

            let ä = Kopplademappar.standardändelser
            Prov.kolla(Kopplademappar.ärIntressant(URL(fileURLWithPath: "/a/main.swift"), ändelser: ä),
                       "en källfil är intressant")
            Prov.kolla(!Kopplademappar.ärIntressant(URL(fileURLWithPath: "/a/.env"), ändelser: ä),
                       "dolda filer hoppas över")
            Prov.kolla(!Kopplademappar.ärIntressant(URL(fileURLWithPath: "/a/bild.png"), ändelser: ä),
                       "bilder hoppas över")

            let k = Kopplad(väg: "/tmp/kod")
            Prov.lika(k.visatNamn, "kod", "mappens eget namn används när inget angetts")
            Prov.lika(Kopplad(väg: "/tmp/kod", namn: "Källkod").visatNamn, "Källkod",
                      "ett eget namn går före")
        }

        do {   // koppling sparas på projektet
            let rot = FileManager.default.temporaryDirectory
                .appending(path: "kundkoll-test-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: rot) }
            let arkiv = Arkivet(rot: rot)
            let kund = try! arkiv.skapaKund(namn: "Acme")
            let projekt = try! arkiv.skapaProjekt(namn: "Nytt lager", hos: kund)

            let mapp = rot.appending(path: "extern-kod")
            try! FileManager.default.createDirectory(at: mapp, withIntermediateDirectories: true)
            try! arkiv.koppla(mapp, till: projekt)
            Prov.lika(arkiv.kopplade(för: projekt).count, 1, "mappen kopplas till projektet")

            try! arkiv.koppla(mapp, till: projekt)
            Prov.lika(arkiv.kopplade(för: projekt).count, 1, "samma mapp två gånger ger ingen dubblett")

            let k = arkiv.kopplade(för: projekt).first!
            Prov.kolla(k.finns, "kopplingen ser att mappen finns")
            try! arkiv.koppla(bort: k, från: projekt)
            Prov.lika(arkiv.kopplade(för: projekt).count, 0, "den går att koppla bort")
            Prov.kolla(FileManager.default.fileExists(atPath: mapp.path),
                       "och mappen ligger kvar på disk — bara kopplingen försvann")

            // Kunden har samma uppsättning genom Placering; filen bor hos kunden.
            try! arkiv.koppla(mapp, till: .kund(kund))
            Prov.lika(arkiv.kopplade(för: kund).count, 1, "mappen kopplas till kunden")
            Prov.lika(arkiv.kopplade(för: projekt).count, 0, "utan att projektet påverkas")
            Prov.kolla(FileManager.default.fileExists(atPath: kund.mapp.appending(path: "kopplade-mappar.json").path),
                       "kopplingsfilen ligger i kundmappen")
            try! arkiv.koppla(bort: arkiv.kopplade(för: kund).first!, från: .kund(kund))
            Prov.lika(arkiv.kopplade(för: kund).count, 0, "och går att koppla bort från kunden")
        }

        do {   // genomgång av en mapp
            let rot = FileManager.default.temporaryDirectory
                .appending(path: "kundkoll-test-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: rot) }
            let fm = FileManager.default
            for väg in ["src", "node_modules/paket", ".git"] {
                try! fm.createDirectory(at: rot.appending(path: väg), withIntermediateDirectories: true)
            }
            fm.createFile(atPath: rot.appending(path: "src/main.swift").path, contents: Data("kod".utf8))
            fm.createFile(atPath: rot.appending(path: "README.md").path, contents: Data("text".utf8))
            fm.createFile(atPath: rot.appending(path: "logo.png").path, contents: Data([0x89]))
            fm.createFile(atPath: rot.appending(path: "node_modules/paket/index.js").path,
                          contents: Data("skräp".utf8))
            fm.createFile(atPath: rot.appending(path: ".git/config").path, contents: Data("x".utf8))

            let filer = Kopplademappar.filer(i: Kopplad(väg: rot.path))
            let namn = Set(filer.map(\.lastPathComponent))
            Prov.kolla(namn.contains("main.swift"), "källfiler hittas i undermappar")
            Prov.kolla(namn.contains("README.md"), "och dokument")
            Prov.kolla(!namn.contains("logo.png"), "bilder hoppas över")
            Prov.kolla(!namn.contains("index.js"),
                       "node_modules gås inte igenom (\(namn.count) filer totalt)")
            Prov.kolla(!namn.contains("config"), ".git gås inte igenom")

            // Dokumenten i samma mapp — de som går till kunskapsbanken.
            fm.createFile(atPath: rot.appending(path: "Rapport.docx").path, contents: Data("x".utf8))
            fm.createFile(atPath: rot.appending(path: "~$Rapport.docx").path, contents: Data("x".utf8))
            let dok = Set(Kopplademappar.dokument(i: Kopplad(väg: rot.path)).map(\.lastPathComponent))
            Prov.kolla(dok.contains("Rapport.docx"), "kontorsfiler räknas som dokument")
            Prov.kolla(dok.contains("README.md"), "markdown också")
            Prov.kolla(dok.contains("logo.png"), "och bilder — Vision läser texten i dem")
            Prov.kolla(!dok.contains("main.swift"), "men inte kod")
            Prov.kolla(!dok.contains("~$Rapport.docx"), "Office låsfiler hoppas över")
            Prov.kolla(Kopplademappar.harKod(Kopplad(väg: rot.path)),
                       "mappen har kod, så agenten får den")
            let bara = rot.appending(path: "dokument")
            try! fm.createDirectory(at: bara, withIntermediateDirectories: true)
            fm.createFile(atPath: bara.appending(path: "Offert.pdf").path, contents: Data("x".utf8))
            Prov.kolla(!Kopplademappar.harKod(Kopplad(väg: bara.path)),
                       "en mapp med bara dokument får ingen agent")
        }

        do {   // kunskapsbanken minns var dokument kom ifrån
            let rot = FileManager.default.temporaryDirectory
                .appending(path: "kundkoll-test-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: rot) }
            try! FileManager.default.createDirectory(at: rot, withIntermediateDirectories: true)
            let bank = try! Kunskapsbank(kund: Kund(namn: "Prov", mapp: rot))
            try! bank.läggTill(titel: "a", text: "alfa", typ: "dokument", källa: "/m/a.docx", tid: nil)
            try! bank.läggTill(titel: "b", text: "beta", typ: "dokument", källa: "/m/b.pdf", tid: nil)
            try! bank.markeraIndexerad(URL(fileURLWithPath: "/m/a.docx"))
            try! bank.markeraIndexerad(URL(fileURLWithPath: "/m/b.pdf"))
            Prov.lika(bank.antalDokument(under: "/m/"), 2, "två dokument ur mappen")
            Prov.lika(bank.källor(under: "/m/").count, 2, "och två källor")
            try! bank.glöm(källa: "/m/a.docx")
            Prov.lika(bank.antalDokument(under: "/m/"), 1, "att glömma tar bort dokumentet")
            Prov.lika(bank.källor(under: "/m/").count, 1, "och källan, så att den läses på nytt om filen kommer tillbaka")

            // Lägesbilden vill ha de senast ändrade, ett stycke per fil.
            let gammalt = Date(timeIntervalSince1970: 1_000_000)
            let nytt = Date(timeIntervalSince1970: 2_000_000)
            try! bank.läggTill(titel: "gammal", text: "gammal text", typ: "dokument",
                               källa: "/m/gammal.pdf", tid: gammalt)
            try! bank.läggTill(titel: "ny (1)", text: "ny text", typ: "dokument",
                               källa: "/m/ny.pdf", tid: nytt)
            try! bank.läggTill(titel: "ny (2)", text: "mer ny text", typ: "dokument",
                               källa: "/m/ny.pdf", tid: nytt)
            try! bank.läggTill(titel: "inte dokument", text: "ett mejl", typ: "mejl",
                               källa: "/m/mejl.json", tid: nytt)
            let senaste = bank.senasteDokument(max: 5)
            Prov.lika(senaste.first?.källa, "/m/ny.pdf", "nyast ändrad först")
            Prov.lika(senaste.count, 2,
                      "ett stycke per fil; mejlet och ett dokument utan datum räknas inte")
            Prov.kolla(senaste.allSatisfy { $0.typ == "dokument" }, "bara dokument")
        }

        do {   // adresserna mejlen söks på
            let kontakter = [
                Kontakt(namn: "Anna", epost: ["Anna@Boras.example", "anna@boras.example"]),
                Kontakt(namn: "Bo", epost: ["bo@boras.example"]),
                Kontakt(namn: "Utan adress", epost: []),
                Kontakt(namn: "Trasig", epost: ["inte en adress"]),
                Kontakt(namn: "Cecilia", epost: ["cecilia@boras.example"]),
            ]
            let a = Mailen.adresser(ur: kontakter)
            Prov.lika(a, ["anna@boras.example", "bo@boras.example", "cecilia@boras.example"],
                      "kontakternas ordning behålls, skiftläge normaliseras, dubbletter bort")
            Prov.lika(Mailen.adresser(ur: kontakter, max: 2), ["anna@boras.example", "bo@boras.example"],
                      "gränsen tar de första, inte ett slumpat urval")
            Prov.lika(Mailen.adresser(ur: []), [], "utan kontakter finns inget att söka på")
        }

        do {   // en bättre läsare får sina filer lästa om, inte alla andra
            let rot = FileManager.default.temporaryDirectory
                .appending(path: "kundkoll-test-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: rot) }
            try! FileManager.default.createDirectory(at: rot, withIntermediateDirectories: true)
            let kund = Kund(namn: "Prov", mapp: rot)
            do {
                let bank = try! Kunskapsbank(kund: kund)
                try! bank.läggTill(titel: "x", text: "gammal läsning", typ: "dokument",
                                   källa: "/m/Risker.xlsx", tid: nil)
                try! bank.markeraIndexerad(URL(fileURLWithPath: "/m/Risker.xlsx"))
                try! bank.markeraIndexerad(URL(fileURLWithPath: "/m/Tom.docx"))
                try! bank.läggTill(titel: "y", text: "en pdf", typ: "dokument",
                                   källa: "/m/Avtal.pdf", tid: nil)
                try! bank.markeraIndexerad(URL(fileURLWithPath: "/m/Avtal.pdf"))
                // Låtsas att banken skrevs av en äldre version.
                let db = rot.appending(path: ".kundkoll/index.db")
                var h: OpaquePointer?
                sqlite3_open(db.path, &h)
                sqlite3_exec(h, "PRAGMA user_version = 1", nil, nil, nil)
                sqlite3_close(h)
            }
            let bank = try! Kunskapsbank(kund: kund)
            Prov.lika(bank.källor(under: "/m/").sorted(), ["/m/Avtal.pdf"],
                      "kontorsfilerna glöms så att de läses om, PDF:en står kvar")
            Prov.lika(bank.antalDokument(under: "/m/"), 1, "och deras gamla text är borta")
        }

        do {   // kontorsfiler: Excel cell för cell, PowerPoint i ordning, Words kommentarer
            let rot = FileManager.default.temporaryDirectory
                .appending(path: "kundkoll-test-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: rot) }
            let fm = FileManager.default
            func skriv(_ väg: String, _ innehåll: String) {
                let url = rot.appending(path: väg)
                try! fm.createDirectory(at: url.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
                try! innehåll.write(to: url, atomically: true, encoding: .utf8)
            }
            func packa(_ mapp: String, som namn: String) -> URL {
                let ut = rot.appending(path: namn)
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                p.currentDirectoryURL = rot.appending(path: mapp)
                p.arguments = ["-qr", ut.path, "."]
                p.standardOutput = FileHandle.nullDevice
                try! p.run()
                p.waitUntilExit()
                return ut
            }

            skriv("x/xl/workbook.xml",
                  #"<workbook><sheets><sheet name="Risker" sheetId="1" r:id="rId1"/></sheets></workbook>"#)
            skriv("x/xl/sharedStrings.xml",
                  "<sst><si><t>Risk</t></si><si><r><t>Åt</t></r><r><t>gärd</t></r></si>"
                  + "<si><t>Servern faller</t></si></sst>")
            skriv("x/xl/worksheets/sheet1.xml", """
                <worksheet><sheetData>
                <row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>
                <row r="2"><c r="A2" t="s"><v>2</v></c><c r="B2"><v>42</v></c>\
                <c r="C2" t="inlineStr"><is><t>inline</t></is></c></row>
                <row r="3"><c r="A3"/></row>
                </sheetData></worksheet>
                """)
            let xlsx = Kontorsfiler.text(ur: packa("x", som: "risker.xlsx"))
            Prov.lika(xlsx.text, "Blad: Risker\nRisk\tÅtgärd\nServern faller\t42\tinline",
                      "bladnamn, rader med tabb mellan cellerna, strängtabellen uppslagen, "
                      + "delad sträng ihopsatt, inline-sträng och tal med, tom rad borta")

            skriv("p/ppt/slides/slide2.xml", "<p:sld><a:t>Andra bilden</a:t></p:sld>")
            skriv("p/ppt/slides/slide10.xml", "<p:sld><a:t>Tionde</a:t></p:sld>")
            skriv("p/ppt/notesSlides/notesSlide2.xml", "<p:notes><a:t>Säg detta</a:t></p:notes>")
            let pptx = Kontorsfiler.text(ur: packa("p", som: "dragning.pptx")).text
            Prov.kolla(pptx.contains("Bild 2: Andra bilden\nTalarnotering: Säg detta"),
                       "bilden följs av sin talarnotering")
            let bild2 = pptx.range(of: "Bild 2:")?.lowerBound ?? pptx.endIndex
            let bild10 = pptx.range(of: "Bild 10:")?.lowerBound ?? pptx.startIndex
            Prov.kolla(bild2 < bild10, "bild 2 kommer före bild 10, inte lexikalt efter")

            skriv("d/word/document.xml", "<w:document><w:t>Brödtext &amp; mer</w:t></w:document>")
            skriv("d/word/comments.xml", "<w:comments><w:t>Invändning</w:t></w:comments>")
            skriv("d/word/settings.xml", "<w:settings><w:zoom w:percent=\"100\"/></w:settings>")
            let docx = Kontorsfiler.text(ur: packa("d", som: "underlag.docx")).text
            Prov.lika(docx, "Brödtext & mer\n\nKommentarer: Invändning",
                      "brödtext först, kommentarerna märkta, inställningarna borta, entiteten avkodad")

            Prov.lika(Kontorsfiler.nummer(i: "slide12.xml"), 12, "numret i filnamnet")
            Prov.lika(Kontorsfiler.avkoda("a &amp;lt; b"), "a &lt; b",
                      "&amp; avkodas sist, annars blir det två steg")
            Prov.kolla(Kontorsfiler.text(ur: rot.appending(path: "finns-inte.xlsx")).skäl != nil,
                       "en fil som inte går att packa upp får ett skäl")
        }

        do {   // «Hör inte till» måste vinna över domänregeln
            let kund = Kund(namn: "Borås stad", mapp: URL(fileURLWithPath: "/tmp/x"))
            let kontakter = [Kontakt(namn: "Philip", epost: ["philip@boras.example"])]
            let m = Kalendern.Möte(
                id: "m1", titel: "Curago Puls", start: Date(), slut: Date(),
                deltagare: [Kalendern.Deltagare(namn: "Helena", epost: "helena@boras.example", ärJag: false)],
                plats: nil, möteslänk: nil)
            Prov.kolla(Kalendern.hör(m, till: kund, kontakter: kontakter), "domänregeln tar mötet")
            Prov.kolla(Kalendern.hörTill(m, kund: kund, kontakter: kontakter, kopplingar: [:]),
                       "utan beslut gäller regeln")
            Prov.kolla(!Kalendern.hörTill(m, kund: kund, kontakter: kontakter,
                                          kopplingar: ["m1": Arkivet.uteslutetMöte]),
                       "uteslutet vinner över regeln")
            Prov.kolla(Kalendern.hörTill(m, kund: kund, kontakter: kontakter, kopplingar: ["m1": ""]),
                       "taget i anspråk vinner också")
            let annat = Kalendern.Möte(id: "m2", titel: "Lunch", start: Date(), slut: Date(),
                                       deltagare: [], plats: nil, möteslänk: nil)
            Prov.kolla(!Kalendern.hörTill(annat, kund: kund, kontakter: kontakter, kopplingar: [:]),
                       "ett möte utan spår hör inte hit")
            Prov.kolla(Kalendern.hörTill(annat, kund: kund, kontakter: kontakter,
                                         kopplingar: ["m2": "Projekt"]),
                       "om det inte tagits i anspråk")
        }

        do {   // lägesbilden bygger på dokument när inget annat finns
            let dok = Kunskapsbank.Träff(id: 1, typ: "dokument", titel: "AP2/DPIA.docx",
                                         text: "Bedömningen visar att behandlingen kräver DPIA.",
                                         källa: "/m/DPIA.docx", tid: Date(), poäng: 0)
            let bara = Läget.underlag(projekt: "M365", inspelningar: [], uppgifter: [],
                                      mejl: [], anteckningar: [], dokument: [dok])
            Prov.lika(bara.count, 1, "ett dokument räcker som underlag")
            Prov.kolla(bara.first?.text.contains("DPIA") == true, "och innehållet följer med")
            Prov.lika(Läget.underlag(projekt: "Tomt", inspelningar: [], uppgifter: [],
                                     mejl: [], anteckningar: [], dokument: []).count, 0,
                      "utan något alls blir det inget underlag")
        }

        do {   // samtal
            let rot = FileManager.default.temporaryDirectory
                .appending(path: "kundkoll-test-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: rot) }
            let arkiv = Arkivet(rot: rot)
            let kund = try! arkiv.skapaKund(namn: "Acme")
            let projekt = try! arkiv.skapaProjekt(namn: "Nytt lager", hos: kund)

            Prov.lika(arkiv.samtal(för: kund, projekt: nil).count, 0, "inga samtal från början")

            var ett = Samtal(projekt: nil, meddelanden: [
                .init(roll: .människa, text: "Vad kostade battericellerna?"),
                .init(roll: .assistent, text: "2 400 kr per enhet."),
            ])
            try! arkiv.spara(ett, för: kund)
            let sparade = arkiv.samtal(för: kund, projekt: nil)
            Prov.lika(sparade.count, 1, "samtalet sparas")
            Prov.lika(sparade.first?.titel, "Vad kostade battericellerna?",
                      "titeln härleds ur första frågan")

            // Ett andra samtal, och ett i projektet
            let två = Samtal(meddelanden: [.init(roll: .människa, text: "Vem är kontaktperson?")])
            try! arkiv.spara(två, för: kund)
            try! arkiv.spara(Samtal(projekt: "Nytt lager",
                                    meddelanden: [.init(roll: .människa, text: "Hur går bygget?")]),
                             för: kund)
            Prov.lika(arkiv.samtal(för: kund, projekt: nil).count, 2,
                      "kundens samtal är två")
            Prov.lika(arkiv.samtal(för: kund, projekt: "Nytt lager").count, 1,
                      "projektet ser bara sitt eget")
            _ = projekt

            // Nyast först, så att man landar i det man höll på med
            let ordning = arkiv.samtal(för: kund, projekt: nil)
            Prov.kolla((ordning.first?.ändrad ?? .distantPast) >= (ordning.last?.ändrad ?? .distantFuture),
                       "nyast först")

            ett.meddelanden.append(.init(roll: .människa, text: "Och volymrabatten?"))
            try! arkiv.spara(ett, för: kund)
            Prov.lika(arkiv.samtal(för: kund, projekt: nil).count, 2,
                      "att spara om ett samtal skapar inte ett nytt")
            Prov.lika(arkiv.samtal(för: kund, projekt: nil).first?.id, ett.id,
                      "det senast ändrade ligger överst")

            try! arkiv.taBort(två, för: kund)
            Prov.lika(arkiv.samtal(för: kund, projekt: nil).count, 1, "samtal går att ta bort")

            // Ett samtal om ett enskilt möte hör hemma i transkriptvyn och
            // ska inte dyka upp i kundens allmänna chatt.
            let mötesid = UUID().uuidString
            var omMötet = Samtal(möte: mötesid)
            omMötet.meddelanden = [.init(roll: .människa, text: "Vad sa vi om priset?")]
            try! arkiv.spara(omMötet, för: kund)
            Prov.lika(arkiv.samtal(för: kund, projekt: nil).count, 1,
                      "ett mötessamtal syns inte i kundens chatt")
            Prov.lika(arkiv.samtal(för: kund, projekt: nil, möte: mötesid).count, 1,
                      "men i mötets egen")
            Prov.lika(arkiv.samtal(för: kund, projekt: nil, möte: UUID().uuidString).count, 0,
                      "och inte i ett annat mötes")

            Prov.lika(Samtal.titel(ur: []), "Nytt samtal", "ett tomt samtal får ett namn ändå")
            let lång = String(repeating: "ord ", count: 40)
            Prov.kolla(Samtal.titel(ur: [.init(roll: .människa, text: lång)]).count <= 53,
                       "en lång fråga kapas till en läsbar titel")
        }

        do {   // en chatt från tiden före samtalen
            let rot = FileManager.default.temporaryDirectory
                .appending(path: "kundkoll-test-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: rot) }
            let arkiv = Arkivet(rot: rot)
            let kund = try! arkiv.skapaKund(namn: "Acme")

            // Så såg det ut när varje kund hade exakt en chatt
            let gammal = kund.mapp.appending(path: ".kundkoll/chatt.json")
            try! FileManager.default.createDirectory(
                at: gammal.deletingLastPathComponent(), withIntermediateDirectories: true)
            let meddelanden: [Chatt.Meddelande] = [
                .init(roll: .människa, text: "Vad sa vi om leveranstiden?"),
                .init(roll: .assistent, text: "Sex veckor."),
            ]
            try! JSONEncoder.kundkoll.encode(meddelanden).write(to: gammal)

            let samtal = arkiv.samtal(för: kund, projekt: nil)
            Prov.lika(samtal.count, 1, "den gamla chatten blir ett samtal")
            Prov.lika(samtal.first?.titel, "Vad sa vi om leveranstiden?", "med titel ur frågan")
            Prov.lika(samtal.first?.meddelanden.count, 2, "och alla meddelanden kvar")
            Prov.kolla(!FileManager.default.fileExists(atPath: gammal.path),
                       "den gamla filen städas bort efter flytten")
        }

        do {   // uppgifter
            let rot = FileManager.default.temporaryDirectory
                .appending(path: "kundkoll-test-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: rot) }
            let arkiv = Arkivet(rot: rot)
            let kund = try! arkiv.skapaKund(namn: "Acme")

            try! arkiv.läggTill([Uppgift(vad: "Skicka offert på pallställ", vem: "Anders",
                                         när: "före fredag", ursprung: .möte,
                                         källtitel: "Avstämning")], för: kund)
            Prov.lika(arkiv.uppgifter(för: kund).count, 1, "uppgiften sparas")

            // Samma sak nämns ofta i både ett möte och ett mejl
            try! arkiv.läggTill([Uppgift(vad: "Skicka offerten på pallställen",
                                         ursprung: .mejl)], för: kund)
            Prov.lika(arkiv.uppgifter(för: kund).count, 1,
                      "samma åtagande från två håll blir inte två kort")

            try! arkiv.läggTill([Uppgift(vad: "Boka möte om certifieringen")], för: kund)
            Prov.lika(arkiv.uppgifter(för: kund).count, 2, "något annat blir ett eget kort")

            var u = arkiv.uppgifter(för: kund).first!
            u.läge = .pågår
            try! arkiv.uppdatera(u, för: kund)
            Prov.lika(arkiv.uppgifter(för: kund).first?.läge, .pågår, "läget går att ändra")

            let not = try! String(contentsOf: kund.mapp.appending(path: "Att göra.md"),
                                  encoding: .utf8)
            Prov.kolla(not.contains("## Pågår"), "tavlan skrivs som markdown")
            Prov.kolla(not.contains("**Anders**"), "med vem som ska göra det")
            Prov.kolla(not.contains("*(före fredag)*"), "och när")

            try! arkiv.taBort(u, för: kund)
            Prov.lika(arkiv.uppgifter(för: kund).count, 1, "uppgifter går att ta bort")
        }

        do {   // likhet mellan uppgifter
            let a = Uppgift(vad: "Skicka offert på pallställ före fredag")
            Prov.kolla(a.liknar(Uppgift(vad: "Skicka offerten på pallställen på fredag")),
                       "samma sak i annan formulering känns igen")
            Prov.kolla(!a.liknar(Uppgift(vad: "Boka möte om certifieringen")),
                       "olika saker hålls isär")
            Prov.kolla(!a.liknar(Uppgift(vad: "")), "tom uppgift liknar inget")
        }

        do {   // samtal
            let rot = FileManager.default.temporaryDirectory
                .appending(path: "kundkoll-test-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: rot) }
            let arkiv = Arkivet(rot: rot)
            let kund = try! arkiv.skapaKund(namn: "Acme")
            let projekt = try! arkiv.skapaProjekt(namn: "Nytt lager", hos: kund)

            Prov.lika(arkiv.samtal(för: kund, projekt: nil).count, 0, "inga samtal från början")

            var ett = Samtal(projekt: nil, meddelanden: [
                .init(roll: .människa, text: "Vad kostade battericellerna?"),
                .init(roll: .assistent, text: "2 400 kr per enhet."),
            ])
            try! arkiv.spara(ett, för: kund)
            let sparade = arkiv.samtal(för: kund, projekt: nil)
            Prov.lika(sparade.count, 1, "samtalet sparas")
            Prov.lika(sparade.first?.titel, "Vad kostade battericellerna?",
                      "titeln härleds ur första frågan")

            // Ett andra samtal, och ett i projektet
            let två = Samtal(meddelanden: [.init(roll: .människa, text: "Vem är kontaktperson?")])
            try! arkiv.spara(två, för: kund)
            try! arkiv.spara(Samtal(projekt: "Nytt lager",
                                    meddelanden: [.init(roll: .människa, text: "Hur går bygget?")]),
                             för: kund)
            Prov.lika(arkiv.samtal(för: kund, projekt: nil).count, 2,
                      "kundens samtal är två")
            Prov.lika(arkiv.samtal(för: kund, projekt: "Nytt lager").count, 1,
                      "projektet ser bara sitt eget")
            _ = projekt

            // Nyast först, så att man landar i det man höll på med
            let ordning = arkiv.samtal(för: kund, projekt: nil)
            Prov.kolla((ordning.first?.ändrad ?? .distantPast) >= (ordning.last?.ändrad ?? .distantFuture),
                       "nyast först")

            ett.meddelanden.append(.init(roll: .människa, text: "Och volymrabatten?"))
            try! arkiv.spara(ett, för: kund)
            Prov.lika(arkiv.samtal(för: kund, projekt: nil).count, 2,
                      "att spara om ett samtal skapar inte ett nytt")
            Prov.lika(arkiv.samtal(för: kund, projekt: nil).first?.id, ett.id,
                      "det senast ändrade ligger överst")

            try! arkiv.taBort(två, för: kund)
            Prov.lika(arkiv.samtal(för: kund, projekt: nil).count, 1, "samtal går att ta bort")

            Prov.lika(Samtal.titel(ur: []), "Nytt samtal", "ett tomt samtal får ett namn ändå")
            let lång = String(repeating: "ord ", count: 40)
            Prov.kolla(Samtal.titel(ur: [.init(roll: .människa, text: lång)]).count <= 53,
                       "en lång fråga kapas till en läsbar titel")
        }

        do {   // en chatt från tiden före samtalen
            let rot = FileManager.default.temporaryDirectory
                .appending(path: "kundkoll-test-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: rot) }
            let arkiv = Arkivet(rot: rot)
            let kund = try! arkiv.skapaKund(namn: "Acme")

            // Så såg det ut när varje kund hade exakt en chatt
            let gammal = kund.mapp.appending(path: ".kundkoll/chatt.json")
            try! FileManager.default.createDirectory(
                at: gammal.deletingLastPathComponent(), withIntermediateDirectories: true)
            let meddelanden: [Chatt.Meddelande] = [
                .init(roll: .människa, text: "Vad sa vi om leveranstiden?"),
                .init(roll: .assistent, text: "Sex veckor."),
            ]
            try! JSONEncoder.kundkoll.encode(meddelanden).write(to: gammal)

            let samtal = arkiv.samtal(för: kund, projekt: nil)
            Prov.lika(samtal.count, 1, "den gamla chatten blir ett samtal")
            Prov.lika(samtal.first?.titel, "Vad sa vi om leveranstiden?", "med titel ur frågan")
            Prov.lika(samtal.first?.meddelanden.count, 2, "och alla meddelanden kvar")
            Prov.kolla(!FileManager.default.fileExists(atPath: gammal.path),
                       "den gamla filen städas bort efter flytten")
        }

        do {   // uppgifter ur modellens JSON
            let json = """
            {"uppgifter": [
              {"vad": "Skicka ritningar", "vem": "Anders", "när": "på måndag"},
              {"vad": "Kolla priset", "vem": null, "när": null},
              {"vad": "kort", "vem": null, "när": null}
            ]}
            """
            let u = Uppgiftsletare.tolka(json) ?? []
            Prov.lika(u.count, 2, "för korta rader sorteras bort")
            Prov.lika(u.first?.vem, "Anders", "vem tolkas")
            Prov.kolla(u.last?.vem == nil, "null blir nil")
            Prov.kolla(Uppgiftsletare.tolka("inget här") == nil, "text utan JSON är otolkbart, inte «inga uppgifter»")
            Prov.lika(Uppgiftsletare.tolka("{\"uppgifter\": []}")?.count, 0, "en tom lista är ett riktigt svar")

            let ikodruta = "Här kommer de:\n```json\n" + json + "\n```"
            Prov.lika(Uppgiftsletare.tolka(ikodruta)?.count, 2, "JSON i kodruta tolkas")
        }

        do {   // gamla filer utan nya fält
            // Det här var en verklig bugg: fältet "text" lades till på Mejl,
            // och då slutade alla tidigare sparade mail.json gå att läsa —
            // tyst, eftersom felet bara syntes som att ingenting hände.
            let gammalt = """
            {"hämtad": "2026-08-31T19:43:13Z",
             "mejl": [{"datumText": "Monday, 3 August 2026 at 09:00:00",
                       "avsändare": "Anna <anna@acme.se>", "ämne": "Offert",
                       "meddelandeID": "<a@x>", "konto": "k", "låda": "INBOX",
                       "riktning": "fran"}]}
            """
            let cache = try? JSONDecoder.kundkoll.decode(
                Arkivet.Mailcache.self, from: Data(gammalt.utf8))
            Prov.kolla(cache != nil, "en mailcache utan bilagor och brödtext går att läsa")
            Prov.kolla(cache?.hämtad != nil, "datum utan sekundbråk går fortfarande att läsa")
            Prov.lika(cache?.mejl.count, 1, "mejlen kommer med")
            Prov.lika(cache?.mejl.first?.text, "", "brödtexten blir tom i stället för att fälla")
            Prov.lika(cache?.bilagor.count, 0, "bilagorna blir en tom lista")

            let gammalInspelning = """
            {"titel": "Avstämning", "inledd": "2026-08-31T19:43:13Z", "längd": 120,
             "kund": "Acme", "liveYttranden": []}
            """
            let i = try? JSONDecoder.kundkoll.decode(
                Inspelning.self, from: Data(gammalInspelning.utf8))
            Prov.kolla(i != nil, "en inspelning utan de senaste fälten går att läsa")
            Prov.lika(i?.titel, "Avstämning", "titeln kommer med")
            Prov.lika(i?.enspårig, false, "enspårig får sitt standardvärde")
            Prov.lika(i?.kallade.count, 0, "kallade blir tom")
            Prov.kolla(i?.sammanfattning == nil, "sammanfattningen blir nil")

            let gammalKontakt = """
            {"namn": "Anna Svensson"}
            """
            let k = try? JSONDecoder.kundkoll.decode(Kontakt.self, from: Data(gammalKontakt.utf8))
            Prov.lika(k?.namn, "Anna Svensson", "en kontakt med bara namn går att läsa")
            Prov.lika(k?.epost.count, 0, "adresserna blir en tom lista")
        }

        do {   // brödtext ur mejl
            let d = "\u{1F}"
            let rad = "Monday, 3 August 2026 at 09:00:00\(d)Anna <anna@acme.se>\(d)Offert\(d)<a@x>\(d)konto\(d)INBOX\(d)fran\(d)Hej! Här kommer offerten på pallställ."
            let m = Mailen.tolka(rad).first
            Prov.lika(m?.text, "Hej! Här kommer offerten på pallställ.",
                      "brödtexten kommer med")

            // Citerade svar och signaturer klipps: de finns redan indexerade
            // var för sig och skulle bara fylla banken.
            Prov.lika(Mailen.städaBrödtext("Nytt svar här.\n\nFrån: Anna\nGammalt svar"),
                      "Nytt svar här.", "citat klipps bort")
            Prov.lika(Mailen.städaBrödtext("Kort svar.\nSkickat från min iPhone"),
                      "Kort svar.", "signaturer klipps bort")
            Prov.lika(Mailen.städaBrödtext("  Bara text.  "), "Bara text.",
                      "blanksteg trimmas")

            let utan = "Monday, 3 August 2026 at 09:00:00\(d)A <a@x.se>\(d)Ämne\(d)<b@x>\(d)konto\(d)INBOX\(d)fran"
            Prov.lika(Mailen.tolka(utan).first?.text, "",
                      "äldre rader utan brödtext tolkas ändå")
        }

        do {   // sammanfattningens JSON
            let json = """
            {"kärna": "Genomgång av lagerprojektet.",
             "beslut": ["Offert före fredag"],
             "åtaganden": [{"vad": "Skicka ritningar", "vem": "Anders", "när": "på måndag"},
                           {"vad": "Kolla pris", "vem": null, "när": null}],
             "öppet": ["Vem betalar frakten?"]}
            """
            let s = Sammanfattare.tolka(json)
            Prov.lika(s?.kärna, "Genomgång av lagerprojektet.", "kärnan tolkas")
            Prov.lika(s?.beslut.count, 1, "beslut tolkas")
            Prov.lika(s?.åtaganden.count, 2, "åtaganden tolkas")
            Prov.lika(s?.åtaganden.first?.vem, "Anders", "vem som ska göra det")
            Prov.lika(s?.åtaganden.first?.när, "på måndag", "och när")
            Prov.kolla(s?.åtaganden.last?.vem == nil, "null blir nil, inte strängen null")
            Prov.lika(s?.öppet.count, 1, "öppna frågor tolkas")
            Prov.kolla(!(s?.tom ?? true), "en ifylld sammanfattning är inte tom")

            // Modeller lägger gärna JSON i en kodruta och skriver en rad före
            let ikodruta = "Här är sammanfattningen:\n\n```json\n" + json + "\n```"
            Prov.kolla(Sammanfattare.tolka(ikodruta) != nil, "JSON i kodruta tolkas")
            Prov.lika(Sammanfattare.tolka(ikodruta)?.beslut.count, 1, "och innehållet kommer med")

            Prov.kolla(Sammanfattare.tolka("inget här") == nil, "text utan JSON ger nil")
            let tom = Sammanfattare.tolka("""
            {"kärna": "", "beslut": [], "åtaganden": [], "öppet": []}
            """)
            Prov.kolla(tom?.tom == true, "en sammanfattning utan innehåll räknas som tom")
        }

        do {   // markdown i svaren
            let block = Markdowntext.tolka("""
            Här är vad som sades:

            - Cell Sourcing Platform beskrivs som en av punkterna [4]
            - Man får tillbaka inspect sheets

            1. Tidsfönstret
            2. Gruppstorlek

            # Sammanfattning

            Sista stycket.
            """)
            Prov.kolla(block.contains(.punkt("Cell Sourcing Platform beskrivs som en av punkterna [4]", nivå: 0)),
                       "bindestreckslistor blir punkter")
            Prov.kolla(block.contains(.numrerad(1, "Tidsfönstret", nivå: 0)),
                       "numrerade listor behåller sina nummer")
            Prov.kolla(block.contains(.rubrik("Sammanfattning")), "rubriker känns igen")
            Prov.kolla(block.contains(.stycke("Sista stycket.")), "vanliga stycken kommer med")

            // Rader i samma stycke slås ihop, tomrad bryter
            let ihop = Markdowntext.tolka("En rad\noch en till\n\nNytt stycke")
            Prov.lika(ihop, [.stycke("En rad och en till"), .stycke("Nytt stycke")],
                      "radbrytning inom ett stycke blir mellanslag")

            Prov.lika(Markdowntext.tolka("").count, 0, "tom text ger inga block")
            Prov.lika(Markdowntext.tolka("bara text"), [.stycke("bara text")],
                      "text utan markdown blir ett stycke")

            // Ett indraget listelement hamnar en nivå in
            let indrag = Markdowntext.tolka("- överst\n  - inunder")
            Prov.kolla(indrag.contains(.punkt("inunder", nivå: 1)), "indrag ger en nivå")
        }

        do {   // nyckelringen
            let konto = "kundkoll-prov-\(UUID().uuidString)"
            defer { Nyckelring.spara("", som: konto) }
            Prov.kolla(Nyckelring.hämta(konto) == nil, "ingen nyckel från början")
            Prov.kolla(Nyckelring.spara("hemlig-nyckel", som: konto), "nyckeln går att spara")
            Prov.lika(Nyckelring.hämta(konto), "hemlig-nyckel", "och att läsa tillbaka")
            Prov.kolla(Nyckelring.spara("", som: konto), "en tom nyckel tar bort posten")
            Prov.kolla(Nyckelring.hämta(konto) == nil, "och då finns den inte längre")
        }
    }
}

import Foundation

extension Tester {
    static func whisper() {
        Prov.svit("Whisper")

        do {   // tolkning
            let json = """
            {"transcription":[
              {"text":" Hej allihopa.","offsets":{"from":0,"to":2400}},
              {"text":" Välkomna till mötet.","offsets":{"from":2400,"to":5100}}
            ]}
            """.data(using: .utf8)!
            let rader = Whisper.tolka(json, röst: .motpart, förskjutning: 10)
            Prov.lika(rader.count, 2, "båda raderna tolkas")
            Prov.lika(rader.first?.text, "Hej allihopa.", "inledande blanksteg tas bort")
            Prov.lika(rader.first?.start, 10, "millisekunder blir sekunder plus förskjutning")
            Prov.lika(rader.first?.slut, 12.4, "sluttiden räknas om likadant")
            Prov.kolla(rader.allSatisfy { $0.röst == .motpart }, "rösten följer med spåret")
        }

        do {   // tomt ljud
            for t in ["", "[Musik]", "(skratt)", ".", " ... "] {
                Prov.kolla(Whisper.ärTomtLjud(t), "«\(t)» sorteras bort som tystnad")
            }
            // Fraserna whisper hittar på ur tystnad
            for t in ["Tack.", "Tack för hjälpen.", "Tack så mycket", "Textning av",
                      "Thank you.", "Hej då"] {
                Prov.kolla(Whisper.ärTomtLjud(t), "påhittet «\(t)» sorteras bort")
            }
            for t in ["Tack för mötet.", "Ja.", "Tack för att du tog dig tid att titta på ritningen."] {
                Prov.kolla(!Whisper.ärTomtLjud(t), "«\(t)» behålls")
            }
            let json = """
            {"transcription":[
              {"text":" [Musik]","offsets":{"from":0,"to":1000}},
              {"text":" Riktig text.","offsets":{"from":1000,"to":2000}}
            ]}
            """.data(using: .utf8)!
            Prov.lika(Whisper.tolka(json, röst: .jag, förskjutning: 0).count, 1,
                      "påhittade rader tas bort redan vid tolkningen")
        }

        do {   // loopar
            Prov.kolla(Whisper.ärLoop("Ett stort stort stort stort stort stelt"),
                       "samma ord fyra gånger i rad är en modell som fastnat")
            Prov.kolla(Whisper.ärLoop("ja ja ja ja ja ja ja ja"),
                       "en lång ramsa av ett enda ord likaså")
            Prov.kolla(!Whisper.ärLoop("Ja, ja, det stämmer nog."),
                       "ett upprepat ord i normalt tal är inte en loop")
            Prov.kolla(!Whisper.ärLoop("Vi ska titta på lagret och sedan gå igenom offerten i lugn och ro."),
                       "vanliga meningar passerar")
            Prov.kolla(Whisper.ärTomtLjud("Ett stort stort stort stort stort stelt"),
                       "loopar sorteras bort som tomt ljud")
        }

        do {   // VAD-flaggor
            let flaggor = Whisper.vadflaggor(.standard)
            Prov.kolla(flaggor.contains("--vad"), "taldetektering slås på")
            Prov.kolla(flaggor.contains { $0.hasSuffix("ggml-silero-v5.1.2.bin") },
                       "Silero-modellen pekas ut")
        }

        do {   // framsteg ur whispers utskrift
            Prov.lika(Whisper.tid(ur: "00:01:30.080"), 90.08, "tidsstämpeln tolkas")
            Prov.lika(Whisper.tid(ur: "01:00:00.000"), 3600, "timmar räknas med")
            Prov.kolla(Whisper.tid(ur: "skräp") == nil, "skräp ger nil")

            var buffert = "[00:00:00.000 --> 00:00:04.500]  Hej allihopa.[00:00:04.500 --> 00:00:09.000]  Välkomna."
            let första = Whisper.nästaSegment(&buffert)
            Prov.lika(första?.slut, 4.5, "första segmentets sluttid")
            Prov.lika(första?.text, "Hej allihopa.", "och dess text")
            Prov.kolla(buffert.hasPrefix("[00:00:04.500"), "det lästa tas bort ur bufferten")

            // Ett halvt segment ska vänta på mer data i stället för att tolkas fel
            var halvt = "[00:00:09.000 --> 00:00:12.000]  Ofull"
            Prov.kolla(Whisper.nästaSegment(&halvt) == nil,
                       "ett ofullständigt segment lämnas kvar tills resten kommit")
            Prov.kolla(halvt.contains("Ofull"), "och texten går inte förlorad")

            var tom = ""
            Prov.kolla(Whisper.nästaSegment(&tom) == nil, "tom buffert kraschar inte")
        }

        do {   // ledig port
            let a = try! Whisper.ledigPort()
            Prov.kolla(a > 1024, "en ledig port hittas (\(a))")
            let s = socket(AF_INET, SOCK_STREAM, 0)
            defer { close(s) }
            var adr = sockaddr_in()
            adr.sin_family = sa_family_t(AF_INET)
            adr.sin_port = UInt16(a).bigEndian
            adr.sin_addr.s_addr = inet_addr("127.0.0.1")
            let r = withUnsafePointer(to: &adr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            Prov.lika(r, 0, "porten går verkligen att binda")
        }

        do {   // brister upptäcks
            let trasig = Whisper.Sökvägar(rot: URL(fileURLWithPath: "/finns/inte"),
                                          livemodell: "a.bin", arkivmodell: "b.bin",
                                          vadmodell: "c.bin")
            Prov.lika(trasig.brister.count, 5, "saknade binärer och modeller upptäcks")
            let riktig = Whisper.Sökvägar.standard
            if FileManager.default.fileExists(atPath: riktig.rot.path) {
                Prov.kolla(riktig.brister.isEmpty,
                           "den riktiga whisper.cpp-uppsättningen är komplett\(riktig.brister.isEmpty ? "" : ": \(riktig.brister)")")
            }
        }
    }
}

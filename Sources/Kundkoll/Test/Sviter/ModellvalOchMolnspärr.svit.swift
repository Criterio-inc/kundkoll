import Foundation

extension Tester {
    static func modellvalOchMolnspärr() {
        Prov.svit("Modellval och molnspärr")

        do {   // standard och adress
            let standard = Modellval()
            Prov.lika(standard.leverantör, .lokal, "lokalt är standard, inte ett moln")
            Prov.kolla(standard.ärLokalAdress, "standardadressen pekar på datorn")
            Prov.kolla(!standard.lämnarDatorn, "och lämnar den inte")
            Prov.lika(standard.etikett, "Lokalt · qwen3:8b", "etiketten säger var och vad")

            let ute = Modellval(leverantör: .lokal, modell: "x", adress: "https://api.groq.com/v1/chat/completions")
            Prov.kolla(!ute.ärLokalAdress, "«Lokal modell» med en adress på nätet räknas inte som lokal")
            Prov.lika(ute.etikett, "Lokal modell · x", "och etiketten döljer det inte")
            let moln = Modellval(leverantör: .anthropic)
            Prov.kolla(moln.lämnarDatorn, "Anthropic lämnar datorn")
            Prov.lika(moln.lokalBas, nil, "ett moln har ingen lokal server")
            Prov.lika(Modellval(leverantör: .lokal, adress: "http://192.168.1.5:11434/v1/chat/completions").lokalBas?.absoluteString,
                      "http://192.168.1.5:11434", "insikter och inbäddning följer adressen under Lokal modell")
            Prov.lika(moln.etikett, "Anthropic · claude-sonnet-5", "molnets etikett")

            // En sparad inställning utan leverantör (äldre fil) ska bli lokal.
            let gammal = try! JSONDecoder().decode(Modellval.self, from: Data("{\"modell\":\"m\"}".utf8))
            Prov.lika(gammal.leverantör, .lokal, "saknat fält faller tillbaka på lokalt")
        }

        do {   // automatik får inte lämna datorn
            // Provsviten är synkron; anropet körs vid sidan av och väntas in.
            func felText(_ val: Modellval) -> String {
                let sem = DispatchSemaphore(value: 0)
                nonisolated(unsafe) var text = ""
                Task.detached {
                    do {
                        _ = try await Chatt(val: val).fråga("hej", om: "Acme", projekt: nil,
                                                             träffar: [], historik: [], automatiskt: true)
                    } catch { text = error.localizedDescription }
                    sem.signal()
                }
                sem.wait()
                return text
            }
            let moln = felText(Modellval(leverantör: .anthropic))
            Prov.kolla(moln.contains("körs bara på datorn"),
                       "ett automatiskt uppdrag mot ett moln stoppas innan något skickas: \(moln.prefix(60))")
            let lokal = felText(Modellval(leverantör: .lokal, adress: "http://127.0.0.1:1/v1/chat/completions"))
            Prov.kolla(!lokal.contains("körs bara på datorn"),
                       "ett lokalt val släpps förbi spärren (föll i stället på: \(lokal.prefix(40)))")
        }
    }
}

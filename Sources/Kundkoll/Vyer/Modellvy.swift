import SwiftUI

/// Väljer var chattens modell körs och lägger in nyckeln.
///
/// Bara chatten går ut på nätet. Transkribering och röstanalys körs alltid på
/// datorn, oavsett vad som väljs här.
struct Modellvy: View {
    @Environment(\.dismiss) private var stäng

    @State private var val = Modellval.läs()
    @State private var nyckel = ""
    @State private var harNyckel = false
    @State private var meddelande: String?
    @State private var provar = false
    @State private var insiktsmodell = Inställningar.insiktsmodell
    @State private var delaRöster = Inställningar.delaRöstprofiler
    @State private var användarnamn = UserDefaults.standard.string(forKey: "kundkoll.användarnamn") ?? ""
    /// Modellerna Ollama faktiskt har, så att ingen behöver gissa ett namn.
    @State private var ollamaModeller: [String] = []
    @State private var transkribering = Transkriberingsval.läs()
    @State private var elevenNyckel = ""
    @State private var harElevenNyckel = Nyckelring.hämta("kundkoll-elevenlabs") != nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Modell för kundchatten").font(.headline)
                Spacer()
            }
            .padding(16)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("Kör hos", selection: $val.leverantör) {
                        ForEach(Leverantör.allCases) { l in Text(l.namn).tag(l) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: val.leverantör) { _, ny in
                        val.modell = ny.standardmodell
                        val.adress = ny.behöverEgenAdress ? ny.standardadress : ""
                        läsNyckel()
                        meddelande = nil
                    }

                    Text(val.leverantör.beskrivning)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if val.leverantör != .azure {
                        fält("Modell") {
                            TextField(val.leverantör.standardmodell, text: $val.modell)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    if val.leverantör.behöverEgenAdress {
                        fält("Adress") {
                            TextField(val.leverantör.standardadress, text: $val.adress)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        }
                    }

                    if val.leverantör == .lokal {
                        // De tre vanliga lokala servrarna talar alla
                        // OpenAI-formatet men lyssnar på olika portar.
                        // Knapparna fyller i adressen; modellnamnet är det
                        // som står i serverns egen lista.
                        fält("Vanliga servrar") {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    förval("Ollama", port: 11434, modell: nil)
                                    förval("LM Studio", port: 1234, modell: nil)
                                    förval("MLX", port: 8080, modell: nil)
                                }
                                if !ollamaModeller.isEmpty {
                                    Picker("Modell i Ollama", selection: $val.modell) {
                                        ForEach(ollamaModeller, id: \.self) { Text($0).tag($0) }
                                    }
                                }
                                if val.adress.contains(":8080") {
                                    Text("MLX startas med `mlx_lm.server --model "
                                         + "mlx-community/…` och modellfältet ska "
                                         + "vara samma namn.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .task(id: val.adress) { await hämtaOllamaModeller() }
                        }
                    }

                    if val.leverantör.behöverNyckel {
                        fält(harNyckel ? "API-nyckel (sparad)" : "API-nyckel") {
                            VStack(alignment: .leading, spacing: 6) {
                                SecureField(harNyckel ? "•••••••• — skriv en ny för att byta" : "Klistra in nyckeln",
                                            text: $nyckel)
                                    .textFieldStyle(.roundedBorder)
                                if let var_ = val.leverantör.nyckeladress {
                                    Text("Hämtas på \(var_)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } else {
                        Label("Ingen nyckel behövs. Materialet lämnar aldrig datorn.",
                              systemImage: "lock")
                            .font(.callout)
                            .foregroundStyle(.green)
                    }

                    Divider().padding(.vertical, 4)

                    fält("Transkribering av färdiga möten") {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("", selection: $transkribering.motor) {
                                ForEach(Transkriberingsmotor.allCases) { m in
                                    Text(m.namn).tag(m)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .onChange(of: transkribering.motor) { transkribering.modell = "" }

                            Text(transkribering.motor.beskrivning)
                                .font(.caption)
                                .foregroundStyle(transkribering.motor.lokal ? Color.secondary : Color.orange)
                                .fixedSize(horizontal: false, vertical: true)

                            if transkribering.motor == .whisperCpp {
                                Picker("Modell", selection: bindningArkivmodell) {
                                    ForEach(Transkriberingsval.lokalaModeller(), id: \.self) { m in
                                        Text(m.replacingOccurrences(of: ".bin", with: "")).tag(m)
                                    }
                                }
                            } else {
                                TextField(transkribering.motor.standardmodell,
                                          text: $transkribering.modell)
                                    .textFieldStyle(.roundedBorder)
                            }

                            if transkribering.motor == .elevenlabs {
                                SecureField(harElevenNyckel
                                            ? "•••••••• — skriv en ny för att byta"
                                            : "API-nyckel från elevenlabs.io",
                                            text: $elevenNyckel)
                                    .textFieldStyle(.roundedBorder)
                            }
                            if transkribering.motor == .openai {
                                Text(Transkriberingsmotor.openai.nyckel == nil
                                     ? "Använder OpenAI-nyckeln från chatten — lägg in en under OpenAI ovan."
                                     : "Använder OpenAI-nyckeln som redan finns.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let brist = Arkivtranskribering.brister(transkribering).first,
                               !(transkribering.motor == .elevenlabs && !elevenNyckel.isEmpty) {
                                Label(brist, systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }

                    fält("Livetranskribering — alltid lokal") {
                        VStack(alignment: .leading, spacing: 6) {
                            Picker("", selection: $transkribering.livemodell) {
                                ForEach(Transkriberingsval.lokalaModeller(), id: \.self) { m in
                                    Text(m.replacingOccurrences(of: ".bin", with: "")).tag(m)
                                }
                            }
                            .labelsHidden()
                            Text("Fönstren under ett samtal är sekunder långa och går genom "
                                 + "whisper-server som håller modellen varm. Gäller från nästa "
                                 + "inspelning.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Divider().padding(.vertical, 4)

                    fält("Modell för insikter under samtal") {
                        VStack(alignment: .leading, spacing: 6) {
                            TextField(Insikter.standardmodell, text: $insiktsmodell)
                                .textFieldStyle(.roundedBorder)
                            Text("Körs lokalt via Ollama och lyssnar efter frågeställningar medan ett möte pågår. Uppmätt: qwen3:8b 12 av 12 rätt utan falska larm, gemma3:4b 11 av 12, gemma3:1b 7 av 12.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Toggle("Känn igen röster mellan kunder", isOn: $delaRöster)
                        .help("Av som standard: röstprofiler ligger hos kunden, och samma person kan förekomma i flera kundärenden utan att man vill koppla ihop dem.")

                    Divider().padding(.vertical, 4)

                    fält("Ditt namn") {
                        VStack(alignment: .leading, spacing: 6) {
                            TextField(NSFullUserName(), text: $användarnamn)
                                .textFieldStyle(.roundedBorder)
                            Text("Så tilltalar chatten dig. Tomt betyder namnet på macOS-kontot.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let meddelande {
                        Text(meddelande)
                            .font(.callout)
                            .foregroundStyle(meddelande.hasPrefix("Fungerar") ? .green : .orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
            }

            Divider()
            HStack {
                Button("Prova", action: prova)
                    .disabled(provar)
                if provar { ProgressView().controlSize(.small) }
                Spacer()
                Button("Avbryt") { stäng() }
                Button("Spara", action: spara).keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 520, height: 560)
        .onAppear(perform: läsNyckel)
    }

    /// En knapp som fyller i adressen för en känd lokal server.
    private func förval(_ namn: String, port: Int, modell: String?) -> some View {
        let adress = "http://127.0.0.1:\(port)/v1/chat/completions"
        return Button(namn) {
            val.adress = adress
            if let modell { val.modell = modell }
            meddelande = nil
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(val.adress == adress ? Color.accentColor : Color.secondary)
    }

    /// Frågar Ollama vilka modeller som finns i stället för att gissa på en
    /// som kanske inte är hämtad — uppmätt: «model 'llama3.1:8b' not found»
    /// på en dator som hade qwen3. Inbäddningsmodeller (bge-m3,
    /// nomic-embed-text) sållas bort; de kan inte föra samtal.
    private func hämtaOllamaModeller() async {
        guard val.leverantör == .lokal, val.adress.contains(":11434"),
              let url = URL(string: val.adress
                .replacingOccurrences(of: "/v1/chat/completions", with: "/api/tags"))
        else { ollamaModeller = []; return }
        var r = URLRequest(url: url)
        r.timeoutInterval = 2
        guard let (data, _) = try? await URLSession.shared.data(for: r),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rader = json["models"] as? [[String: Any]]
        else { ollamaModeller = []; return }
        let namn: [String] = rader.compactMap { m in
            guard let n = m["name"] as? String else { return nil }
            let familj = ((m["details"] as? [String: Any])?["family"] as? String) ?? ""
            if familj.contains("bert") || n.contains("embed") || n.hasPrefix("bge") { return nil }
            return n
        }.sorted()
        ollamaModeller = namn
        if !namn.isEmpty, !namn.contains(val.modell) { val.modell = namn[0] }
    }

    /// whisper.cpp-väljaren skriver tomt när standarden valts, så att en
    /// framtida standardhöjning slår igenom av sig själv.
    private var bindningArkivmodell: Binding<String> {
        Binding(get: { transkribering.arkivmodell },
                set: { transkribering.modell =
                    $0 == transkribering.motor.standardmodell ? "" : $0 })
    }

    private func fält<I: View>(_ rubrik: String, @ViewBuilder _ innehåll: () -> I) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(rubrik).font(.subheadline.weight(.medium))
            innehåll()
        }
    }

    private func läsNyckel() {
        harNyckel = Nyckelring.förLeverantör(val.leverantör) != nil
        nyckel = ""
    }

    private func sparaNyckel() {
        let ren = nyckel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ren.isEmpty else { return }
        Nyckelring.spara(ren, som: val.leverantör.nyckelkonto)
        harNyckel = true
        nyckel = ""
    }

    private func spara() {
        sparaNyckel()
        val.spara()
        transkribering.spara()
        if !elevenNyckel.isEmpty {
            Nyckelring.spara(elevenNyckel.trimmingCharacters(in: .whitespaces),
                             som: "kundkoll-elevenlabs")
        }
        let ren = insiktsmodell.trimmingCharacters(in: .whitespacesAndNewlines)
        Inställningar.insiktsmodell = ren.isEmpty ? Insikter.standardmodell : ren
        Inställningar.delaRöstprofiler = delaRöster
        Inställningar.användarnamn = användarnamn.trimmingCharacters(in: .whitespacesAndNewlines)
        stäng()
    }

    /// Ett riktigt anrop, för att felet ska visa sig här och inte mitt i en fråga.
    private func prova() {
        sparaNyckel()
        val.spara()
        provar = true
        meddelande = nil
        Task {
            let chatt = Chatt(val: val)
            do {
                let svar = try await chatt.fråga(
                    "Svara med ordet klart.", om: "prov", projekt: nil,
                    träffar: [], historik: [])
                meddelande = "Fungerar. Modellen svarade: \(svar.text.prefix(60))"
            } catch {
                meddelande = error.localizedDescription
            }
            provar = false
        }
    }
}

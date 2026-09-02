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
                                    förval("Ollama", port: 11434, modell: "llama3.1:8b")
                                    förval("LM Studio", port: 1234, modell: nil)
                                    förval("MLX", port: 8080, modell: nil)
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
        let ren = insiktsmodell.trimmingCharacters(in: .whitespacesAndNewlines)
        Inställningar.insiktsmodell = ren.isEmpty ? Insikter.standardmodell : ren
        Inställningar.delaRöstprofiler = delaRöster
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

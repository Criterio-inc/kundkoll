import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Tar in en färdig ljud- eller videofil som en inspelning.
struct Importvy: View {
    let kund: Kund
    let projekt: [Projekt]
    /// Fil som redan valts, till exempel genom att släppas på fönstret.
    var förvald: URL?
    /// Projektet som är öppet när importen startas — förvalt i väljaren.
    var förvaltProjekt: Projekt?
    var vidKlar: () -> Void

    @EnvironmentObject private var arkiv: Arkivet
    @Environment(\.dismiss) private var stäng

    init(kund: Kund, projekt: [Projekt], förvald: URL? = nil,
         förvaltProjekt: Projekt? = nil, vidKlar: @escaping () -> Void) {
        self.kund = kund
        self.projekt = projekt
        self.förvald = förvald
        self.förvaltProjekt = förvaltProjekt
        self.vidKlar = vidKlar
        _valtProjekt = State(initialValue: förvaltProjekt)
    }

    @State private var fil: URL?
    @State private var titel = ""
    @State private var valtProjekt: Projekt?
    /// "sv", "en" eller nil — motorn avgör själv.
    @State private var språk: String? = "sv"

    @State private var läge: Läge = .väljer
    @State private var steg = ""
    @State private var andel: Double?
    @State private var senaste = ""
    @State private var start = Date()

    private enum Läge: Equatable { case väljer, arbetar, klar(String), fel(String) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Lägg till en inspelning").font(.headline)
                Spacer()
            }
            .padding(16)
            Divider()

            switch läge {
            case .väljer: väljare
            case .arbetar: arbetar
            case .klar(let namn): klar(namn)
            case .fel(let text): felruta(text)
            }
        }
        .frame(width: 560, height: 420)
        .onAppear {
            if let förvald { välj(förvald) }
        }
    }

    private var väljare: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button {
                väljFil()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: fil == nil ? "waveform.badge.plus" : "waveform")
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fil?.lastPathComponent ?? "Välj ljud- eller videofil")
                            .lineLimit(1)
                        Text(fil == nil
                             ? "Mötesinspelning från Teams eller Zoom, telefonsamtal, diktafon"
                             : "Klicka för att byta")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            Form {
                TextField("Vad gäller inspelningen?", text: $titel)
                Picker("Hör till", selection: $valtProjekt) {
                    Text(kund.namn).tag(Projekt?.none)
                    ForEach(projekt) { p in Text(p.namn).tag(Projekt?.some(p)) }
                }
                Picker("Språk", selection: $språk) {
                    Text("Svenska").tag(String?.some("sv"))
                    Text("Engelska").tag(String?.some("en"))
                    Text("Avgör själv").tag(String?.none)
                }
                .help("KB-Whisper är svensktrimmad och översätter engelska till "
                      + "svenska — för engelska möten tar transkriberingen vägen "
                      + "via MLX eller den valda molnmotorn.")
            }
            .formStyle(.grouped)

            Label("Hela ljudet ligger i ett spår, så rösterna delas upp av röstanalysen i stället för av kanalerna. En av dem kan vara du.",
                  systemImage: "person.wave.2")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
            HStack {
                Button("Avbryt") { stäng() }
                Spacer()
                Button("Lägg till", action: kör)
                    .keyboardShortcut(.defaultAction)
                    .disabled(fil == nil)
            }
        }
        .padding(24)
    }

    private var arbetar: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer()
            HStack {
                Text(steg).foregroundStyle(.secondary)
                Spacer()
                if let andel {
                    Text("\(Int(andel * 100)) %")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if let andel {
                ProgressView(value: andel)
                Text(kvarText(andel))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }

            // Texten allteftersom säger mer än en siffra: man ser att det
            // faktiskt är rätt ljud som läses.
            if !senaste.isEmpty {
                Text("«\(senaste)»")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
                    .animation(.default, value: senaste)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    /// Uppskattad tid kvar, räknad på hur fort det gått hittills.
    private func kvarText(_ andel: Double) -> String {
        let gått = Date().timeIntervalSince(start)
        guard andel > 0.02, gått > 2 else { return "Beräknar tid …" }
        let kvar = gått / andel - gått
        if kvar < 60 { return "Ungefär \(Int(kvar)) sekunder kvar" }
        return "Ungefär \(Int((kvar / 60).rounded())) minuter kvar"
    }

    private func klar(_ namn: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle").font(.system(size: 44)).foregroundStyle(.green)
            Text("Inspelningen är tillagd").font(.title3.weight(.semibold))
            Text(namn).font(.callout).foregroundStyle(.secondary)
            Text("Öppna den och sätt namn på rösterna under «Vem är vem».")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Klar") { vidKlar(); stäng() }.keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func felruta(_ text: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 40)).foregroundStyle(.orange)
            Text(text).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Försök igen") { läge = .väljer }
                Button("Stäng") { stäng() }.keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - Handling

    private func väljFil() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .movie, .mpeg4Movie, .mp3, .wav, .quickTimeMovie]
        panel.message = "Välj en mötesinspelning"
        if panel.runModal() == .OK, let vald = panel.url { välj(vald) }
    }

    private func välj(_ url: URL) {
        fil = url
        if titel.isEmpty { titel = url.deletingPathExtension().lastPathComponent }
    }

    private func kör() {
        guard let fil else { return }
        let placering: Placering = valtProjekt.map { .projekt($0) } ?? .kund(kund)
        let namn = titel.trimmingCharacters(in: .whitespaces)
        let profiler = arkiv.röstprofiler(för: kund)
        läge = .arbetar
        steg = "Förbereder"
        andel = nil
        senaste = ""
        start = Date()

        Task {
            let importör = Import()
            do {
                let (_, mapp) = try await importör.importera(
                    fil, placering: placering,
                    titel: namn.isEmpty ? fil.deletingPathExtension().lastPathComponent : namn,
                    kund: kund, profiler: profiler,
                    språk: språk,
                    vidLäge: { l in
                        Task { @MainActor in
                            steg = l.steg
                            andel = l.andel
                            if let s = l.senaste, !s.isEmpty { senaste = s }
                        }
                    })
                läge = .klar(mapp.lastPathComponent)
                vidKlar()
            } catch {
                läge = .fel(error.localizedDescription)
            }
        }
    }
}

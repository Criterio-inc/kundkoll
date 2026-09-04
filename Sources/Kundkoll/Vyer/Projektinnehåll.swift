import SwiftUI
import AppKit

/// Ett projekt hos en kund.
struct Projektinnehåll: View {
    let kund: Kund
    let projekt: Projekt

    @EnvironmentObject private var arkiv: Arkivet
    @EnvironmentObject private var session: Inspelningssession

    @State private var flik: Flik = .översikt
    @State private var kopplade: [Kopplad] = []
    /// Dokument ur varje kopplad mapp i kunskapsbanken, och om inläsningen pågår.
    @State private var dokumentantal: [String: (filer: Int, medText: Int)] = [:]
    @State private var läserIn = false
    @State private var inspelningar: [(Inspelning, URL)] = []
    @State private var öppnad: Kundinnehåll.Öppnad?
    @State private var attKasta: Kundinnehåll.Öppnad?
    @State private var visaImport = false
    @State private var släpptFil: URL?
    @State private var lägesbild: Lägesbild?
    @State private var skriverLäget = false
    @State private var lägesjobb: Task<Void, Never>?
    @State private var lägesfel: String?
    /// Ett skrivförsök per gång vyn visas — annars skulle ett projekt utan
    /// underlag försöka om vid varje omritning.
    @State private var harFörsöktSkriva = false

    enum Flik: String, CaseIterable, Identifiable {
        case översikt, attGöra, inspelningar, anteckningar, tid
        var id: String { rawValue }
        var namn: String {
            switch self {
            case .översikt: "Översikt"
            case .attGöra: "Att göra"
            case .inspelningar: "Inspelningar"
            case .anteckningar: "Anteckningar"
            case .tid: "Tid"
            }
        }
        var ikon: String {
            switch self {
            case .översikt: "square.grid.2x2"
            case .attGöra: "checklist"
            case .inspelningar: "waveform"
            case .anteckningar: "note.text"
            case .tid: "clock"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $flik) {
                ForEach(Flik.allCases) { f in
                    Label(f.namn, systemImage: f.ikon).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch flik {
                    case .översikt:
                        lägesavsnitt
                        mappavsnitt
                    case .attGöra: Kanbanvy(kund: kund, projekt: projekt)
                    case .inspelningar: inspelningsflik
                    case .anteckningar: Anteckningslista(mapp: projekt.anteckningsmapp)
                    case .tid: Tidsvy(kund: kund, projekt: projekt)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Stil.botten)
        .navigationTitle(projekt.namn)
        .navigationSubtitle(kund.namn)
        .sheet(item: $öppnad) { v in
            Transkriptvy(kund: kund, inspelning: v.inspelning, mapp: v.mapp)
                .onDisappear(perform: läsIn)
        }
        .sheet(isPresented: $visaImport) {
            Importvy(kund: kund, projekt: arkiv.projekt(för: kund),
                     förvald: släpptFil, förvaltProjekt: projekt, vidKlar: läsIn)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { leverantörer in
            guard let l = leverantörer.first else { return false }
            _ = l.loadObject(ofClass: URL.self) { url, _ in
                guard let url, Import.format.contains(url.pathExtension.lowercased()) else { return }
                Task { @MainActor in släpptFil = url; visaImport = true }
            }
            return true
        }
        .confirmationDialog(
            "Flytta inspelningen till papperskorgen?",
            isPresented: Binding(get: { attKasta != nil }, set: { if !$0 { attKasta = nil } }),
            presenting: attKasta
        ) { v in
            Button("Flytta till papperskorgen", role: .destructive) {
                try? arkiv.kastaInspelning(i: v.mapp)
                attKasta = nil
                läsIn()
            }
            Button("Avbryt", role: .cancel) { attKasta = nil }
        } message: { v in
            Text("\(v.inspelning.titel) med ljud och transkript flyttas till papperskorgen.")
        }
        .onAppear {
            läsIn()
            // Lägesbilden ska bara finnas där. Saknas den, eller har underlaget
            // ändrats, skrivs den om — men högst en gång per besök, och bara
            // när chattens modell är på plats.
            lägesbild = Läget.läs(kund: kund, projekt: projekt)
            if !harFörsöktSkriva, Modellval.läs().färdig,
               lägesbild == nil
               || Läget.gammal(lägesbild!, kund: kund, projekt: projekt, arkiv: arkiv) {
                harFörsöktSkriva = true
                skrivLäget(automatiskt: true)
            }
        }
        .onChange(of: arkiv.sparningar) { läsIn() }
        .onReceive(NotificationCenter.default.publisher(for: .dokumentIndexerade)) { _ in
            räknaDokument()
        }
    }

    /// Var projektet står just nu, skrivet av modellen ur uppgifter, möten,
    /// mejl och anteckningar. Cachas och skrivs om när underlaget ändrats.
    private var lägesavsnitt: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Avsnittsrubrik("Läget just nu")
                if skriverLäget { ProgressView().controlSize(.mini) }
                Spacer()
                Text(faktarad)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let lägesbild {
                VStack(alignment: .leading, spacing: 10) {
                    Markdowntext(text: lägesbild.text)
                    HStack(spacing: 8) {
                        Text("Skriven \(DateFormatter.klocka.string(from: lägesbild.skriven))"
                             + (lägesbild.modell.map { " av \($0)" } ?? ""))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        if Läget.gammal(lägesbild, kund: kund, projekt: projekt, arkiv: arkiv) {
                            Text("· underlaget har ändrats")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        Button("Skriv om") { skrivLäget() }
                            .buttonStyle(.link)
                            .font(.caption)
                            .disabled(skriverLäget)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .kort()
            } else if skriverLäget {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Läser igenom projektet och skriver lägesbilden … kan ta en minut lokalt")
                        .foregroundStyle(.secondary)
                    Button("Avbryt") { lägesjobb?.cancel() }.buttonStyle(.link)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .kort()
            } else if let lägesfel {
                Text(lägesfel)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .kort()
            }
        }
    }

    /// Det räknbara, som alltid stämmer oavsett vad modellen skrev.
    private var faktarad: String {
        let egna = arkiv.uppgifter(för: kund).filter { $0.projekt == projekt.namn }
        let öppna = egna.filter { $0.läge != .klart }
        let försenade = öppna.filter(\.försenad).count
        var delar: [String] = []
        delar.append("\(inspelningar.count) \(inspelningar.count == 1 ? "möte" : "möten")")
        var u = "\(öppna.count) öppna uppgifter"
        if försenade > 0 { u += " · \(försenade) försenade" }
        delar.append(u)
        if let senaste = inspelningar.first?.0.inledd {
            delar.append("senast \(DateFormatter.kortdag.string(from: senaste))")
        }
        return delar.joined(separator: " · ")
    }

    private func skrivLäget(automatiskt: Bool = false) {
        guard !skriverLäget,
              let jobb = Arbeten.delad.starta(.lägesbild, kund: kund, titel: "Skriver lägesbild för \(projekt.namn)",
                                              beställt: !automatiskt)
        else { return }
        skriverLäget = true
        lägesfel = nil
        lägesjobb = Task {
            do {
                let bild = try await Läget.skriv(kund: kund, projekt: projekt, arkiv: arkiv,
                                                 automatiskt: automatiskt)
                lägesbild = bild
                jobb.klart("Lägesbilden skriven", modell: bild.modell)
            } catch {
                if Task.isCancelled {
                    jobb.klart("Avbrutet")
                } else {
                    lägesfel = error.localizedDescription
                    jobb.föll(error.localizedDescription)
                }
            }
            skriverLäget = false
        }
    }

    /// Mappar utanför kundmappen som hör till projektet.
    private var mappavsnitt: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Avsnittsrubrik("Kopplade mappar")
                Spacer()
                Button("Koppla mapp", action: väljMapp).buttonStyle(.link)
            }
            if kopplade.isEmpty {
                Text("Peka ut en mapp som hör till projektet. Dokument — Word, Excel, PowerPoint, PDF, text, bilder — läses in i kunskapsbanken. Källkod indexeras inte utan genomsöks av en agent när du frågar, så att svaret bygger på hur filerna ser ut just nu.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(kopplade.enumerated()), id: \.element.id) { i, k in
                        HStack(spacing: 10) {
                            Image(systemName: k.finns ? "folder" : "questionmark.folder")
                                .foregroundStyle(k.finns ? Color.secondary : Color.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(k.visatNamn)
                                    if let n = dokumentantal[k.väg] {
                                        Märke(text: Indexering.dokumentetikett(filer: n.filer, medText: n.medText, pågår: läserIn),
                                              ikon: "doc.richtext")
                                    }
                                }
                                Text(k.finns ? k.väg : "Mappen finns inte längre")
                                    .font(.caption)
                                    .foregroundStyle(k.finns ? Color.secondary : Color.orange)
                                    .lineLimit(1)
                                    .truncationMode(.head)
                            }
                            Spacer()
                            if k.finns {
                                Button { NSWorkspace.shared.open(k.url) } label: {
                                    Image(systemName: "arrow.up.forward.square")
                                }
                                .buttonStyle(.borderless)
                                .help("Visa i Finder")
                            }
                            Button {
                                kopplade = (try? arkiv.koppla(bort: k, från: projekt)) ?? kopplade
                                Indexering.glöm(k, hos: kund)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Koppla bort mappen. Innehållet rörs inte, men försvinner ur kunskapsbanken.")
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        if i < kopplade.count - 1 { Divider() }
                    }
                }
                .kort(hörn: Stil.radhörn)
            }
        }
    }

    private var inspelningsflik: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Avsnittsrubrik("Inspelningar")
                Spacer()
                // Samma två vägar som hos kunden: spela in nytt, eller lägg
                // till en färdig fil — den hamnar då i projektet direkt.
                Button("Lägg till") { släpptFil = nil; visaImport = true }
                    .buttonStyle(.link)
                Button("Spela in") {
                    Inspelningsfönster.öppna(kund: kund, projekt: projekt, möte: nil)
                }
                .buttonStyle(.link)
                .disabled(session.pågår)
            }
            if inspelningar.isEmpty {
                Text("Inga inspelningar än. Släpp en ljud- eller videofil här för att lägga till en.")
                    .foregroundStyle(.secondary)
            } else {
                Inspelningslista(
                    rader: inspelningar,
                    öppna: { öppnad = .init(inspelning: $0, mapp: $1) },
                    kasta: { attKasta = .init(inspelning: $0, mapp: $1) })
            }
        }
    }

    private func väljMapp() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.message = "Välj en mapp som hör till \(projekt.namn)"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            kopplade = (try? arkiv.koppla(url, till: projekt)) ?? kopplade
        }
        Indexering.dokumentIBakgrunden(för: kund)
        räknaDokument()
    }

    /// Hur många dokument ur varje mapp som ligger i kunskapsbanken.
    private func räknaDokument() {
        läserIn = Indexering.pågår(kund)
        guard !kopplade.isEmpty, let bank = try? Kunskapsbank(kund: kund) else {
            dokumentantal = [:]
            return
        }
        var ut: [String: (filer: Int, medText: Int)] = [:]
        for k in kopplade {
            ut[k.väg] = (bank.antalKällor(under: k.väg + "/"),
                         bank.antalDokument(under: k.väg + "/"))
        }
        dokumentantal = ut
    }

    private func läsIn() {
        kopplade = arkiv.kopplade(för: projekt)
        räknaDokument()
        inspelningar = arkiv.inspelningar(för: kund).filter { $0.0.projekt == projekt.namn }
    }
}

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
    @State private var inspelningar: [(Inspelning, URL)] = []
    @State private var öppnad: Kundinnehåll.Öppnad?
    @State private var attKasta: Kundinnehåll.Öppnad?

    enum Flik: String, CaseIterable, Identifiable {
        case översikt, attGöra, inspelningar, anteckningar
        var id: String { rawValue }
        var namn: String {
            switch self {
            case .översikt: "Översikt"
            case .attGöra: "Att göra"
            case .inspelningar: "Inspelningar"
            case .anteckningar: "Anteckningar"
            }
        }
        var ikon: String {
            switch self {
            case .översikt: "square.grid.2x2"
            case .attGöra: "checklist"
            case .inspelningar: "waveform"
            case .anteckningar: "note.text"
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
                    case .översikt: mappavsnitt
                    case .attGöra: Kanbanvy(kund: kund, projekt: projekt)
                    case .inspelningar: inspelningsflik
                    case .anteckningar: Anteckningslista(mapp: projekt.anteckningsmapp)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle(projekt.namn)
        .navigationSubtitle(kund.namn)
        .sheet(item: $öppnad) { v in
            Transkriptvy(kund: kund, inspelning: v.inspelning, mapp: v.mapp)
                .onDisappear(perform: läsIn)
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
        .onAppear(perform: läsIn)
        .onChange(of: arkiv.sparningar) { läsIn() }
    }

    /// Mappar utanför kundmappen som hör till projektet.
    private var mappavsnitt: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Kopplade mappar").font(.headline)
                Spacer()
                Button("Koppla mapp", action: väljMapp).buttonStyle(.link)
            }
            if kopplade.isEmpty {
                Text("Peka ut en mapp med källkod, ritningar eller offerter. Chatten söker i den när du frågar något — innehållet indexeras inte, så svaret bygger på hur filerna ser ut just nu.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(kopplade.enumerated()), id: \.element.id) { i, k in
                        HStack(spacing: 10) {
                            Image(systemName: k.finns ? "folder" : "questionmark.folder")
                                .foregroundStyle(k.finns ? Color.secondary : Color.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(k.visatNamn)
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
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Koppla bort mappen. Innehållet rörs inte.")
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        if i < kopplade.count - 1 { Divider() }
                    }
                }
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
            }
        }
    }

    private var inspelningsflik: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Inspelningar").font(.headline)
                Spacer()
                Button("Spela in") {
                    Inspelningsfönster.öppna(kund: kund, projekt: projekt, möte: nil)
                }
                .buttonStyle(.link)
                .disabled(session.pågår)
            }
            if inspelningar.isEmpty {
                Text("Inga inspelningar än.").foregroundStyle(.secondary)
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
    }

    private func läsIn() {
        kopplade = arkiv.kopplade(för: projekt)
        inspelningar = arkiv.inspelningar(för: kund).filter { $0.0.projekt == projekt.namn }
    }
}

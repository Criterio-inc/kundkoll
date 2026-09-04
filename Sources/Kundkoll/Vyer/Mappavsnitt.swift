import SwiftUI

/// «Kopplade mappar» hos en kund eller ett projekt: samma lista, samma
/// räkning och samma varningar var man än står. Mapparna rörs inte;
/// dokumenten i dem läses in i kundens kunskapsbank.
struct Mappavsnitt: View {
    let placering: Placering
    let kund: Kund

    @EnvironmentObject private var arkiv: Arkivet
    @State private var kopplade: [Kopplad] = []
    /// Dokument ur varje kopplad mapp i kunskapsbanken, och om inläsningen pågår.
    @State private var dokumentantal: [String: (filer: Int, medText: Int)] = [:]
    @State private var läserIn = false
    @State private var dokumentfel: String?
    @State private var iMolnet = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Avsnittsrubrik("Kopplade mappar")
                Spacer()
                Button("Koppla mapp", action: väljMapp).buttonStyle(.link)
            }
            if kopplade.isEmpty {
                Text(förklaring)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                if iMolnet > 0 {
                    Label("\(iMolnet) filer ligger kvar i molnet och kan inte läsas. Högerklicka mappen i Finder och välj «Behåll alltid på den här enheten».",
                          systemImage: "icloud.and.arrow.down")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let dokumentfel {
                    Label("Någon fil gick inte att läsa: \(dokumentfel)",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                mapplista
            }
        }
        .onAppear(perform: läsIn)
        .onChange(of: placering) { läsIn() }
        .onChange(of: arkiv.sparningar) { läsIn() }
        .onReceive(NotificationCenter.default.publisher(for: .dokumentIndexerade)) { _ in
            räknaDokument()
        }
    }

    private var förklaring: String {
        switch placering {
        case .kund:
            "Peka ut en mapp med kundens material — OneDrive, en delad mapp, ett arkiv. Word, Excel, PowerPoint, PDF, text och bilder läses in i kunskapsbanken så att chatten kan svara ur dem. Mappen rörs inte."
        case .projekt:
            "Peka ut en mapp som hör till projektet. Dokument — Word, Excel, PowerPoint, PDF, text, bilder — läses in i kunskapsbanken. Källkod indexeras inte utan genomsöks av en agent när du frågar, så att svaret bygger på hur filerna ser ut just nu."
        }
    }

    private var mapplista: some View {
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
                        kopplade = (try? arkiv.koppla(bort: k, från: placering)) ?? kopplade
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

    private func väljMapp() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.message = switch placering {
        case .kund(let k): "Välj en mapp med material om \(k.namn)"
        case .projekt(let p): "Välj en mapp som hör till \(p.namn)"
        }
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            kopplade = (try? arkiv.koppla(url, till: placering)) ?? kopplade
        }
        räknaDokument()
        Indexering.dokumentIBakgrunden(för: kund)
    }

    private func läsIn() {
        kopplade = arkiv.kopplade(för: placering)
        räknaDokument()
    }

    /// Hur många dokument ur varje mapp som ligger i kunskapsbanken.
    private func räknaDokument() {
        läserIn = Indexering.pågår(kund)
        dokumentfel = Indexering.senasteUtfall[kund.id]?.fel
        iMolnet = Indexering.senasteUtfall[kund.id]?.platshållare ?? 0
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
}

extension View {
    /// Tar emot en släppt ljud- eller videofil och öppnar importbladet med
    /// den förvald. Samma sak hos kunden och i projektet.
    func tarEmotInspelningsfil(förvald: Binding<URL?>, visaImport: Binding<Bool>) -> some View {
        onDrop(of: [.fileURL], isTargeted: nil) { leverantörer in
            guard let l = leverantörer.first else { return false }
            _ = l.loadObject(ofClass: URL.self) { url, _ in
                guard let url, Import.format.contains(url.pathExtension.lowercased()) else { return }
                Task { @MainActor in förvald.wrappedValue = url; visaImport.wrappedValue = true }
            }
            return true
        }
    }

    /// Frågar innan ett möte flyttas till papperskorgen, och läser om efteråt.
    func bekräftarKast(av möte: Binding<Möte?>, arkiv: Arkivet, efter läsOm: @escaping () -> Void) -> some View {
        confirmationDialog(
            "Flytta inspelningen till papperskorgen?",
            isPresented: Binding(get: { möte.wrappedValue != nil }, set: { if !$0 { möte.wrappedValue = nil } }),
            presenting: möte.wrappedValue
        ) { v in
            Button("Flytta till papperskorgen", role: .destructive) {
                try? arkiv.kastaInspelning(i: v.mapp)
                möte.wrappedValue = nil
                läsOm()
            }
            Button("Avbryt", role: .cancel) { möte.wrappedValue = nil }
        } message: { v in
            Text("\(v.inspelning.titel) med ljud och transkript flyttas till papperskorgen. Du kan ta tillbaka den därifrån.")
        }
    }
}

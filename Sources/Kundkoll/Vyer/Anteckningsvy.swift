import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Redigerar en anteckning.
///
/// Texten är markdown och filen är anteckningen — samma fil som Obsidian
/// öppnar. Bilder läggs bredvid i en `bilder`-mapp och länkas med wikilänkar,
/// så att Obsidian visar dem utan vidare.
struct Anteckningsvy: View {
    @State var anteckning: Anteckning
    /// Mappen anteckningen ligger i, dit bilder sparas.
    let mapp: URL
    var vidÄndring: () -> Void

    @EnvironmentObject private var arkiv: Arkivet
    @Environment(\.dismiss) private var stäng

    @State private var titel = ""
    @State private var text = ""
    @State private var sparaJobb: Task<Void, Never>?
    /// Letar åtaganden en stund efter att man slutat skriva.
    @State private var letaJobb: Task<Void, Never>?
    @State private var meddelande: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField("Rubrik", text: $titel)
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .onSubmit(byNamn)
                Spacer()
                Text(DateFormatter.klocka.string(from: anteckning.ändrad))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if Obsidian.finns {
                    Button {
                        spara()
                        Obsidian.öppna(anteckning.fil)
                    } label: {
                        Image(systemName: "book.closed")
                    }
                    .help("Öppna i Obsidian")
                }
            }
            .padding(16)
            Divider()

            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(12)
                .onChange(of: text) { schemaläggSparning() }
                .onDrop(of: [.image, .fileURL], isTargeted: nil, perform: släpp)

            if !anteckning.bilder.isEmpty {
                Divider()
                miniatyrer
            }

            Divider()
            HStack(spacing: 10) {
                Button {
                    taSkärmdump()
                } label: {
                    Label("Skärmdump", systemImage: "camera.viewfinder")
                }
                .help("Dra ut ett område på skärmen; bilden läggs in i anteckningen")

                Button {
                    klistraInBild()
                } label: {
                    Label("Klistra in bild", systemImage: "doc.on.clipboard")
                }
                .disabled(!urklippHarBild)

                if let m = meddelande {
                    Text(m).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Klar") { spara(); stäng() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 720, height: 600)
        .onAppear {
            titel = anteckning.titel
            text = anteckning.text
        }
        .onDisappear { spara(); leta() }
    }

    private var miniatyrer: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(anteckning.bilder, id: \.self) { namn in
                    let url = mapp.appending(path: namn)
                    if let bild = NSImage(contentsOf: url) {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Image(nsImage: bild)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 96, height: 64)
                                .clipShape(.rect(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .help(namn)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(height: 86)
    }

    // MARK: - Bilder

    private var urklippHarBild: Bool {
        NSPasteboard.general.canReadObject(forClasses: [NSImage.self])
    }

    /// Öppnar macOS egen områdesväljare. Appen behöver ingen egen infångning
    /// och användaren får samma verktyg som vanligt.
    private func taSkärmdump() {
        let tillfällig = FileManager.default.temporaryDirectory
            .appending(path: "kundkoll-\(UUID().uuidString).png")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -i väljer område interaktivt, -o utan fönsterskugga.
        p.arguments = ["-i", "-o", tillfällig.path]
        do { try p.run() } catch {
            meddelande = "Kunde inte starta skärmdumpen."
            return
        }
        p.terminationHandler = { _ in
            Task { @MainActor in
                defer { try? FileManager.default.removeItem(at: tillfällig) }
                // Avbryter man med Esc skrivs ingen fil.
                guard let data = try? Data(contentsOf: tillfällig), !data.isEmpty else { return }
                infoga(data, ändelse: "png")
            }
        }
    }

    private func klistraInBild() {
        guard let bild = NSPasteboard.general.readObjects(forClasses: [NSImage.self])?.first as? NSImage,
              let data = bild.pngData else {
            meddelande = "Urklippet innehåller ingen bild."
            return
        }
        infoga(data, ändelse: "png")
    }

    private func släpp(_ leverantörer: [NSItemProvider]) -> Bool {
        var någon = false
        for l in leverantörer {
            if l.canLoadObject(ofClass: NSImage.self) {
                någon = true
                _ = l.loadObject(ofClass: NSImage.self) { objekt, _ in
                    guard let bild = objekt as? NSImage, let data = bild.pngData else { return }
                    Task { @MainActor in infoga(data, ändelse: "png") }
                }
            }
        }
        return någon
    }

    private func infoga(_ data: Data, ändelse: String) {
        do {
            let namn = try arkiv.sparaBild(data, ändelse: ändelse, i: mapp)
            if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
            text += "\n![[\(namn)]]\n"
            spara()
            meddelande = "Bilden är tillagd."
            Task {
                try? await Task.sleep(for: .seconds(3))
                meddelande = nil
            }
        } catch {
            meddelande = "Kunde inte spara bilden."
        }
    }

    // MARK: - Sparning

    /// Sparar strax efter att man slutat skriva, i stället för vid varje tangent.
    private func schemaläggSparning() {
        sparaJobb?.cancel()
        sparaJobb = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            spara()
        }
    }

    private func spara() {
        guard text != anteckning.text else { return }
        anteckning.text = text
        anteckning.ändrad = Date()
        try? arkiv.spara(anteckning)
        vidÄndring()
        schemaläggLetning()
    }

    // MARK: - Åtaganden ur anteckningen

    /// Väntar tills man slutat skriva på riktigt: en modellrunda per
    /// sparning vore en runda var sekund.
    private func schemaläggLetning() {
        letaJobb?.cancel()
        letaJobb = Task {
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            leta()
        }
    }

    private func leta() {
        letaJobb?.cancel(); letaJobb = nil
        let a = anteckning
        guard let kund = arkiv.kunder.first(where: { a.fil.path.hasPrefix($0.mapp.path + "/") })
        else { return }
        guard let jobb = Arbeten.delad.starta(.anteckningsrunda, kund: kund, titel: "Letar åtaganden i «\(a.titel)»")
        else { return }
        Task {
            let u = await Uppgiftssamling.frånAnteckning(a, kund: kund)
            if let fel = u.fel {
                jobb.föll(fel)
                meddelande = "Kunde inte leta åtaganden: \(fel)"
            } else if u.genomgångna == 0 {
                jobb.klart("Oförändrad sedan sist", modell: u.modell)
            } else {
                let text = u.nya == 0 ? "Inga åtaganden i anteckningen" : "\(u.nya) åtaganden lades på tavlan"
                jobb.klart(text, modell: u.modell)
                meddelande = text
            }
        }
    }

    private func byNamn() {
        let rent = titel.trimmingCharacters(in: .whitespaces)
        guard !rent.isEmpty, rent != anteckning.titel else { return }
        spara()
        if let ny = try? arkiv.döpOm(anteckning, till: rent) {
            anteckning = ny
            titel = ny.titel
            vidÄndring()
        }
    }
}

extension NSImage {
    var pngData: Data? {
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

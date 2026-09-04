import SwiftUI
import AppKit

/// Frågor om en kund eller ett projekt, besvarade ur kundens eget material.
///
/// En panel och inte ett blad: man ska kunna slå upp något medan ett möte
/// spelas in eller ett transkript ligger uppe bredvid.
struct Chattpanel: View {
    let kund: Kund
    /// Sätt när chatten gäller ett enskilt projekt.
    var projekt: Projekt?
    /// Sätt när chatten gäller ett enskilt möte. Då ligger hela transkriptet
    /// med som underlag, och samtalen hör till mötet i stället för till kunden.
    var möte: Inspelning?
    var mötesmapp: URL?
    /// Källor som alltid ska med, utöver det sökningen hittar — till exempel
    /// förra mötets sammanfattning i en mötesserie.
    var extraUnderlag: [Kunskapsbank.Träff] = []

    @EnvironmentObject private var arkiv: Arkivet

    @State private var samtal = Samtal()
    @State private var tidigare: [Samtal] = []
    @State private var fråga = ""
    @State private var väntar = false
    /// Svaret som väntas, så att det går att avbryta. Förut stod «Tänker …»
    /// i upp till fem minuter när en lokal modell hängt sig.
    @State private var svarJobb: Task<Void, Never>?
    @State private var fel: String?
    @State private var bank: Kunskapsbank?
    @State private var status = "Förbereder …"
    @State private var visaNyckel = false
    @State private var senasteTräffar: [Kunskapsbank.Träff] = []
    @State private var förbereder = true
    @State private var hovrat: UUID?
    @State private var mappar: [Kopplad] = []
    /// Mappar som just nu genomsöks av en agent.
    @State private var söker: Set<String> = []
    @State private var sparadeSom: String?

    private let chatt = Chatt()
    private let kodagent = Kodagent()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                // Samtalets titel, och listan över tidigare bakom den.
                Menu {
                    Button {
                        nyttSamtal()
                    } label: {
                        Label("Nytt samtal", systemImage: "plus")
                    }
                    if !tidigare.isEmpty {
                        Divider()
                        ForEach(tidigare) { t in
                            Button {
                                byt(till: t)
                            } label: {
                                Text(t.id == samtal.id ? "✓  \(t.titel)" : "    \(t.titel)")
                            }
                        }
                    }
                    if !samtal.tomt {
                        Divider()
                        Button("Ta bort det här samtalet", role: .destructive, action: taBort)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(samtal.tomt
                             ? (möte?.titel ?? projekt?.namn ?? kund.namn)
                             : samtal.titel)
                            .font(.headline)
                            .lineLimit(1)
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                if förbereder { ProgressView().controlSize(.small) }
                Spacer()
                Button {
                    nyttSamtal()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(.borderless)
                .help("Nytt samtal")
                // Vad banken innehåller är sällan det man vill läsa, men bra
                // att kunna se — därför i verktygstipset och inte på raden.
                Image(systemName: "info.circle")
                    .foregroundStyle(.tertiary)
                    .help(status)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            // Var svaret kommer ifrån ska synas, inte bara finnas i ett
            // verktygstips: det är det som avgör om kundmaterial lämnar datorn.
            Label(chatt.lämnarDatorn ? "Svarar med \(chatt.etikett) — materialet lämnar datorn"
                                     : "Svarar med \(chatt.etikett)",
                  systemImage: chatt.lämnarDatorn ? "lock.open" : "lock")
                .font(.caption)
                .foregroundStyle(chatt.lämnarDatorn ? Color.orange : Color.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            Divider()

            ScrollViewReader { rulle in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if samtal.meddelanden.isEmpty { tomtLäge }
                        // Tomma meddelanden är platshållare som väntar på sin
                        // första strömmade bit; de ritas inte.
                        ForEach(samtal.meddelanden.filter { !$0.text.isEmpty }) { m in
                            bubbla(m).id(m.id)
                        }
                        if väntar && !(samtal.meddelanden.last.map {
                            $0.roll == .assistent && !$0.text.isEmpty } ?? false) {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text(chatt.lämnarDatorn ? "Tänker …" : "Tänker … en lokal modell kan ta upp till en minut")
                                    .foregroundStyle(.secondary)
                                Button("Avbryt") { avbryt() }
                                    .buttonStyle(.link).font(.caption)
                                Spacer()
                            }
                            .padding(.leading, 14)
                            .id("väntar")
                        }
                        ForEach(mappar.filter { söker.contains($0.väg) }) { m in
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Läser \(m.visatNamn) — svaret kommer när det är klart")
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.leading, 14)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: samtal.meddelanden.count) {
                    if let sista = samtal.meddelanden.last {
                        withAnimation { rulle.scrollTo(sista.id, anchor: .bottom) }
                    }
                }
                // Strömmande text ändrar inte antalet; följ även växandet.
                .onChange(of: samtal.meddelanden.last?.text) {
                    if let sista = samtal.meddelanden.last, !sista.text.isEmpty {
                        rulle.scrollTo(sista.id, anchor: .bottom)
                    }
                }
            }

            if let sparadeSom {
                Divider()
                HStack(spacing: 8) {
                    Label("Sparat som «\(sparadeSom)» bland anteckningarna",
                          systemImage: "checkmark.circle")
                        .font(.callout)
                        .foregroundStyle(.green)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            if let fel {
                Divider()
                HStack(spacing: 8) {
                    Label(fel, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if fel.contains("API-nyckel") || fel.contains("Ollama") || fel.contains("adressen") {
                        Button("Inställningar") { visaNyckel = true }
                    }
                }
                .font(.callout)
                .padding(16)
            }

            Divider()
            HStack(spacing: 10) {
                TextField(möte == nil ? "Fråga om \(projekt?.namn ?? kund.namn) …" : "Fråga om mötet …",
                          text: $fråga, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 18))
                    .onSubmit(skicka)
                Button {
                    skicka()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(kanSkicka ? Color.accentColor : Color.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .disabled(!kanSkicka)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .sheet(isPresented: $visaNyckel) { Modellvy() }
        .task { await förbered() }
    }

    private var tomtLäge: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(möte == nil ? "Fråga om det som sagts och skrivits" : "Fråga om mötet")
                .font(.title3.weight(.semibold))
            Text(möte == nil
                 ? "Svaren byggs på transkript, anteckningar, mejl med bilagor, dokument ur kopplade mappar, kontakter och tidigare samtal hos \(kund.namn)."
                 : "Hela samtalet ligger som underlag, tillsammans med det övriga materialet hos \(kund.namn).")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            FlödandeRad(mellanrum: 8) {
                ForEach(möte == nil
                        ? ["Vad lovade vi senast?",
                           "Vilka frågor är obesvarade?",
                           "Vad sa de om priset?"]
                        : ["Vad landade vi i?",
                           "Vad ska jag göra?",
                           "Vad lämnades obesvarat?"], id: \.self) { f in
                    Button {
                        fråga = f
                        skicka()
                    } label: {
                        Text(f)
                            .font(.callout)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(.quaternary.opacity(0.5), in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func bubbla(_ m: Chatt.Meddelande) -> some View {
        if m.roll == .människa {
            // Egna frågor till höger, som i vilken chatt som helst. Placeringen
            // säger vem som talar, så ingen etikett behövs.
            HStack {
                Spacer(minLength: 60)
                Text(m.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.accentColor, in: .rect(cornerRadius: 16))
                    .foregroundStyle(.white)
            }
        } else {
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 10) {
                    if m.ursprung == .mapp, let mapp = m.mapp {
                        Label("ur \(mapp)", systemImage: "folder")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Markdowntext(text: m.text)
                        .textSelection(.enabled)
                    if !m.hänvisningar.isEmpty {
                        källor(m.hänvisningar)
                    }
                }
                .padding(14)
                .background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 16))

                // Ett svar är ofta värt att behålla. Knappen visas vid
                // hovring så att den inte tar plats i varje bubbla.
                if hovrat == m.id {
                    Button {
                        sparaSomAnteckning(m)
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Spara svaret som anteckning")
                }
                Spacer(minLength: 20)
            }
            .onHover { hovrar in hovrat = hovrar ? m.id : (hovrat == m.id ? nil : hovrat) }
        }
    }

    /// Skriver ett svar till en anteckning i kundens eller projektets valv.
    private func sparaSomAnteckning(_ m: Chatt.Meddelande) {
        // Frågan som ledde fram till svaret ger noten sin rubrik.
        let fråga = samtal.meddelanden
            .prefix(while: { $0.id != m.id })
            .last { $0.roll == .människa }?.text ?? "Fråga"
        let rubrik = String(fråga.prefix(60))
            .trimmingCharacters(in: CharacterSet(charactersIn: " ?.!"))
        let mapp = projekt?.anteckningsmapp ?? kund.anteckningsmapp

        guard var not = try? arkiv.nyAnteckning(i: mapp, titel: rubrik) else { return }
        var text = "# \(not.titel)\n\n"
        text += "> \(fråga)\n\n"
        text += m.text + "\n"
        if !m.hänvisningar.isEmpty {
            text += "\n## Underlag\n\n"
            for h in m.hänvisningar {
                text += "- \(h.beskrivning)\n"
            }
        }
        text += "\n---\nSvar ur kunskapsbanken \(DateFormatter.klocka.string(from: m.tid)).\n"
        not.text = text
        try? arkiv.spara(not)

        sparadeSom = not.titel
        Task {
            try? await Task.sleep(for: .seconds(4))
            sparadeSom = nil
        }
    }

    /// Källorna som små knappar på en rad i stället för en lista.
    /// De upprepar redan numren i texten; poängen är att kunna öppna dem.
    private func källor(_ hänvisningar: [Chatt.Hänvisning]) -> some View {
        FlödandeRad(mellanrum: 6) {
            ForEach(hänvisningar) { h in
                Button {
                    öppna(h)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: h.ikon).font(.caption2)
                        Text("\(h.nummer)")
                            .font(.caption2.weight(.medium))
                            .monospacedDigit()
                        Text(h.titel)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.background.opacity(0.6), in: .capsule)
                }
                .buttonStyle(.plain)
                .help(h.beskrivning)
            }
        }
    }

    private func öppna(_ h: Chatt.Hänvisning) {
        let url = URL(fileURLWithPath: h.källa)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        // Transkript och mejl ligger som json bredvid den markdown man vill se.
        let visa = url.lastPathComponent == "möte.json"
            ? url.deletingLastPathComponent().appending(path: "Transkript.md")
            : url.lastPathComponent == "mail.json"
                ? url.deletingLastPathComponent().appending(path: "Mail.md")
                : url
        if Obsidian.finns, visa.pathExtension == "md" {
            Obsidian.öppna(visa)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([visa])
        }
    }

    private var kanSkicka: Bool {
        !fråga.trimmingCharacters(in: .whitespaces).isEmpty && !väntar && bank != nil
    }

    // MARK: - Handling

    /// Ett tomt samtal med rätt hemvist.
    private func tomtSamtal() -> Samtal {
        Samtal(projekt: projekt?.namn, projektID: projekt?.id, möte: möte?.id.uuidString)
    }

    /// Hela mötet som en källa. Frågan gäller det som sades, så transkriptet
    /// ska med oavsett vad sökningen tycker om orden i frågan.
    private var mötesträff: Kunskapsbank.Träff? {
        guard let möte else { return nil }
        var text = möte.yttranden.map { y in
            "[\(y.tidsstämpel)] \(y.etikett(möte.röstnamn, enspårig: möte.enspårig)): \(y.text)"
        }.joined(separator: "\n")
        // Ett långt möte får inte tränga ut allt annat ur kontextfönstret.
        if text.count > 40_000 {
            text = String(text.prefix(20_000)) + "\n\n[…]\n\n" + String(text.suffix(20_000))
        }
        return Kunskapsbank.Träff(
            id: -1, typ: "transkript", titel: möte.titel, text: text,
            källa: mötesmapp?.appending(path: "möte.json").path ?? "",
            tid: möte.inledd, poäng: 0)
    }

    private func förbered() async {
        tidigare = arkiv.samtal(för: kund, projekt: projekt, möte: möte?.id.uuidString)
        samtal = tidigare.first ?? tomtSamtal()
        // En mötschatt håller sig till mötet. En projektchatt söker i
        // projektets mappar; kundchatten i alla projektens, men bara några,
        // annars blir det för många agenter.
        // Agenten får bara kodmappar. Dokumentmappar ligger redan i
        // kunskapsbanken, och en agent som läste om dem vid varje fråga vore
        // både långsam och överflödig.
        // Agenten är Claude Code och går till Anthropic vad som än är valt
        // under Inställningar. Därför bara när Anthropic är valt, och då
        // står det i statusraden. Uppmätt 2026-09-03: den hade redan läst
        // Borås OneDrive-mapp med «Lokal modell» valt.
        if möte != nil || Modellval.läs().leverantör != .anthropic {
            mappar = []
        } else if let projekt {
            mappar = arkiv.kopplade(för: projekt)
                .filter(\.finns)
                .filter(Kopplademappar.harKod)
        } else {
            mappar = Array((arkiv.kopplade(för: kund)
                + arkiv.projekt(för: kund).flatMap { arkiv.kopplade(för: $0) })
                .filter(\.finns)
                .filter(Kopplademappar.harKod)
                .prefix(3))
        }
        förbereder = true
        status = "Läser igenom materialet …"
        do {
            let b = try Kunskapsbank(kund: kund)
            let r = try await Indexering.körIBakgrunden(för: kund, bank: b)
            bank = b
            // Dokumenten ur kopplade mappar tar längre tid och läses i
            // bakgrunden; det som redan är inläst är sökbart direkt.
            Indexering.dokumentIBakgrunden(för: kund)
            var rader = b.antal == 0
                ? "Inget material att söka i än"
                : "\(b.antal) stycken ur transkript, anteckningar, mejl och dokument"
                    + (r.indexerade > 0 ? " · \(r.indexerade) nyindexerade" : "")
            if möte != nil { rader = "Hela mötet, och \(rader.lowercased())" }
            if await Inbäddare.delad.tillgänglig {
                rader += "\nSöker på både ord och betydelse"
                // Nyindexerat bäddas in i bakgrunden, på en egen anslutning.
                let kund = kund
                Task.detached(priority: .utility) {
                    guard let b = try? Kunskapsbank(kund: kund) else { return }
                    await Inbäddare.kör(bank: b)
                }
            }
            if !mappar.isEmpty {
                rader += "\nSöker också i \(mappar.map(\.visatNamn).joined(separator: ", "))"
                    + " — läses av Claude Code, lämnar datorn"
            }
            rader += "\nSvarar med \(chatt.etikett)"
            status = rader
        } catch {
            status = "Kunde inte läsa materialet"
            fel = error.localizedDescription
        }
        förbereder = false
        if await !chatt.färdig {
            let l = await chatt.leverantör
            fel = l.behöverNyckel
                ? "Ingen API-nyckel för \(l.namn). Lägg in den för att kunna fråga."
                : "Modellen är inte färdigställd. Kontrollera adressen under API-nyckel."
        }
    }

    private func skicka() {
        let text = fråga.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !väntar, let bank else { return }
        fråga = ""
        fel = nil
        samtal.meddelanden.append(Chatt.Meddelande(roll: .människa, text: text))
        spara()
        väntar = true

        // Projektets namn hjälper sökningen att hamna rätt när frågan gäller
        // ett projekt men är formulerad utan att nämna det.
        let sökt = projekt.map { "\(text) \($0.namn)" } ?? text
        let historik = samtal.meddelanden.dropLast()

        // Svaret strömmas in i en platshållare, så att de första orden syns
        // på under sekunden. Hänvisningarna sätts när texten är färdig.
        let plats = Chatt.Meddelande(roll: .assistent, text: "")
        samtal.meddelanden.append(plats)
        svarJobb = Task {
            // Mötet först: frågan gäller det som sades där. Sökningen sker
            // här inne eftersom betydelsedelen behöver Ollama och är asynkron.
            let träffar = (mötesträff.map { [$0] } ?? []) + extraUnderlag
                + (await bank.bästaSök(sökt))
            senasteTräffar = träffar
            do {
                let svar = try await chatt.fråga(
                    text, om: kund.namn, projekt: projekt?.namn,
                    träffar: träffar, historik: Array(historik),
                    vidDelta: { bit in
                        Task { @MainActor in
                            guard let i = samtal.meddelanden.firstIndex(where: { $0.id == plats.id })
                            else { return }
                            samtal.meddelanden[i].text += bit
                        }
                    })
                if let i = samtal.meddelanden.firstIndex(where: { $0.id == plats.id }) {
                    samtal.meddelanden[i].text = svar.text
                    samtal.meddelanden[i].hänvisningar = svar.hänvisningar
                }
                spara()
            } catch {
                // URLSession kastar ett vanligt fel vid avbrott, inte
                // CancellationError; uppgiftens flagga är det som gäller.
                if Task.isCancelled {
                    // Det som hann komma får stå kvar, märkt; ett tomt svar tas bort.
                    if let i = samtal.meddelanden.firstIndex(where: { $0.id == plats.id }) {
                        if samtal.meddelanden[i].text.isEmpty {
                            samtal.meddelanden.remove(at: i)
                        } else {
                            samtal.meddelanden[i].text += "\n\n(avbrutet)"
                        }
                    }
                } else {
                    samtal.meddelanden.removeAll { $0.id == plats.id }
                    fel = error.localizedDescription
                }
            }
            väntar = false
            svarJobb = nil
        }

        // Kopplade mappar genomsöks av en agent som läser filerna. Det tar
        // tiotals sekunder, så svaret får komma när det kommer i stället för
        // att hålla tillbaka det snabba.
        for mapp in mappar {
            sökIMapp(mapp, fråga: text)
        }
    }

    private func avbryt() {
        svarJobb?.cancel()
    }

    private func sökIMapp(_ mapp: Kopplad, fråga text: String) {
        söker.insert(mapp.väg)
        Task {
            defer { söker.remove(mapp.väg) }
            do {
                let svar = try await kodagent.fråga(
                    text, i: mapp.url, om: kund.namn, projekt: projekt?.namn)
                samtal.meddelanden.append(Chatt.Meddelande(
                    roll: .assistent, text: svar.text,
                    ursprung: .mapp, mapp: mapp.visatNamn))
                spara()
            } catch {
                // Att agenten inte kunde svara ska inte dölja det svar som kom
                // ur kunskapsbanken.
                samtal.meddelanden.append(Chatt.Meddelande(
                    roll: .assistent,
                    text: "Kunde inte söka i \(mapp.visatNamn): \(error.localizedDescription)",
                    ursprung: .mapp, mapp: mapp.visatNamn))
                spara()
            }
        }
    }

    /// Börjar om utan att kasta det som var. Ett tomt samtal sparas inte —
    /// annars skulle listan fyllas av tomma poster.
    private func nyttSamtal() {
        guard !samtal.tomt else { return }
        spara()
        samtal = tomtSamtal()
        fel = nil
        tidigare = arkiv.samtal(för: kund, projekt: projekt, möte: möte?.id.uuidString)
    }

    private func byt(till annat: Samtal) {
        guard annat.id != samtal.id else { return }
        spara()
        samtal = annat
        fel = nil
    }

    private func taBort() {
        try? arkiv.taBort(samtal, för: kund)
        tidigare = arkiv.samtal(för: kund, projekt: projekt, möte: möte?.id.uuidString)
        samtal = tidigare.first ?? tomtSamtal()
    }

    private func spara() {
        guard !samtal.tomt else { return }
        try? arkiv.spara(samtal, för: kund)
        tidigare = arkiv.samtal(för: kund, projekt: projekt, möte: möte?.id.uuidString)
        // Titeln sätts vid sparning; hämta tillbaka den.
        if let uppdaterad = tidigare.first(where: { $0.id == samtal.id }) {
            samtal.titel = uppdaterad.titel
        }
    }
}


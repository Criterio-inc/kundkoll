import SwiftUI
import AppKit

/// Ett möte, efter mötet.
///
/// Transkriptet är sällan det man vill läsa. Det man vill veta är vad mötet
/// landade i, vad någon lovade, och svaret på den fråga man kom hit med —
/// därför ligger sammanfattningen först, uppgifterna bredvid och en chatt som
/// har hela samtalet som underlag i panelen till höger.
struct Transkriptvy: View {
    let kund: Kund
    @State var inspelning: Inspelning
    @State var mapp: URL
    @Environment(\.dismiss) private var stäng
    @EnvironmentObject private var arkiv: Arkivet

    @State private var visaRöster = false
    @State private var visaChatt = Inställningar.mötesChattPå
    @State private var flik: Flik = .sammanfattning
    @State private var uppgifter: [Uppgift] = []
    @State private var redigerad: Uppgift?
    @State private var ny = ""
    @State private var sammanfattar = false
    @State private var sammanfattningsjobb: Task<Void, Never>?
    @State private var fel: String?
    /// Sätts medan hela inspelningen görs om — transkribering, röster,
    /// sammanfattning.
    @State private var körOmSteg: String?
    @StateObject private var spelare = Yttrandespelare()
    @State private var hovrad: UUID?
    /// Närmast föregående möte i samma serie, när det finns ett.
    @State private var förra: Möte?
    /// Åtaganden från förra mötet som fortfarande är öppna.
    @State private var kvarSedanSist = 0

    private enum Flik: String, CaseIterable, Identifiable {
        case sammanfattning, transkript, attGöra
        var id: String { rawValue }
        var namn: String {
            switch self {
            case .sammanfattning: "Sammanfattning"
            case .transkript: "Transkript"
            case .attGöra: "Att göra"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                rubrik
                Divider()
                Picker("", selection: $flik) {
                    ForEach(Flik.allCases) { f in
                        Text(f == .attGöra && !uppgifter.isEmpty
                             ? "\(f.namn) \(uppgifter.count)" : f.namn).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                Divider()

                switch flik {
                case .sammanfattning: sammanfattningsflik
                case .transkript: transkriptflik
                case .attGöra: uppgiftsflik
                }

                Divider()
                HStack {
                    if let körOmSteg {
                        ProgressView().controlSize(.small)
                        Text(körOmSteg).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    } else if let fel {
                        Text(fel).font(.caption).foregroundStyle(.red).lineLimit(2)
                    }
                    Spacer()
                    Button("Stäng") { stäng() }.keyboardShortcut(.defaultAction)
                }
                .padding(16)
            }
            .frame(width: 700)

            if visaChatt {
                Divider()
                Chattpanel(kund: kund, projekt: projekt, möte: inspelning, mötesmapp: mapp,
                           extraUnderlag: förraSomUnderlag)
                    .id(inspelning.id)
                    .frame(width: 400)
            }
        }
        .frame(height: 660)
        .onAppear(perform: läsUppgifter)
        // Efterbearbetningen skriver möte.json tre gånger i bakgrunden. Vyn
        // höll förut sin kopia från klicket och skrev tillbaka den över
        // arkivtranskriptet vid nästa sparning. Nu läser den om från disk.
        .onChange(of: arkiv.sparningar) {
            läsUppgifter()
            if !sammanfattar, !visaRöster, let ny = arkiv.inspelning(i: mapp) { inspelning = ny }
        }
        .onDisappear { spelare.sluta() }
        .sheet(isPresented: $visaRöster) {
            Röstvy(kund: kund, mapp: mapp, inspelning: inspelning) { inspelning = $0 }
        }
        .sheet(item: $redigerad) { u in
            Uppgiftsredigering(uppgift: u, kund: kund, vidSparat: läsUppgifter)
        }
    }

    // MARK: - Rubrik

    private var rubrik: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(inspelning.titel).font(.headline)
                Text("\(DateFormatter.klocka.string(from: inspelning.inledd)) · \(formateraLängd(inspelning.längd))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !inspelning.efterbearbetad {
                Märke(text: "live", färg: .orange)
            }
            // Knappen ska finnas även när uppdelningen inte gav några
            // grupper — det är ju precis då man vill köra om den med ett
            // angivet antal.
            if inspelning.yttranden.contains(where: { $0.röst == .motpart }) {
                Button {
                    visaRöster = true
                } label: {
                    Label("Vem är vem", systemImage: "person.wave.2")
                }
            }
            if Obsidian.finns {
                Button {
                    Obsidian.öppna(mapp.appending(path: "Transkript.md"), valvrot: kund.mapp)
                } label: {
                    Image(systemName: "book.closed")
                }
                .help("Öppna transkriptet i Obsidian")
            }
            Button {
                NSWorkspace.shared.open(mapp)
            } label: {
                Image(systemName: "folder")
            }
            .help("Visa i Finder")
            if inspelning.enspårig {
                // Fel språk vid importen ska inte kräva en ny import — ljudet
                // finns ju kvar.
                Menu {
                    Button("Transkribera om på svenska") { transkriberaOm("sv") }
                    Button("Transkribera om på engelska") { transkriberaOm("en") }
                    Button("Transkribera om — avgör själv") { transkriberaOm(nil) }
                } label: {
                    Image(systemName: "arrow.trianglehead.2.clockwise")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(körOmSteg != nil)
                .help("Kör om transkribering, röster och sammanfattning på valt språk")
            }
            Button {
                visaChatt.toggle()
                Inställningar.mötesChattPå = visaChatt
            } label: {
                Image(systemName: "bubble.left.and.text.bubble.right")
            }
            .help(visaChatt ? "Dölj chatten" : "Fråga om mötet")
        }
        .padding(16)
    }

    // MARK: - Flikar

    @ViewBuilder
    private var sammanfattningsflik: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if förra != nil { förraGången }
                if let s = inspelning.sammanfattning, !s.tom || !s.kärna.isEmpty {
                    if !s.kärna.isEmpty {
                        Text(s.kärna)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let m = s.modell {
                        Text("Sammanfattad av \(m)")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    if !s.beslut.isEmpty { punktlista("Beslut", s.beslut) }
                    if !s.öppet.isEmpty { punktlista("Öppna frågor", s.öppet) }
                    if !s.besvarade.isEmpty { punktlista("Besvarat från förra mötet", s.besvarade) }
                    if !s.beslut.isEmpty || !s.öppet.isEmpty || !uppgifter.isEmpty {
                        Divider()
                    }
                    if !uppgifter.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Att göra").font(.subheadline.weight(.semibold))
                            Text("\(uppgifter.count) på tavlan")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 16) {
                        Button("Skriv uppföljningsmejl") { uppföljningsmejl() }
                            .help("Öppnar ett utkast i Mail med beslut och åtaganden. Inget skickas.")
                        if sammanfattar {
                            ProgressView().controlSize(.small)
                            Text("Skriver om … kan ta en minut lokalt").font(.caption).foregroundStyle(.secondary)
                            Button("Avbryt") { sammanfattningsjobb?.cancel() }.buttonStyle(.link)
                        } else {
                            Button("Skriv om sammanfattningen") {
                                sammanfattningsjobb = Task { await sammanfatta() }
                            }
                            .buttonStyle(.link)
                        }
                    }
                } else {
                    saknasSammanfattning
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }

    /// Serien binder ihop återkommande möten: samma titel så när som på
    /// siffrorna. Det man vill veta inför och efter ett 1:1 är nästan alltid
    /// vad som sades på förra.
    @ViewBuilder
    private var förraGången: some View {
        if let f = förra?.inspelning {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Förra gången · \(DateFormatter.dag.string(from: f.inledd))",
                          systemImage: "clock.arrow.circlepath")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("Öppna") { if let förra { visa(förra) } }
                        .buttonStyle(.link)
                }
                if let kärna = f.sammanfattning?.kärna, !kärna.isEmpty {
                    Text(kärna)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if kvarSedanSist > 0 {
                    let föreslagna = inspelning.sammanfattning?.verkarKlara.count ?? 0
                    Text((kvarSedanSist == 1
                          ? "1 åtagande därifrån är fortfarande öppet"
                          : "\(kvarSedanSist) åtaganden därifrån är fortfarande öppna")
                         + (föreslagna > 0 ? ", \(föreslagna) verkar klara enligt det här mötet: se tavlan" : ""))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 10))
        }
    }

    /// Byter till ett annat möte i samma vy — bläddring i serien.
    private func visa(_ annat: Möte) {
        spelare.sluta()
        inspelning = annat.inspelning
        mapp = annat.mapp
        läsUppgifter()
    }

    private var saknasSammanfattning: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ingen sammanfattning än")
                .font(.subheadline.weight(.semibold))
            Text("En modell läser igenom mötet och skriver vad det handlade om, "
                 + "vad som beslutades och vad någon lovade att göra. "
                 + "Åtagandena hamnar på tavlan.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(sammanfattar ? "Sammanfattar …" : "Sammanfatta mötet") {
                sammanfattningsjobb = Task { await sammanfatta() }
            }
            .disabled(sammanfattar || inspelning.yttranden.isEmpty)
            if sammanfattar {
                ProgressView().controlSize(.small)
                Text("Kan ta en minut med lokal modell").font(.caption).foregroundStyle(.secondary)
                Button("Avbryt") { sammanfattningsjobb?.cancel() }.buttonStyle(.link)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 10))
    }

    private var transkriptflik: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(inspelning.yttranden) { y in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(y.etikett(inspelning.röstnamn, enspårig: inspelning.enspårig))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(färg(y))
                            Text(y.tidsstämpel)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                            // Transkriptet är whispers ord; ljudet är facit.
                            Button {
                                spelare.växla(y, i: mapp, enspårig: inspelning.enspårig)
                            } label: {
                                Image(systemName: spelare.spelar == y.id
                                      ? "stop.fill" : "play.fill")
                                    .font(.system(size: 9))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(spelare.spelar == y.id
                                             ? Color.accentColor : Color.secondary)
                            .opacity(spelare.spelar == y.id || hovrad == y.id ? 1 : 0)
                            .help("Hör vad som faktiskt sades")
                        }
                        Text(y.text)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(spelare.spelar == y.id
                                ? Color.accentColor.opacity(0.08) : Color.clear,
                                in: .rect(cornerRadius: 6))
                    .onHover { över in hovrad = över ? y.id : (hovrad == y.id ? nil : hovrad) }
                }
            }
            .padding(14)
        }
    }

    private var uppgiftsflik: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if uppgifter.isEmpty {
                        Text(inspelning.sammanfattning == nil
                             ? "Åtagandena plockas ut när mötet sammanfattas."
                             : "Mötet gav inga åtaganden.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    }
                    ForEach(uppgifter) { u in uppgiftsrad(u) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            Divider()
            HStack(spacing: 8) {
                TextField("Lägg till något ur mötet", text: $ny)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(läggTill)
                Button("Lägg till", action: läggTill)
                    .disabled(ny.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16)
        }
    }

    private func uppgiftsrad(_ u: Uppgift) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button {
                bocka(u)
            } label: {
                Image(systemName: u.läge == .klart ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(u.läge == .klart ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(u.vad)
                    .strikethrough(u.läge == .klart)
                    .foregroundStyle(u.läge == .klart ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                if u.vem != nil || u.när != nil {
                    Text([u.vem, u.när].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if u.läge == .pågår {
                Text("Pågår").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 8))
        .contentShape(.rect(cornerRadius: 8))
        .onTapGesture { redigerad = u }
    }

    private func punktlista(_ rubrik: String, _ rader: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(rubrik).font(.subheadline.weight(.semibold))
            ForEach(Array(rader.enumerated()), id: \.offset) { _, r in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("•").foregroundStyle(.secondary)
                    Text(r).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Handling

    private var projekt: Projekt? {
        arkiv.projekt(innehållande: mapp, hos: kund)
    }

    /// Uppgifterna som kom ur det här mötet. Tavlan är sanningen — det som
    /// står i sammanfattningen är en ögonblicksbild från när den skrevs.
    private func läsUppgifter() {
        uppgifter = arkiv.uppgifter(för: kund)
            .filter { Uppgiftssamling.hör($0, till: mapp, titel: inspelning.titel) }
            .sorted { $0.skapad < $1.skapad }
        förra = Mötesserie.föregående(inspelning, bland: arkiv.inspelningar(för: kund))
        kvarSedanSist = förra.map { f in
            arkiv.uppgifter(för: kund)
                .filter { Uppgiftssamling.hör($0, till: f.mapp, titel: f.inspelning.titel) }
                .filter { $0.läge != .klart }
                .count
        } ?? 0
    }

    /// Förra mötets sammanfattning som underlag åt chatten, så att "vad sa
    /// vi förra gången?" har något att stå på även utan sökträff.
    private var förraSomUnderlag: [Kunskapsbank.Träff] {
        guard let förra, let s = förra.inspelning.sammanfattning, !s.kärna.isEmpty else { return [] }
        let (f, m) = (förra.inspelning, förra.mapp)
        var text = s.kärna
        if !s.beslut.isEmpty { text += "\nBeslut: " + s.beslut.joined(separator: "; ") }
        if !s.öppet.isEmpty { text += "\nÖppet: " + s.öppet.joined(separator: "; ") }
        return [Kunskapsbank.Träff(
            id: -2, typ: "sammanfattning", titel: "Förra mötet · \(f.titel)",
            text: text, källa: m.appending(path: "möte.json").path,
            tid: f.inledd, poäng: 0)]
    }

    private func bocka(_ u: Uppgift) {
        var ändrad = u
        ändrad.läge = u.läge == .klart ? .attGöra : .klart
        try? arkiv.uppdatera(ändrad, för: kund)
        läsUppgifter()
    }

    private func läggTill() {
        let text = ny.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        _ = try? arkiv.läggTill([Uppgift(vad: text, ursprung: .möte, källa: mapp.path,
                                     källtitel: inspelning.titel,
                                     projekt: inspelning.projekt)], för: kund)
        ny = ""
        läsUppgifter()
    }

    /// Ett utkast i Mail ur det mötet landade i. Skickas aldrig härifrån.
    private func uppföljningsmejl() {
        let text = Uppföljning.brödtext(för: inspelning, kort: uppgifter)
        guard !text.isEmpty else { return }
        let till = Uppföljning.mottagare(för: inspelning,
                                         kontakter: arkiv.kontakter(för: kund))
        do {
            try Uppföljning.öppnaUtkast(ämne: "Uppföljning: \(inspelning.titel)",
                                        text: text, till: till)
        } catch {
            fel = error.localizedDescription
        }
    }

    /// Gör om hela inspelningen från ljudet: transkribering på valt språk,
    /// röstuppdelning, sammanfattning. Titeln behålls.
    private func transkriberaOm(_ språk: String?) {
        guard körOmSteg == nil else { return }
        körOmSteg = "Förbereder …"
        fel = nil
        spelare.sluta()
        let placering: Placering = projekt.map { .projekt($0) } ?? .kund(kund)
        let profiler = arkiv.röstprofiler(för: kund)
        let titel = inspelning.titel
        Task {
            do {
                let ny = try await Import().slutför(
                    mapp: mapp, placering: placering, profiler: profiler,
                    titel: titel, språk: språk,
                    vidLäge: { l in
                        Task { @MainActor in
                            körOmSteg = l.steg
                                + (l.andel.map { " · \(Int($0 * 100)) %" } ?? "")
                        }
                    })
                inspelning = ny
                läsUppgifter()
            } catch {
                fel = error.localizedDescription
            }
            körOmSteg = nil
        }
    }

    private func sammanfatta() async {
        sammanfattar = true
        fel = nil
        defer { sammanfattar = false }
        do {
            let förra = Uppgiftssamling.förra(för: inspelning, mapp: mapp)
            let s = try await Sammanfattare().skriv(för: inspelning, kund: kund.namn, förra: förra)
            inspelning.sammanfattning = s
            try arkiv.spara(inspelning, i: mapp)
            Uppgiftssamling.frånMöte(s, inspelning: inspelning, mapp: mapp)
            läsUppgifter()
        } catch {
            // Avbrutet av dig: inget att säga. Andra fel visas.
            if !Task.isCancelled { fel = error.localizedDescription }
        }
    }

    /// Egen färg per röst, så att man ser talarbyten utan att läsa namnen.
    private func färg(_ y: Yttrande) -> Color {
        guard y.röst == .motpart || inspelning.enspårig else { return .blue }
        let paletten: [Color] = [.purple, .orange, .teal, .pink, .indigo, .brown]
        guard let g = y.röstgrupp else { return .purple }
        return paletten[g % paletten.count]
    }
}

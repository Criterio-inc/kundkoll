import SwiftUI
import AppKit

/// Allt om en kund, uppdelat i flikar.
///
/// Tidigare låg allt i en enda lång rulle. Med möten, projekt, anteckningar,
/// kontakter, inspelningar och mejl på samma sida fick man scrolla förbi det
/// man inte var ute efter för att komma åt det man ville ha.
struct Kundinnehåll: View {
    let kund: Kund
    var väljProjekt: (Projekt) -> Void

    @EnvironmentObject private var arkiv: Arkivet
    @EnvironmentObject private var kalender: Kalendern
    @EnvironmentObject private var adressbok: Adressboken
    @EnvironmentObject private var session: Inspelningssession

    @State private var flik: Flik = .översikt
    @State private var projekt: [Projekt] = []
    @State private var kontakter: [Kontakt] = []
    @State private var möten: [Kalendern.Möte] = []
    @State private var inspelningar: [(Inspelning, URL)] = []
    @State private var visaBilagor = false
    @State private var mejl: [Mailen.Mejl] = []
    @State private var bilagor: [Bilagor.Bilaga] = []
    @State private var mejlLäge: Mejlläge = .ejHämtat
    /// Den retroaktiva genomgången av alla mejl: pågår den, och vad gav den.
    @State private var mejlrundaPågår = false
    @State private var mejlrundaBesked: String?

    @State private var visaNyttProjekt = false
    @State private var nyttProjektnamn = ""
    @State private var visaKontakter = false
    @State private var visaImport = false
    @State private var släpptFil: URL?
    @State private var öppnad: Öppnad?
    @State private var attKasta: Öppnad?
    @State private var ofullständiga: [(mapp: URL, storlek: Int)] = []
    @State private var briefing: Kalendern.Möte?
    @State private var visaMötesplockare = false
    /// Mötes-id → projektnamn, valt för hand.
    @State private var möteskopplingar: [String: String] = [:]
    @State private var slutför: URL?
    @State private var slutförsteg = ""
    /// Mappar utanför kundmappen, och hur många dokument ur var och en som
    /// ligger i kunskapsbanken.
    @State private var kopplade: [Kopplad] = []
    @State private var dokumentantal: [String: (filer: Int, medText: Int)] = [:]
    @State private var läserIn = false
    @State private var dokumentfel: String?
    @State private var iMolnet = 0

    enum Flik: String, CaseIterable, Identifiable {
        case översikt, attGöra, inspelningar, anteckningar, mail
        var id: String { rawValue }
        var namn: String {
            switch self {
            case .översikt: "Översikt"
            case .attGöra: "Att göra"
            case .inspelningar: "Inspelningar"
            case .anteckningar: "Anteckningar"
            case .mail: "Mail"
            }
        }
        var ikon: String {
            switch self {
            case .översikt: "square.grid.2x2"
            case .attGöra: "checklist"
            case .inspelningar: "waveform"
            case .anteckningar: "note.text"
            case .mail: "envelope"
            }
        }
    }

    enum Mejlläge: Equatable { case ejHämtat, hämtar(String), klar, fel(String) }

    struct Öppnad: Identifiable {
        let inspelning: Inspelning
        let mapp: URL
        var id: UUID { inspelning.id }
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
                    case .översikt: översikt
                    case .attGöra: Kanbanvy(kund: kund)
                    case .inspelningar: inspelningsflik
                    case .anteckningar: Anteckningslista(mapp: kund.anteckningsmapp)
                    case .mail: mailflik
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Stil.botten)
        .navigationTitle(kund.namn)
        .onDrop(of: [.fileURL], isTargeted: nil) { leverantörer in
            guard let l = leverantörer.first else { return false }
            _ = l.loadObject(ofClass: URL.self) { url, _ in
                guard let url, Import.format.contains(url.pathExtension.lowercased()) else { return }
                Task { @MainActor in släpptFil = url; visaImport = true }
            }
            return true
        }
        .sheet(isPresented: $visaNyttProjekt) { nyttProjektBlad }
        .sheet(isPresented: $visaKontakter) { Kontaktvy(kund: kund).onDisappear(perform: läsOm) }
        .sheet(isPresented: $visaImport) {
            Importvy(kund: kund, projekt: projekt, förvald: släpptFil, vidKlar: läsOm)
        }
        .sheet(item: $öppnad) { v in
            Transkriptvy(kund: kund, inspelning: v.inspelning, mapp: v.mapp)
                .onDisappear(perform: läsOm)
        }
        .sheet(isPresented: $visaMötesplockare) {
            Mötesplockare(kund: kund) {
                Task { await hämtaMöten() }
                läsOm()
            }
        }
        .sheet(item: $briefing) { m in
            Briefingvy(kund: kund, möte: m) { i, mapp in
                öppnad = Öppnad(inspelning: i, mapp: mapp)
            }
        }
        .confirmationDialog(
            "Flytta inspelningen till papperskorgen?",
            isPresented: Binding(get: { attKasta != nil }, set: { if !$0 { attKasta = nil } }),
            presenting: attKasta
        ) { v in
            Button("Flytta till papperskorgen", role: .destructive) {
                try? arkiv.kastaInspelning(i: v.mapp)
                attKasta = nil
                läsOm()
            }
            Button("Avbryt", role: .cancel) { attKasta = nil }
        } message: { v in
            Text("\(v.inspelning.titel) med ljud och transkript flyttas till papperskorgen. Du kan ta tillbaka den därifrån.")
        }
        .onAppear {
            läsOm()
            hämtaKontaktbilder()
            // Indexet hålls aktuellt från start — inte först när ett mejl
            // råkar hämtas eller chatten öppnas. Ändringskontrollen gör att
            // ett aktuellt index kostar nästan ingenting att bekräfta.
            indexeraIBakgrunden()
        }
        // Ett avslutat möte — och senare arkivtranskriptet, rösterna och
        // sammanfattningen — ska dyka upp utan att appen startas om.
        .onChange(of: arkiv.sparningar) { läsOm() }
        .onReceive(NotificationCenter.default.publisher(for: .dokumentIndexerade)) { _ in
            räknaDokument()
        }
        .task(id: kund.id) { await hämtaMöten() }
        .task(id: kund.id) { await visaMejl() }
        // Ett nyinbokat eller flyttat möte ska synas direkt.
        .onChange(of: kalender.ändringar) { Task { await hämtaMöten() } }
        // Och när man kommer tillbaka till appen efter att ha varit någon
        // annanstans är det troligt att något hänt.
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            Task {
                await hämtaMöten()
                await visaMejl(äldreÄn: 5 * 60)
            }
        }
        // Mail säger inte till när något kommer in, så det får kollas med
        // jämna mellanrum. Sökningen tar sekunder, därför inte oftare.
        .onReceive(Timer.publish(every: 300, on: .main, in: .common).autoconnect()) { _ in
            Task { await visaMejl(äldreÄn: 15 * 60) }
        }
    }

    // MARK: - Översikt

    @ViewBuilder
    private var översikt: some View {
        mötesavsnitt
        projektavsnitt
        mappavsnitt
        kontaktavsnitt
        if !inspelningar.isEmpty {
            avsnitt("Senaste inspelningarna") {
                inspelningslista(Array(inspelningar.prefix(3)))
            }
        }
    }

    @ViewBuilder
    private var mötesavsnitt: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Avsnittsrubrik(möten.isEmpty ? "Möten" : "Kommande möten")
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .help("Ett möte räknas som kundens om någon deltagare finns "
                          + "bland kundens kontakter, har kundens mejldomän, eller "
                          + "om kundnamnet står i mötets titel. Andra möten läggs "
                          + "till för hand, och projektet väljs på raden.")
                Spacer()
                Button("Lägg till möte") { visaMötesplockare = true }
                    .buttonStyle(.link)
                    .help("Ta ett möte i anspråk som reglerna inte känner igen — "
                          + "till exempel ett utan deltagarlista")
            }
            mötesinnehåll
        }
    }

    @ViewBuilder
    private var mötesinnehåll: some View {
        Group {
            if möten.isEmpty {
                Text(kalender.harTillgång
                     ? "Inga inbokade möten med \(kund.namn) de närmaste veckorna."
                     : "Ge tillgång till Kalender för att se inbokade möten.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
            VStack(spacing: 0) {
                ForEach(Array(möten.prefix(5).enumerated()), id: \.offset) { i, m in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.titel)
                            HStack(spacing: 6) {
                                Text(m.pågår ? "pågår nu" : närText(m.start))
                                let andra = m.deltagare.filter { !$0.ärJag }
                                if !andra.isEmpty {
                                    Text("· \(andra.map(\.namn).prefix(3).joined(separator: ", "))")
                                        .lineLimit(1)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if m.pågår {
                            Märke(text: "pågår", färg: .red)
                        }
                        if !projekt.isEmpty {
                            // Vilket projekt mötet hör till kan ingen regel
                            // gissa; det väljs här och följer med inspelningen.
                            Menu {
                                Button("Inget projekt") { koppla(m, till: nil) }
                                ForEach(projekt) { p in
                                    Button(p.namn) { koppla(m, till: p.namn) }
                                }
                                Divider()
                                Button("Hör inte till \(kund.namn)", role: .destructive) {
                                    try? arkiv.uteslutMöte(m.id, för: kund)
                                    läsOm()
                                    Task { await hämtaMöten() }
                                }
                            } label: {
                                Label({ let p = möteskopplingar[m.id]
                                        return (p?.isEmpty == false) ? p! : "Projekt" }(),
                                      systemImage: "folder")
                                    .font(.caption)
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .foregroundStyle(möteskopplingar[m.id] == nil
                                             ? Color.secondary : Color.accentColor)
                            .help("Välj vilket projekt mötet hör till")
                        }
                        if let länk = m.möteslänk {
                            Button { NSWorkspace.shared.open(länk) } label: {
                                Image(systemName: "video")
                            }
                            .buttonStyle(.borderless)
                            .help("Öppna mötet")
                        }
                        Button("Förbered") { briefing = m }
                            .buttonStyle(.borderless)
                            .help("Senaste mötet, öppna åtaganden och nya mejl — läsningen inför mötet")
                        Button("Spela in") {
                            // Mötet bär titel, deltagare och sitt valda
                            // projekt. Mikrofonen är den som användes sist.
                            Inspelningsfönster.öppna(kund: kund,
                                                     projekt: kopplatProjekt(m),
                                                     möte: m)
                        }
                        .buttonStyle(.borderless)
                        .disabled(session.pågår)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    if i < min(5, möten.count) - 1 { Divider() }
                }
            }
            .kort(hörn: Stil.radhörn)
            }
        }
    }

    private func koppla(_ m: Kalendern.Möte, till projektnamn: String?) {
        try? arkiv.kopplaMöte(m.id, till: projektnamn, för: kund)
        möteskopplingar = arkiv.möteskopplingar(för: kund)
    }

    private func kopplatProjekt(_ m: Kalendern.Möte) -> Projekt? {
        möteskopplingar[m.id].flatMap { namn in projekt.first { $0.namn == namn } }
    }

    /// "om 20 minuter", "i dag 14:00", "på torsdag" — närmare till hands än
    /// ett datum när allt som visas ligger framåt.
    private func närText(_ start: Date) -> String {
        let kalender = Calendar.current
        let om = start.timeIntervalSinceNow
        if om < 3600 {
            return "om \(max(1, Int(om / 60))) minuter"
        }
        if kalender.isDateInToday(start) {
            return "i dag \(DateFormatter.timme.string(from: start))"
        }
        if kalender.isDateInTomorrow(start) {
            return "i morgon \(DateFormatter.timme.string(from: start))"
        }
        if om < 7 * 24 * 3600 {
            let f = DateFormatter()
            f.locale = Locale(identifier: "sv_SE")
            f.dateFormat = "EEEE HH:mm"
            return f.string(from: start)
        }
        return DateFormatter.klocka.string(from: start)
    }

    private var projektavsnitt: some View {
        avsnitt("Projekt", knapp: ("Nytt projekt", { visaNyttProjekt = true })) {
            if projekt.isEmpty {
                Text("Inga projekt än.").foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)],
                          alignment: .leading, spacing: 10) {
                    ForEach(projekt) { p in
                        Button { väljProjekt(p) } label: {
                            HStack {
                                Image(systemName: "folder")
                                Text(p.namn).lineLimit(1)
                                Spacer()
                            }
                            .padding(10)
                            .kort(hörn: Stil.radhörn)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var kontaktavsnitt: some View {
        avsnitt("Kontakter", knapp: ("Hantera", { visaKontakter = true })) {
            if kontakter.isEmpty {
                Text("Inga kontakter än.").foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10)],
                          alignment: .leading, spacing: 10) {
                    ForEach(kontakter) { k in
                        HStack(spacing: 10) {
                            Kontaktsigill(kontakt: k, kund: kund, sida: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(k.namn)
                                if let r = k.roll {
                                    Text(r).font(.caption).foregroundStyle(.secondary)
                                } else if let e = k.förstaEpost {
                                    Text(e).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .kort(hörn: Stil.radhörn)
                    }
                }
            }
        }
    }

    // MARK: - Inspelningar

    @ViewBuilder
    private var inspelningsflik: some View {
        if !ofullständiga.isEmpty { ofullständigaAvsnitt }
        avsnitt("Inspelningar", knapp: ("Lägg till", { släpptFil = nil; visaImport = true })) {
            if inspelningar.isEmpty {
                Text("Inga inspelningar än. Släpp en ljud- eller videofil här för att lägga till en.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                inspelningslista(inspelningar)
            }
        }
    }

    /// Inspelningar vars ljud finns men vars transkript aldrig blev klart.
    private var ofullständigaAvsnitt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Påbörjade inspelningar").font(.headline)
            Text("Ljudet finns men transkriberingen blev aldrig klar.")
                .font(.callout).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(Array(ofullständiga.enumerated()), id: \.offset) { i, rad in
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rad.mapp.lastPathComponent).lineLimit(1)
                            Text("\(rad.storlek / 1_000_000) MB ljud")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if slutför == rad.mapp {
                            ProgressView().controlSize(.small)
                            Text(slutförsteg).font(.caption).foregroundStyle(.secondary)
                        } else {
                            Button("Gör klart") { görKlart(rad.mapp) }
                                .disabled(slutför != nil)
                            Button {
                                try? arkiv.kastaInspelning(i: rad.mapp)
                                läsOm()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Flytta till papperskorgen")
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    if i < ofullständiga.count - 1 { Divider() }
                }
            }
            .background(.orange.opacity(0.08), in: .rect(cornerRadius: 8))
        }
    }

    private func görKlart(_ mapp: URL) {
        slutför = mapp
        slutförsteg = "Förbereder"
        let profiler = arkiv.röstprofiler(för: kund)
        Task {
            let importör = Import()
            _ = try? await importör.slutför(
                mapp: mapp, placering: .kund(kund), profiler: profiler,
                vidLäge: { l in Task { @MainActor in slutförsteg = l.steg } })
            slutför = nil
            läsOm()
        }
    }

    private func inspelningslista(_ rader: [(Inspelning, URL)]) -> some View {
        Inspelningslista(rader: rader,
                         öppna: { öppnad = Öppnad(inspelning: $0, mapp: $1) },
                         kasta: { attKasta = Öppnad(inspelning: $0, mapp: $1) })
    }

    // MARK: - Mail

    @ViewBuilder
    private var mailflik: some View {
        mejlavsnitt
        if !bilagor.isEmpty { bilageavsnitt }
    }

    private var mejlavsnitt: some View {
        avsnitt("Mail", knapp: mejlknapp) {
            switch mejlLäge {
            case .ejHämtat:
                Text(kontakter.flatMap(\.epost).isEmpty
                     ? "Lägg till en kontakt med e-postadress för att kunna söka."
                     : "Inte hämtat än.")
                    .foregroundStyle(.secondary)
            case .hämtar(let vad):
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(vad).foregroundStyle(.secondary)
                }
            case .fel(let text):
                Label(text, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            case .klar:
                if mejl.isEmpty {
                    Text("Inga mejl hittades.").foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(mejl.prefix(25).enumerated()), id: \.offset) { i, m in
                            Button { m.öppna() } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: m.skickat ? "arrow.up" : "arrow.down")
                                        .font(.caption)
                                        .foregroundStyle(m.skickat ? Color.blue : Color.secondary)
                                        .frame(width: 12)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(m.ämne).lineLimit(1)
                                        Text("\(m.skickat ? "Du" : m.avsändarnamn) · \(m.datum.map(DateFormatter.klocka.string) ?? m.datumText)")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 12).padding(.vertical, 9)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            if i < min(25, mejl.count) - 1 { Divider() }
                        }
                    }
                    .kort(hörn: Stil.radhörn)
                    HStack(spacing: 8) {
                        Button("Leta åtaganden i alla \(mejl.count) mejl", action: letaIAllaMejl)
                            .buttonStyle(.link)
                            .disabled(mejlrundaPågår)
                            .help("Går igenom allt som ligger sparat, även äldre mejl, och lägger det som ska göras på tavlan.")
                        if mejlrundaPågår { ProgressView().controlSize(.small) }
                        if let mejlrundaBesked {
                            Text(mejlrundaBesked).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    /// Bilagorna, med markering för vilka som gick att läsa text ur.
    /// Det är texten som är sökbar; en bild utan text säger inget.
    ///
    /// Hopfälld som standard. Ett par mejlväxlingar räcker för att ge trettio
    /// skärmdumpar, och då är det bilagorna man ser i mailfliken i stället för
    /// mejlen. Att de är sökbara är det som betyder något; namnen letar man
    /// sällan efter.
    private var bilageavsnitt: some View {
        let lästa = bilagor.filter { $0.text?.isEmpty == false }
        return DisclosureGroup(isExpanded: $visaBilagor) {
            VStack(spacing: 0) {
                ForEach(Array(bilagor.enumerated()), id: \.element.id) { i, b in
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([b.url])
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: b.text?.isEmpty == false ? "doc.text.magnifyingglass" : "doc")
                                .foregroundStyle(b.text?.isEmpty == false ? Color.accentColor : Color.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(b.namn).lineLimit(1)
                                HStack(spacing: 6) {
                                    Text(b.ämne).lineLimit(1)
                                    Text("· \(b.storlek / 1024) kB")
                                    if let t = b.text, !t.isEmpty {
                                        Text("· \(t.count) tecken text")
                                    }
                                }
                                .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    if i < bilagor.count - 1 { Divider() }
                }
            }
            .kort(hörn: Stil.radhörn)
            .padding(.top, 8)
        } label: {
            Text("Bilagor · \(lästa.count) av \(bilagor.count) sökbara").font(.headline)
        }
    }

    private var mejlknapp: (String, () -> Void)? {
        guard !kontakter.flatMap(\.epost).isEmpty else { return nil }
        if case .hämtar = mejlLäge { return nil }
        return (mejl.isEmpty ? "Hämta" : "Uppdatera", { Task { await hämtaMejl() } })
    }

    // MARK: - Stomme

    private func avsnitt<I: View>(_ rubrik: String,
                                  knapp: (String, () -> Void)? = nil,
                                  @ViewBuilder _ innehåll: () -> I) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Avsnittsrubrik(rubrik)
                Spacer()
                if let knapp { Button(knapp.0, action: knapp.1).buttonStyle(.link) }
            }
            innehåll()
        }
    }

    private var nyttProjektBlad: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nytt projekt hos \(kund.namn)").font(.headline)
            TextField("Namn", text: $nyttProjektnamn)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
                .onSubmit(skapaProjekt)
            HStack {
                Spacer()
                Button("Avbryt") { visaNyttProjekt = false; nyttProjektnamn = "" }
                Button("Skapa", action: skapaProjekt)
                    .keyboardShortcut(.defaultAction)
                    .disabled(nyttProjektnamn.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }

    // MARK: - Data

    private func skapaProjekt() {
        let namn = nyttProjektnamn.trimmingCharacters(in: .whitespaces)
        guard !namn.isEmpty else { return }
        _ = try? arkiv.skapaProjekt(namn: namn, hos: kund)
        nyttProjektnamn = ""
        visaNyttProjekt = false
        läsOm()
    }

    private func läsOm() {
        projekt = arkiv.projekt(för: kund)
        möteskopplingar = arkiv.möteskopplingar(för: kund)
        kontakter = arkiv.kontakter(för: kund)
        inspelningar = arkiv.inspelningar(för: kund)
        ofullständiga = arkiv.ofullständiga(för: kund)
        kopplade = arkiv.kopplade(för: kund)
        räknaDokument()
    }

    // MARK: - Kopplade mappar

    /// Mappar utanför kundmappen — OneDrive, en delad mapp, ett arkiv. De
    /// rörs inte; dokumenten i dem läses in i kunskapsbanken.
    private var mappavsnitt: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Avsnittsrubrik("Kopplade mappar")
                Spacer()
                Button("Koppla mapp", action: väljMapp).buttonStyle(.link)
            }
            if kopplade.isEmpty {
                Text("Peka ut en mapp med kundens material — OneDrive, en delad mapp, ett arkiv. Word, Excel, PowerPoint, PDF, text och bilder läses in i kunskapsbanken så att chatten kan svara ur dem. Mappen rörs inte.")
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
    }

    @ViewBuilder
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
                        kopplade = (try? arkiv.koppla(bort: k, från: kund)) ?? kopplade
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
        panel.message = "Välj en mapp med material om \(kund.namn)"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            kopplade = (try? arkiv.koppla(url, till: kund)) ?? kopplade
        }
        räknaDokument()
        Indexering.dokumentIBakgrunden(för: kund)
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

    /// Kopplade kontakter utan bild får sin profilbild ur macOS Kontakter,
    /// i tysthet — den som redan lagt in bilder där ska inte göra om jobbet.
    private func hämtaKontaktbilder() {
        guard adressbok.harTillgång else { return }
        Task {
            var ändrade = false
            for var k in arkiv.kontakter(för: kund)
            where k.systemID != nil && k.bild == nil {
                guard let data = adressbok.bilddata(för: k) else { continue }
                _ = try? arkiv.sparaKontaktbild(data, för: &k, hos: kund)
                ändrade = true
            }
            if ändrade { kontakter = arkiv.kontakter(för: kund) }
        }
    }

    private func hämtaMöten() async {
        guard kalender.harTillgång else { return }
        let mina = arkiv.kontakter(för: kund)
        let kopplade = arkiv.möteskopplingar(för: kund)
        // Reglerna tar de flesta, men ett möte utan deltagare och utan
        // kundnamn i titeln kan ingen regel känna igen — de tas i anspråk
        // för hand och känns igen på att nyckeln finns.
        möten = kalender.möten().filter {
            Kalendern.hörTill($0, kund: kund, kontakter: mina, kopplingar: kopplade)
        }
    }

    /// - Parameter äldreÄn: hämta om cachen är äldre än så här. Timern och
    ///   återkomsten till appen använder olika gränser: den som just kommit
    ///   tillbaka vill se det senaste, medan en timer som går hela dagen inte
    ///   ska söka i Mail i onödan.
    private func visaMejl(äldreÄn: TimeInterval = 15 * 60) async {
        // Kontakterna läses här och inte ur vyns tillstånd: den fylls av
        // onAppear, som kan hinna köra efter den här uppgiften.
        let adresser = Mailen.adresser(ur: arkiv.kontakter(för: kund))
        guard !adresser.isEmpty else { return }

        guard let cache = arkiv.mailcache(för: kund) else {
            // Ingen cache alls: kunden har aldrig hämtat mejl. Att avbryta här
            // gjorde att första hämtningen aldrig skedde av sig själv.
            await hämtaMejl()
            return
        }
        mejl = cache.mejl
        bilagor = cache.bilagor
        mejlLäge = .klar

        if cache.ålder >= äldreÄn {
            await hämtaMejl()
        } else if cache.bilagor.isEmpty {
            // Mejlen kan vara färska men hämtade innan bilagorna fanns med.
            // Då ska bilagorna hämtas för sig, inte vänta på att cachen
            // åldras ut.
            await hämtaBilagor(adresser)
            mejlLäge = .klar
        }
    }

    private func hämtaMejl() async {
        let adresser = Mailen.adresser(ur: arkiv.kontakter(för: kund))
        guard !adresser.isEmpty else { return }
        mejlLäge = .hämtar("Söker i Mail …")
        let mailen = Mailen()
        var samlat: [Mailen.Mejl] = []
        do {
            for (i, a) in adresser.enumerated() {
                mejlLäge = .hämtar("Söker i Mail: \(a) (\(i + 1) av \(adresser.count))")
                samlat += try await mailen.sök(adress: a, max: 20)
            }
        } catch {
            mejlLäge = .fel(error.localizedDescription)
            return
        }
        var sedda = Set<String>()
        mejl = samlat.filter { sedda.insert($0.id).inserted }
            .sorted { ($0.datum ?? .distantPast) > ($1.datum ?? .distantPast) }
        try? arkiv.sparaMail(mejl, bilagor: bilagor, för: kund)
        // Nya mejl kan bära åtaganden. I bakgrunden, och oberoende av
        // bilagorna: tidigare låg anropet sist i bilagehämtningen, bakom en
        // spärr som avbröt när inga bilagor fanns, så rundan uteblev oftast.
        let mejlen = mejl
        Task { await Uppgiftssamling.frånMejl(mejlen, kund: kund) }

        await hämtaBilagor(adresser)
        mejlLäge = .klar
    }

    /// Går igenom allt som ligger sparat, äldst först. Ett modellanrop per
    /// mejl, så det tar en stund; framstegen visas i mejlavsnittet.
    private func letaIAllaMejl() {
        guard !mejlrundaPågår else { return }
        mejlrundaPågår = true
        mejlrundaBesked = nil
        let mejlen = mejl
        Task {
            let nya = await Uppgiftssamling.frånMejl(mejlen, kund: kund, alla: true) { i, n in
                mejlrundaBesked = "Letar åtaganden i mejl \(i) av \(n) …"
            }
            mejlrundaPågår = false
            mejlrundaBesked = nya == 0
                ? "Inga nya åtaganden i mejlen."
                : "\(nya) nya på tavlan under Att göra."
        }
    }

    private func hämtaBilagor(_ adresser: [String]) async {
        let skript = URL(fileURLWithPath: Bundle.main.bundlePath)
            .appending(path: "Contents/Resources/mail-bilagor.applescript")
        guard FileManager.default.fileExists(atPath: skript.path) else {
            mejlLäge = .fel("Skriptet som hämtar bilagor saknas i appen.")
            return
        }

        mejlLäge = .hämtar("Hämtar bilagor …")
        let mapp = kund.mailmapp.appending(path: "Bilagor")
        var hittade: [Bilagor.Bilaga] = []
        for a in adresser {
            do {
                hittade += try await Bilagor.hämta(adress: a, till: mapp, skript: skript)
            } catch {
                // Ett tyst misslyckande här var orsaken till att bilagorna
                // aldrig dök upp: felet syntes ingenstans.
                mejlLäge = .fel("Bilagorna kunde inte hämtas: \(error.localizedDescription)")
                return
            }
        }
        var sedda = Set<String>()
        hittade = hittade.filter { sedda.insert($0.fil).inserted }
        guard !hittade.isEmpty else { return }

        for (i, b) in hittade.enumerated() {
            mejlLäge = .hämtar("Läser bilaga \(i + 1) av \(hittade.count) — \(b.namn)")
            hittade[i].text = await Bilagor.text(ur: b)
        }
        bilagor = hittade
        try? arkiv.sparaMail(mejl, bilagor: hittade, för: kund)
        indexeraIBakgrunden()
    }

    /// Håller indexet aktuellt utan att man behöver öppna chatten.
    ///
    /// Sökningen bygger inga index — den läser dem som finns. Utan det här
    /// blev nyhämtade mejl och bilagor osökbara tills chatten öppnats.
    private func indexeraIBakgrunden() {
        // Ett spår: dokumentgenomgången tar transkript, anteckningar och mejl
        // med sig. Två parallella genomgångar på egna anslutningar skrev om
        // varandra och fällde den ena.
        Indexering.dokumentIBakgrunden(för: kund)
    }
}

/// Lista över inspelningar, med papperskorg vid hovring.
struct Inspelningslista: View {
    let rader: [(Inspelning, URL)]
    var öppna: (Inspelning, URL) -> Void
    var kasta: (Inspelning, URL) -> Void

    @EnvironmentObject private var session: Inspelningssession
    @State private var hovrad: Int?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rader.enumerated()), id: \.offset) { i, rad in
                ZStack(alignment: .trailing) {
                    Button { öppna(rad.0, rad.1) } label: { innehåll(rad.0, mapp: rad.1) }
                        .buttonStyle(.plain)
                    if hovrad == i {
                        Button { kasta(rad.0, rad.1) } label: {
                            Image(systemName: "trash").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Flytta inspelningen till papperskorgen")
                        .padding(.trailing, 12)
                    }
                }
                .onHover { hovrar in hovrad = hovrar ? i : (hovrad == i ? nil : hovrad) }
                .contextMenu {
                    Button("Visa i Finder") { NSWorkspace.shared.open(rad.1) }
                    Divider()
                    Button("Flytta till papperskorgen", role: .destructive) { kasta(rad.0, rad.1) }
                }
                if i < rader.count - 1 { Divider() }
            }
        }
        .kort(hörn: Stil.radhörn)
    }

    private func innehåll(_ i: Inspelning, mapp: URL) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(i.titel)
                HStack(spacing: 6) {
                    Text(DateFormatter.klocka.string(from: i.inledd))
                    if let p = i.projekt { Text("· \(p)") }
                    if i.enspårig { Text("· importerad") }
                    let namn = Set(i.röstnamn.values).sorted()
                    if !namn.isEmpty { Text("· \(namn.joined(separator: ", "))").lineLimit(1) }
                    if let steg = pågår(mapp) {
                        ProgressView().controlSize(.mini)
                        Text(steg).foregroundStyle(.orange)
                    } else if !i.efterbearbetad {
                        Märke(text: "live", färg: .orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(formateraLängd(i.längd))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .contentShape(.rect)
    }

    /// Var bearbetningen står, för raden vars inspelning just nu jobbas på.
    private func pågår(_ mapp: URL) -> String? {
        guard session.bearbetadMapp == mapp else { return nil }
        if session.sammanfattar { return "Sammanfattar …" }
        if session.analyserarRöster { return "Delar upp röster …" }
        if session.efterbearbetar {
            return "Transkriberar \(Int(session.efterbearbetningsandel * 100)) % …"
        }
        return nil
    }
}

/// Väljaren för möten som reglerna inte känner igen.
///
/// Kalenderposter utan deltagarlista och utan kundnamn i titeln — vanligt
/// när en inbjudan vidarebefordrats eller skrivits in för hand — kan ingen
/// regel para ihop med en kund. Här tas de i anspråk med ett klick.
struct Mötesplockare: View {
    let kund: Kund
    var vidVal: () -> Void

    @EnvironmentObject private var arkiv: Arkivet
    @EnvironmentObject private var kalender: Kalendern
    @Environment(\.dismiss) private var stäng

    @State private var kandidater: [Kalendern.Möte] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Lägg till möte hos \(kund.namn)").font(.headline)
                Spacer()
            }
            .padding(16)
            Divider()

            if kandidater.isEmpty {
                TomtLäge(ikon: "calendar", rubrik: "Inga fler möten",
                         text: "Alla kommande möten i kalendern hör redan till någon kund.")
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(kandidater.enumerated()), id: \.element.id) { i, m in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.titel)
                                    Text(DateFormatter.klocka.string(from: m.start))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Lägg till") {
                                    try? arkiv.kopplaMöte(m.id, till: nil, för: kund)
                                    vidVal()
                                    stäng()
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            if i < kandidater.count - 1 { Divider() }
                        }
                    }
                }
            }

            Divider()
            HStack {
                Spacer()
                Button("Stäng") { stäng() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 480, height: 380)
        .onAppear(perform: läsIn)
    }

    /// Alla kommande möten som inte redan hör till någon kund.
    private func läsIn() {
        var tagna = Set<String>()
        for k in arkiv.kunder {
            let kontakter = arkiv.kontakter(för: k)
            let kopplade = arkiv.möteskopplingar(för: k)
            for m in kalender.möten()
            where kopplade[m.id] != nil || Kalendern.hör(m, till: k, kontakter: kontakter) {
                tagna.insert(m.id)
            }
        }
        kandidater = kalender.möten().filter { !tagna.contains($0.id) }
    }
}

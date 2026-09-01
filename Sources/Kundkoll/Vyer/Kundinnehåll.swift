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

    @State private var visaNyttProjekt = false
    @State private var nyttProjektnamn = ""
    @State private var visaKontakter = false
    @State private var visaImport = false
    @State private var släpptFil: URL?
    @State private var öppnad: Öppnad?
    @State private var attKasta: Öppnad?
    @State private var ofullständiga: [(mapp: URL, storlek: Int)] = []
    @State private var briefing: Kalendern.Möte?
    @State private var slutför: URL?
    @State private var slutförsteg = ""

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
            // Indexet hålls aktuellt från start — inte först när ett mejl
            // råkar hämtas eller chatten öppnas. Ändringskontrollen gör att
            // ett aktuellt index kostar nästan ingenting att bekräfta.
            indexeraIBakgrunden()
        }
        // Ett avslutat möte — och senare arkivtranskriptet, rösterna och
        // sammanfattningen — ska dyka upp utan att appen startas om.
        .onChange(of: arkiv.sparningar) { läsOm() }
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
        kontaktavsnitt
        if !inspelningar.isEmpty {
            avsnitt("Senaste inspelningarna") {
                inspelningslista(Array(inspelningar.prefix(3)))
            }
        }
    }

    @ViewBuilder
    private var mötesavsnitt: some View {
        avsnitt(möten.isEmpty ? "Möten" : "Kommande möten") {
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
                            // Mötet bär titel och deltagare, och mikrofonen är
                            // den som användes sist. Inget att fylla i.
                            Inspelningsfönster.öppna(kund: kund, projekt: nil, möte: m)
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
                        VStack(alignment: .leading, spacing: 2) {
                            Text(k.namn)
                            if let r = k.roll {
                                Text(r).font(.caption).foregroundStyle(.secondary)
                            } else if let e = k.förstaEpost {
                                Text(e).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
        kontakter = arkiv.kontakter(för: kund)
        inspelningar = arkiv.inspelningar(för: kund)
        ofullständiga = arkiv.ofullständiga(för: kund)
    }

    private func hämtaMöten() async {
        guard kalender.harTillgång else { return }
        let mina = arkiv.kontakter(för: kund)
        möten = kalender.möten().filter { Kalendern.hör($0, till: kund, kontakter: mina) }
    }

    /// - Parameter äldreÄn: hämta om cachen är äldre än så här. Timern och
    ///   återkomsten till appen använder olika gränser: den som just kommit
    ///   tillbaka vill se det senaste, medan en timer som går hela dagen inte
    ///   ska söka i Mail i onödan.
    private func visaMejl(äldreÄn: TimeInterval = 15 * 60) async {
        // Kontakterna läses här och inte ur vyns tillstånd: den fylls av
        // onAppear, som kan hinna köra efter den här uppgiften.
        let adresser = Array(Set(arkiv.kontakter(för: kund).flatMap(\.epost))).prefix(5)
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
            await hämtaBilagor(Array(adresser))
            mejlLäge = .klar
        }
    }

    private func hämtaMejl() async {
        let adresser = Array(Set(arkiv.kontakter(för: kund).flatMap(\.epost))).prefix(5)
        guard !adresser.isEmpty else { return }
        mejlLäge = .hämtar("Söker i Mail …")
        let mailen = Mailen()
        var samlat: [Mailen.Mejl] = []
        do {
            for a in adresser { samlat += try await mailen.sök(adress: a, max: 20) }
        } catch {
            mejlLäge = .fel(error.localizedDescription)
            return
        }
        var sedda = Set<String>()
        mejl = samlat.filter { sedda.insert($0.id).inserted }
            .sorted { ($0.datum ?? .distantPast) > ($1.datum ?? .distantPast) }
        try? arkiv.sparaMail(mejl, bilagor: bilagor, för: kund)

        await hämtaBilagor(Array(adresser))
        mejlLäge = .klar
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
        // Nya mejl kan bära åtaganden. Görs efter indexeringen, i bakgrunden,
        // så att listan inte står och väntar.
        let mejlen = mejl
        Task { await Uppgiftssamling.frånMejl(mejlen, kund: kund) }
    }

    /// Håller indexet aktuellt utan att man behöver öppna chatten.
    ///
    /// Sökningen bygger inga index — den läser dem som finns. Utan det här
    /// blev nyhämtade mejl och bilagor osökbara tills chatten öppnats.
    private func indexeraIBakgrunden() {
        let kund = kund
        Task.detached(priority: .utility) {
            guard let bank = try? await Kunskapsbank(kund: kund) else { return }
            try? await Indexering.kör(för: kund, bank: bank)
            await Inbäddare.kör(bank: bank)
        }
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

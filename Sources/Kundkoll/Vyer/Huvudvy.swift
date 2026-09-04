import SwiftUI
import AppKit

/// Appens ram: kunder och projekt till vänster, deras innehåll i mitten, en
/// chatt som kan fällas ut till höger, och en rad längst ned när en inspelning
/// pågår.
///
/// Ingenting av det här är modalt. En inspelning kan pågå i sitt eget fönster
/// medan man läser gamla transkript eller frågar chatten — det var hela
/// poängen med att lämna bladen.
struct Huvudvy: View {
    @EnvironmentObject private var arkiv: Arkivet
    @EnvironmentObject private var session: Inspelningssession
    @EnvironmentObject private var kalender: Kalendern

    @State private var val: Val?
    @State private var visaChatt = false
    @State private var visaNyKund = false
    @State private var nyttKundnamn = ""
    @State private var visaNyckel = false
    @State private var utfällda: Set<String> = []
    @State private var visaSök = false
    @State private var visaPalett = false
    /// Möte respektive uppgift öppnad från paletten.
    @State private var palettMöte: Palettmöte?
    @State private var palettUppgift: Palettuppgift?

    struct Palettmöte: Identifiable {
        let kund: Kund, inspelning: Inspelning, mapp: URL
        var id: UUID { inspelning.id }
    }
    struct Palettuppgift: Identifiable {
        let kund: Kund, uppgift: Uppgift
        var id: UUID { uppgift.id }
    }
    @State private var briefing: Briefingval?
    struct Briefingval: Identifiable {
        let kund: Kund
        let möte: Kalendern.Möte?
        var id: String { möte?.id ?? kund.namn }
    }

    /// Vad som är valt i sidopanelen.
    enum Val: Hashable {
        case minVecka
        case kund(Kund)
        case projekt(Projekt)

        var kund: Kund? {
            if case .kund(let k) = self { return k }
            return nil
        }
        var projekt: Projekt? {
            if case .projekt(let p) = self { return p }
            return nil
        }
    }

    var body: some View {
        NavigationSplitView {
            sidopanel
        } detail: {
            HStack(spacing: 0) {
                innehåll
                if visaChatt, let kund = valdKund {
                    Divider()
                    Chattpanel(kund: kund, projekt: val?.projekt)
                        .frame(width: 380)
                        .transition(AnyTransition.move(edge: .trailing))
                }
            }
            .toolbar { verktyg }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if session.pågår || session.efterbearbetar {
                    Inspelningsrad()
                }
                Importrad()
                Tidursrad()
            }
        }
        .sheet(isPresented: $visaSök) {
            Sökvy { kund in val = .kund(kund) }
        }
        .sheet(isPresented: $visaPalett) {
            Kommandopalett { träff in
                switch träff.slag {
                case .kund(let k): val = .kund(k)
                case .projekt(let p, _): val = .projekt(p)
                case .minVecka: val = .minVecka
                case .inspelning(let i, let mapp, let kund):
                    val = .kund(kund)
                    palettMöte = Palettmöte(kund: kund, inspelning: i, mapp: mapp)
                case .uppgift(let u, let kund):
                    val = .kund(kund)
                    palettUppgift = Palettuppgift(kund: kund, uppgift: u)
                }
            }
        }
        .sheet(item: $palettMöte) { v in
            Transkriptvy(kund: v.kund, inspelning: v.inspelning, mapp: v.mapp)
        }
        .sheet(item: $palettUppgift) { v in
            Uppgiftsredigering(uppgift: v.uppgift, kund: v.kund,
                               projekt: arkiv.projekt(för: v.kund), vidSparat: {})
        }
        .onReceive(NotificationCenter.default.publisher(for: .palett)) { _ in visaPalett = true }
        .sheet(item: $briefing) { v in
            Briefingvy(kund: v.kund, möte: v.möte) { i, mapp in
                palettMöte = Palettmöte(kund: v.kund, inspelning: i, mapp: mapp)
            }
        }
        // Ett klick på en briefingnotis landar här: rätt kund väljs och
        // briefen öppnas.
        .onReceive(NotificationCenter.default.publisher(for: .öppnaKund)) { n in
            guard let namn = n.object as? String,
                  let kund = arkiv.kunder.first(where: { $0.namn == namn }) else { return }
            val = .kund(kund)
            if let mid = n.userInfo?["möte"] as? String {
                let möte = kalender.möten(tillDagar: 7).first { $0.id == mid }
                briefing = Briefingval(kund: kund, möte: möte)
            }
        }
        // Påminnelserna en kvart före kundmöten bokas om varje gång kalendern
        // ändras, så att flyttade möten följer med och avbokade tystnar.
        .task { planeraBriefingar() }
        .onChange(of: kalender.ändringar) { planeraBriefingar() }
        .sheet(isPresented: $visaNyKund) { nyKundBlad }
        .sheet(isPresented: $visaNyckel) { Modellvy() }
        .onReceive(NotificationCenter.default.publisher(for: .nyKund)) { _ in visaNyKund = true }
        .onReceive(NotificationCenter.default.publisher(for: .sök)) { _ in visaSök = true }
        .onReceive(NotificationCenter.default.publisher(for: .visaNyckel)) { _ in visaNyckel = true }
        .onAppear {
            if val == nil, let första = arkiv.kunder.first { val = .kund(första) }
        }
    }

    /// Kundens rad: sigillet gör att samma kund ser likadan ut överallt.
    private func kundrad(_ kund: Kund) -> some View {
        HStack(spacing: 8) {
            Sigill(namn: kund.namn, sida: 22)
            Text(kund.namn)
        }
        .padding(.vertical, 2)
    }

    /// Bokar briefingnotiser för alla kundmatchade möten den närmaste veckan.
    private func planeraBriefingar() {
        guard kalender.harTillgång else { return }
        let möten = kalender.möten(tillDagar: 7)
        var par: [(kund: String, möte: Kalendern.Möte)] = []
        for kund in arkiv.kunder {
            let kontakter = arkiv.kontakter(för: kund)
            let kopplade = arkiv.möteskopplingar(för: kund)
            for m in möten
            where Kalendern.hörTill(m, kund: kund, kontakter: kontakter, kopplingar: kopplade) {
                par.append((kund.namn, m))
            }
        }
        guard !par.isEmpty else { return }
        Notiser.begär()
        Notiser.planeraBriefingar(för: par)
    }

    private var valdKund: Kund? {
        switch val {
        case .kund(let k): k
        case .projekt(let p): arkiv.kunder.first { $0.namn == p.kundnamn }
        case .minVecka, nil: nil
        }
    }

    // MARK: - Sidopanel

    private var sidopanel: some View {
        List(selection: $val) {
            Label("Min vecka", systemImage: "calendar.badge.checkmark")
                .tag(Val.minVecka)
            ForEach(arkiv.kunder) { kund in
                let projekt = arkiv.projekt(för: kund)
                if projekt.isEmpty {
                    kundrad(kund).tag(Val.kund(kund))
                } else {
                    DisclosureGroup(isExpanded: bindning(för: kund)) {
                        ForEach(projekt) { p in
                            Label(p.namn, systemImage: "folder")
                                .tag(Val.projekt(p))
                        }
                    } label: {
                        kundrad(kund).tag(Val.kund(kund))
                    }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        .overlay {
            if arkiv.kunder.isEmpty {
                ContentUnavailableView {
                    Label("Inga kunder", systemImage: "person.2")
                } description: {
                    Text("Lägg till din första kund för att komma igång.")
                } actions: {
                    Button("Ny kund") { visaNyKund = true }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                visaNyKund = true
            } label: {
                Label("Ny kund", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(10)
        }
    }

    /// Kundens gren minns om den är utfälld.
    private func bindning(för kund: Kund) -> Binding<Bool> {
        Binding(
            get: { utfällda.contains(kund.id) || val?.projekt?.kundnamn == kund.namn },
            set: { utfälld in
                if utfälld { utfällda.insert(kund.id) } else { utfällda.remove(kund.id) }
            })
    }

    // MARK: - Innehåll

    @ViewBuilder
    private var innehåll: some View {
        switch val {
        case .kund(let kund):
            Kundinnehåll(kund: kund, väljProjekt: { val = .projekt($0) })
                .id(kund.id)
        case .projekt(let projekt):
            if let kund = valdKund {
                Projektinnehåll(kund: kund, projekt: projekt)
                    .id(projekt.id)
            }
        case .minVecka:
            Minveckavy()
        case nil:
            ContentUnavailableView("Välj en kund", systemImage: "person.2")
        }
    }

    @ToolbarContentBuilder
    private var verktyg: some ToolbarContent {
        if let kund = valdKund {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    starta(kund: kund)
                } label: {
                    Label("Spela in", systemImage: "record.circle")
                }
                .disabled(session.pågår)
                .help(session.pågår ? "En inspelning pågår redan" : "Spela in ett samtal")
            }
            ToolbarItem {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { visaChatt.toggle() }
                } label: {
                    Label("Chatt", systemImage: "bubble.left.and.text.bubble.right")
                }
                .help(visaChatt ? "Dölj chatten" : "Fråga om det som sagts och skrivits")
            }
            ToolbarItem {
                Button { visaSök = true } label: {
                    Label("Sök", systemImage: "magnifyingglass")
                }
                .help("Sök i allt material hos alla kunder")
            }
            ToolbarItem {
                Menu {
                    Button("Visa i Finder") { NSWorkspace.shared.open(kund.mapp) }
                    if Obsidian.finns {
                        Button("Öppna i Obsidian") {
                            Obsidian.öppna(kund.mapp, valvrot: kund.mapp)
                        }
                    }
                    Divider()
                    Button("Inställningar …") { visaNyckel = true }
                        .keyboardShortcut(",", modifiers: .command)
                } label: {
                    Label("Mer", systemImage: "ellipsis.circle")
                }
            }
        }
    }

    private func starta(kund: Kund) {
        Inspelningsfönster.öppna(kund: kund, projekt: val?.projekt, möte: nil)
    }

    // MARK: - Ny kund

    private var nyKundBlad: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ny kund").font(.headline)
            TextField("Namn", text: $nyttKundnamn)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
                .onSubmit(skapa)
            HStack {
                Spacer()
                Button("Avbryt") { visaNyKund = false; nyttKundnamn = "" }
                Button("Skapa", action: skapa)
                    .keyboardShortcut(.defaultAction)
                    .disabled(nyttKundnamn.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }

    private func skapa() {
        let namn = nyttKundnamn.trimmingCharacters(in: .whitespaces)
        guard !namn.isEmpty else { return }
        if let ny = try? arkiv.skapaKund(namn: namn) { val = .kund(ny) }
        nyttKundnamn = ""
        visaNyKund = false
    }
}

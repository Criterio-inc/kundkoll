import SwiftUI

/// ⌘K — skriv några bokstäver, hamna rätt.
///
/// Med några kunder blir sidopanelsklickandet den långsammaste vägen till
/// allt. Paletten söker i kunder, projekt, möten och uppgifter på en gång
/// och körs helt med tangentbordet: pilar, retur, klart.
struct Kommandopalett: View {
    var kör: (Träff) -> Void
    @EnvironmentObject private var arkiv: Arkivet
    @Environment(\.dismiss) private var stäng

    @State private var text = ""
    @State private var vald = 0
    @State private var allt: [Träff] = []
    @FocusState private var fokus: Bool

    /// Något paletten kan hoppa till.
    struct Träff: Identifiable {
        enum Slag {
            case kund(Kund)
            case projekt(Projekt, Kund)
            case inspelning(Inspelning, URL, Kund)
            case uppgift(Uppgift, Kund)
            case minVecka
        }
        let id = UUID()
        let slag: Slag

        var namn: String {
            switch slag {
            case .kund(let k): k.namn
            case .projekt(let p, _): p.namn
            case .inspelning(let i, _, _): i.titel
            case .uppgift(let u, _): u.vad
            case .minVecka: "Min vecka"
            }
        }

        var detalj: String {
            switch slag {
            case .kund: "kund"
            case .projekt(_, let k): k.namn
            case .inspelning(let i, _, let k):
                "\(k.namn) · \(DateFormatter.kortdag.string(from: i.inledd))"
            case .uppgift(_, let k): "\(k.namn) · att göra"
            case .minVecka: "alla kunder"
            }
        }

        var ikon: String {
            switch slag {
            case .kund: "person.2"
            case .projekt: "folder"
            case .inspelning: "waveform"
            case .uppgift: "checklist"
            case .minVecka: "calendar.badge.checkmark"
            }
        }

        /// Ordningen mellan slag när flera matchar lika bra.
        var vikt: Int {
            switch slag {
            case .kund: 0
            case .projekt: 1
            case .minVecka: 2
            case .uppgift: 3
            case .inspelning: 4
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Kund, projekt, möte eller uppgift …", text: $text)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($fokus)
                    .onSubmit(körVald)
            }
            .padding(14)

            if !träffar.isEmpty {
                Divider()
                ScrollViewReader { rulle in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(träffar.enumerated()), id: \.element.id) { i, t in
                                rad(t, markerad: i == vald)
                                    .id(i)
                                    .onTapGesture { kör(t); stäng() }
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 320)
                    .onChange(of: vald) { rulle.scrollTo(vald) }
                }
            }
        }
        .frame(width: 560)
        .onAppear {
            fokus = true
            läsIn()
        }
        .onChange(of: text) { vald = 0 }
        .onKeyPress(.downArrow) {
            vald = min(vald + 1, max(0, träffar.count - 1)); return .handled
        }
        .onKeyPress(.upArrow) {
            vald = max(0, vald - 1); return .handled
        }
    }

    private func rad(_ t: Träff, markerad: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: t.ikon)
                .frame(width: 18)
                .foregroundStyle(markerad ? .white : .secondary)
            Text(t.namn).lineLimit(1)
            Spacer()
            Text(t.detalj)
                .font(.caption)
                .foregroundStyle(markerad ? Color.white.opacity(0.8) : Color.secondary.opacity(0.7))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(markerad ? Color.accentColor : .clear, in: .rect(cornerRadius: 6))
        .foregroundStyle(markerad ? .white : .primary)
        .contentShape(.rect)
    }

    private func körVald() {
        guard träffar.indices.contains(vald) else { return }
        kör(träffar[vald])
        stäng()
    }

    // MARK: - Sökning

    private var träffar: [Träff] {
        Self.sök(text, i: allt)
    }

    /// Utbruten för att kunna provas: prefix slår ordprefix som slår
    /// förekomst var som helst, och vid lika avgör slaget.
    static func sök(_ text: String, i allt: [Träff]) -> [Träff] {
        let sökt = text.trimmingCharacters(in: .whitespaces)
        guard !sökt.isEmpty else {
            // Tom sökning visar det man oftast vill nå: kunder och Min vecka.
            return allt.filter {
                if case .inspelning = $0.slag { return false }
                if case .uppgift = $0.slag { return false }
                return true
            }
        }
        func poäng(_ t: Träff) -> Int? {
            let namn = t.namn
            if namn.range(of: sökt, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil {
                return 0
            }
            if namn.range(of: " " + sökt, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                return 1
            }
            if namn.range(of: sökt, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                return 2
            }
            return nil
        }
        return allt
            .compactMap { t in poäng(t).map { (t, $0) } }
            .sorted { ($0.1, $0.0.vikt) < ($1.1, $1.0.vikt) }
            .prefix(20)
            .map(\.0)
    }

    private func läsIn() {
        var ut: [Träff] = [Träff(slag: .minVecka)]
        for kund in arkiv.kunder {
            ut.append(Träff(slag: .kund(kund)))
            for p in arkiv.projekt(för: kund) {
                ut.append(Träff(slag: .projekt(p, kund)))
            }
            for (i, mapp) in arkiv.inspelningar(för: kund) {
                ut.append(Träff(slag: .inspelning(i, mapp, kund)))
            }
            for u in arkiv.uppgifter(för: kund) where u.läge != .klart {
                ut.append(Träff(slag: .uppgift(u, kund)))
            }
        }
        allt = ut
    }
}

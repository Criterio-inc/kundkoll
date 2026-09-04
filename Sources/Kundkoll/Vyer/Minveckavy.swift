import SwiftUI

/// Allt jag har att göra, hos alla kunder, sorterat på hur bråttom det är.
///
/// Tavlorna är per kund men arbetsdagen är det inte. Det här är en läsvy
/// över samma uppgifter, i två spalter: det jag ska göra och det jag väntar
/// på från andra. I varje spalt försenat överst, sedan veckan, sedan resten.
struct Minveckavy: View {
    @EnvironmentObject private var arkiv: Arkivet

    @State private var rader: [(kund: Kund, uppgift: Uppgift)] = []
    @State private var redigerad: Redigeringsval?

    private struct Redigeringsval: Identifiable {
        let kund: Kund
        let uppgift: Uppgift
        var id: UUID { uppgift.id }
    }

    private enum Grupp: String, CaseIterable {
        case försenat = "Försenat"
        case veckan = "Denna vecka"
        case senare = "Senare"
        case utanDatum = "Utan datum"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Avsnittsrubrik("Min vecka")
                    Spacer()
                    Text(sammanfattning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .top, spacing: 24) {
                    spalt("Jag ska", mina, tom: "Inget jag ska göra hos någon kund. Skönt.")
                    spalt("Jag väntar på", väntade, tom: "Inget jag väntar på från någon.")
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Stil.botten)
        .onAppear(perform: läsOm)
        // Ett kort som bockats av i mötesvyn, eller kommit ur en mejlrunda,
        // ska synas här utan att man klickar bort och tillbaka.
        .onChange(of: arkiv.sparningar) { läsOm() }
        .sheet(item: $redigerad) { v in
            Uppgiftsredigering(uppgift: v.uppgift, kund: v.kund,
                               projekt: arkiv.projekt(för: v.kund),
                               vidSparat: läsOm)
        }
    }

    private var mina: [(kund: Kund, uppgift: Uppgift)] { rader.filter { $0.uppgift.mitt } }
    private var väntade: [(kund: Kund, uppgift: Uppgift)] { rader.filter { !$0.uppgift.mitt } }

    private var sammanfattning: String {
        guard !rader.isEmpty else { return "" }
        let kunder = Set(rader.map(\.kund.namn)).count
        var delar: [String] = []
        if !mina.isEmpty { delar.append("\(mina.count) att göra") }
        if !väntade.isEmpty { delar.append("\(väntade.count) väntar jag på") }
        return delar.joined(separator: " · ") + " hos " + (kunder == 1 ? "en kund" : "\(kunder) kunder")
    }

    /// En spalt: rubrik, sedan grupperna försenat, veckan, senare, utan datum.
    private func spalt(_ rubrik: String, _ urval: [(kund: Kund, uppgift: Uppgift)],
                       tom: String) -> some View {
        let grupperade = Self.grupperade(urval)
        return VStack(alignment: .leading, spacing: 16) {
            Text(rubrik).font(.title3.weight(.semibold))
            if urval.isEmpty {
                Text(tom).foregroundStyle(.secondary)
            }
            ForEach(Grupp.allCases, id: \.self) { grupp in
                let ivarje = grupperade[grupp] ?? []
                if !ivarje.isEmpty {
                    avsnitt(grupp, ivarje)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func avsnitt(_ grupp: Grupp, _ ivarje: [(kund: Kund, uppgift: Uppgift)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(grupp.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(grupp == .försenat ? Color.red : Color.primary)
                Text("\(ivarje.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(ivarje.enumerated()), id: \.element.uppgift.id) { i, rad in
                    self.rad(rad)
                    if i < ivarje.count - 1 { Divider() }
                }
            }
            .kort(hörn: Stil.radhörn)
        }
    }

    private func rad(_ rad: (kund: Kund, uppgift: Uppgift)) -> some View {
        let u = rad.uppgift
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button {
                bocka(rad)
            } label: {
                Image(systemName: "circle").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(u.mitt ? "Gör klar" : "Har kommit")

            VStack(alignment: .leading, spacing: 2) {
                Text(u.vad).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(rad.kund.namn)
                    if let p = u.projekt { Text("· \(p)") }
                    if let vem = u.vem, !u.mitt || Uppgift.gissaRiktning(vem) != .jag {
                        Text("· \(vem)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let förslag = u.klartFörslag {
                    Klartförslag(text: förslag,
                                 bekräfta: { bocka(rad) },
                                 behåll: { var k = u; k.klartFörslag = nil; try? arkiv.uppdatera(k, för: rad.kund); läsOm() })
                }
            }
            Spacer()
            if let senast = u.senast {
                Text(DateFormatter.kortdag.string(from: senast))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(u.försenad ? Color.red : Color.secondary)
            } else if let när = u.när {
                Text(när).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .contentShape(.rect)
        .onTapGesture { redigerad = Redigeringsval(kund: rad.kund, uppgift: u) }
    }

    // MARK: - Urval

    private static func grupperade(_ urval: [(kund: Kund, uppgift: Uppgift)])
        -> [Grupp: [(kund: Kund, uppgift: Uppgift)]] {
        Dictionary(grouping: urval) { Grupp(rawValue: grupp($0.uppgift)) ?? .utanDatum }
            .mapValues { $0.sorted {
                ($0.uppgift.senast ?? .distantFuture, $0.uppgift.skapad)
                    < ($1.uppgift.senast ?? .distantFuture, $1.uppgift.skapad)
            } }
    }

    /// Var en uppgift hör hemma i veckan. Utbruten för att kunna provas.
    static func grupp(_ u: Uppgift, idag: Date = Date()) -> String {
        guard let senast = u.senast else { return Grupp.utanDatum.rawValue }
        let kalender = Calendar.current
        if senast < kalender.startOfDay(for: idag) { return Grupp.försenat.rawValue }
        if kalender.isDate(senast, equalTo: idag, toGranularity: .weekOfYear) {
            return Grupp.veckan.rawValue
        }
        return Grupp.senare.rawValue
    }

    private func bocka(_ rad: (kund: Kund, uppgift: Uppgift)) {
        var klar = rad.uppgift
        klar.läge = .klart
        try? arkiv.uppdatera(klar, för: rad.kund)
        läsOm()
    }

    private func läsOm() {
        rader = arkiv.kunder.flatMap { kund in
            arkiv.uppgifter(för: kund)
                .filter { $0.läge != .klart }
                .map { (kund, $0) }
        }
    }
}

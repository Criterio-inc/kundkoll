import SwiftUI

/// «Kom igång»: arbetssättet i åtta steg med bockar appen sätter själv,
/// och en «Visa mig» per steg som tar en dit det händer.
struct Komigångvy: View {
    var visa: (Komigång.Mål) -> Void

    @EnvironmentObject private var arkiv: Arkivet
    @State private var steg: [Komigång.Steg] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Avsnittsrubrik("Kom igång")
                    Spacer()
                    Text(sammanfattning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Kundkoll bygger på ett arbetssätt. Kunden är relationen: kontakterna, mejlen, mötena. Projektet är ett betalt uppdrag, och det är dit allt som kommer in hamnar: åtaganden ur mejl, inspelningar, anteckningar, tid. Dagen börjar i Min vecka, mötet börjar i briefen, och tavlan hålls levande av dig och av det som sägs på nästa möte. Stegen här står i den ordning man gör dem, och bocken sätts när steget är gjort.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 0) {
                    ForEach(Array(steg.enumerated()), id: \.element.id) { i, s in
                        rad(i + 1, s)
                        if i < steg.count - 1 { Divider() }
                    }
                }
                .kort(hörn: Stil.radhörn)

                HStack {
                    Text(steg.allSatisfy(\.klar)
                         ? "Allt är på plats. Sidan finns kvar under Hjälp."
                         : "Sidan ligger i sidopanelen tills allt är gjort, och finns alltid under Hjälp.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !Komigång.dold {
                        Button("Dölj i sidopanelen") { Komigång.dold = true; arkiv.läsOm() }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Stil.botten)
        .onAppear(perform: läsOm)
        .onChange(of: arkiv.sparningar) { läsOm() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in läsOm() }
    }

    private var sammanfattning: String {
        let klara = steg.filter(\.klar).count
        return steg.isEmpty ? "" : "\(klara) av \(steg.count) gjorda"
    }

    private func rad(_ nummer: Int, _ s: Komigång.Steg) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: s.klar ? "checkmark.circle.fill" : "\(nummer).circle")
                .font(.title3)
                .foregroundStyle(s.klar ? Color.green : Color.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(s.rubrik)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(s.klar ? Color.secondary : Color.primary)
                Text(s.varför)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button("Visa mig") { visa(s.mål) }
                .buttonStyle(.link)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    private func läsOm() { steg = Komigång.steg(arkiv: arkiv) }
}

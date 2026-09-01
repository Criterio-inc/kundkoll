import SwiftUI
import AppKit

struct Transkriptvy: View {
    let kund: Kund
    @State var inspelning: Inspelning
    let mapp: URL
    @Environment(\.dismiss) private var stäng
    @State private var visaRöster = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(inspelning.titel).font(.headline)
                    Text("\(DateFormatter.klocka.string(from: inspelning.inledd)) · \(formateraLängd(inspelning.längd))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !inspelning.efterbearbetad {
                    Text("live")
                        .font(.caption)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.orange.opacity(0.2), in: .capsule)
                }
                if inspelning.yttranden.contains(where: { $0.röstgrupp != nil }) {
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
            }
            .padding(16)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if let sam = inspelning.sammanfattning, !sam.tom {
                        sammanfattning(sam)
                        Divider().padding(.vertical, 6)
                    }
                    ForEach(inspelning.yttranden) { y in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(y.etikett(inspelning.röstnamn, enspårig: inspelning.enspårig))
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(färg(y))
                                Text(y.tidsstämpel)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                            Text(y.text)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(20)
            }

            Divider()
            HStack {
                Spacer()
                Button("Stäng") { stäng() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 700, height: 620)
        .sheet(isPresented: $visaRöster) {
            Röstvy(kund: kund, mapp: mapp, inspelning: inspelning) { inspelning = $0 }
        }
    }

    /// Vad mötet landade i, före transkriptet.
    @ViewBuilder
    private func sammanfattning(_ s: Mötessammanfattning) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if !s.kärna.isEmpty {
                Text(s.kärna)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !s.åtaganden.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Att göra").font(.subheadline.weight(.semibold))
                    ForEach(Array(s.åtaganden.enumerated()), id: \.element.id) { i, å in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Button {
                                bocka(i)
                            } label: {
                                Image(systemName: å.klart ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(å.klart ? Color.green : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(å.vad)
                                    .strikethrough(å.klart)
                                    .foregroundStyle(å.klart ? .secondary : .primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                if å.vem != nil || å.när != nil {
                                    Text([å.vem, å.när].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            if !s.beslut.isEmpty { punktlista("Beslut", s.beslut) }
            if !s.öppet.isEmpty { punktlista("Öppna frågor", s.öppet) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 10))
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

    /// Bockar av ett åtagande. Sparas direkt, så att det står kvar i markdown
    /// och syns i Obsidian.
    private func bocka(_ i: Int) {
        guard var sam = inspelning.sammanfattning, i < sam.åtaganden.count else { return }
        sam.åtaganden[i].klart.toggle()
        inspelning.sammanfattning = sam
        try? Arkivet.shared.spara(inspelning, i: mapp)
    }

    /// Egen färg per röst, så att man ser talarbyten utan att läsa namnen.
    private func färg(_ y: Yttrande) -> Color {
        guard y.röst == .motpart || inspelning.enspårig else { return .blue }
        let paletten: [Color] = [.purple, .orange, .teal, .pink, .indigo, .brown]
        guard let g = y.röstgrupp else { return .purple }
        return paletten[g % paletten.count]
    }
}

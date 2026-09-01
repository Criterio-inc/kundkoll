import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Uppgifterna hos en kund, i tre spalter.
///
/// Korten kommer från möten och mejl utan att någon skriver in dem: mötets
/// åtaganden plockas ur sammanfattningen, mejlens ur texten när de hämtas.
struct Kanbanvy: View {
    let kund: Kund
    /// Sätts för att bara visa uppgifter som hör till ett projekt.
    var projekt: Projekt?

    @EnvironmentObject private var arkiv: Arkivet
    @State private var uppgifter: [Uppgift] = []
    @State private var ny = ""
    @State private var dras: Uppgift?

    private var synliga: [Uppgift] {
        guard let projekt else { return uppgifter }
        return uppgifter.filter { $0.projekt == projekt.namn }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Att göra").font(.headline)
                Spacer()
                if Obsidian.finns {
                    Button("Öppna i Obsidian") {
                        Obsidian.öppna(kund.mapp.appending(path: "Att göra.md"),
                                       valvrot: kund.mapp)
                    }
                    .buttonStyle(.link)
                }
            }

            HStack(alignment: .top, spacing: 12) {
                ForEach(Uppgift.Läge.allCases) { läge in
                    spalt(läge)
                }
            }

            HStack(spacing: 8) {
                TextField("Lägg till något att göra", text: $ny)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(läggTill)
                Button("Lägg till", action: läggTill)
                    .disabled(ny.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear(perform: läsOm)
    }

    private func spalt(_ läge: Uppgift.Läge) -> some View {
        let ivarje = synliga.filter { $0.läge == läge }
            .sorted { $0.skapad > $1.skapad }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(läge.namn).font(.subheadline.weight(.semibold))
                Text("\(ivarje.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
            }
            ForEach(ivarje) { u in kort(u) }
            if ivarje.isEmpty {
                Text(läge == .attGöra ? "Inget här än" : " ")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 10))
        // Släpp ett kort i spalten för att flytta det dit.
        .onDrop(of: [.text], isTargeted: nil) { _ in
            guard let dras, dras.läge != läge else { return false }
            var flyttad = dras
            flyttad.läge = läge
            try? arkiv.uppdatera(flyttad, för: kund)
            self.dras = nil
            läsOm()
            return true
        }
    }

    private func kort(_ u: Uppgift) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(u.vad)
                .font(.callout)
                .strikethrough(u.läge == .klart)
                .foregroundStyle(u.läge == .klart ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)

            if u.vem != nil || u.när != nil {
                Text([u.vem, u.när].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                Image(systemName: u.ursprung.ikon).font(.system(size: 9))
                if let titel = u.källtitel {
                    Text(titel).lineLimit(1)
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(.background, in: .rect(cornerRadius: 8))
        .onDrag {
            dras = u
            return NSItemProvider(object: u.id.uuidString as NSString)
        }
        .contextMenu {
            ForEach(Uppgift.Läge.allCases) { läge in
                if läge != u.läge {
                    Button("Flytta till \(läge.namn)") {
                        var flyttad = u
                        flyttad.läge = läge
                        try? arkiv.uppdatera(flyttad, för: kund)
                        läsOm()
                    }
                }
            }
            Divider()
            Button("Ta bort", role: .destructive) {
                try? arkiv.taBort(u, för: kund)
                läsOm()
            }
        }
    }

    private func läggTill() {
        let text = ny.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        try? arkiv.läggTill([Uppgift(vad: text, projekt: projekt?.namn)], för: kund)
        ny = ""
        läsOm()
    }

    private func läsOm() { uppgifter = arkiv.uppgifter(för: kund) }
}

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
    /// Spalten kortet just nu hålls över, för att visa var det landar.
    @State private var mål: Uppgift.Läge?
    @State private var redigerad: Uppgift?

    private var synliga: [Uppgift] {
        guard let projekt else { return uppgifter }
        return uppgifter.filter { $0.projekt == projekt.namn }
    }

    /// Öppna kort vars datum har passerat — de röda.
    private var försenade: [Uppgift] {
        synliga.filter { $0.försenad && $0.läge != .klart }
    }

    private func läggFörsenadeKlart() {
        _ = try? arkiv.läggKlart(Set(försenade.map(\.id)), för: kund)
        läsOm()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Avsnittsrubrik("Att göra")
                Spacer()
                if !försenade.isEmpty {
                    Button("Lägg \(försenade.count) försenade i Klart", action: läggFörsenadeKlart)
                        .buttonStyle(.link)
                        .help("Flyttar allt med passerat datum som fortfarande står under Att göra eller Pågår. Går att dra tillbaka.")
                }
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
        .onChange(of: arkiv.sparningar) { läsOm() }
        .sheet(item: $redigerad) { u in
            Uppgiftsredigering(uppgift: u, kund: kund,
                               projekt: projekt == nil ? arkiv.projekt(för: kund) : [],
                               vidSparat: läsOm)
        }
    }

    /// Det som brådskar överst: närmast datum först, sedan nyast skapat.
    /// Klart-spalten sorteras på när kortet rördes senast.
    static func ordning(_ a: Uppgift, _ b: Uppgift) -> Bool {
        switch (a.senast, b.senast) {
        case let (x?, y?) where x != y: return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return a.skapad > b.skapad
        }
    }

    /// Så många färdiga kort visas innan resten fälls ihop.
    static let synligaKlara = 10
    @State private var visaAllaKlara = false

    private func spalt(_ läge: Uppgift.Läge) -> some View {
        let alla = synliga.filter { $0.läge == läge }
        let ivarje = läge == .klart
            ? alla.sorted { $0.ändrad > $1.ändrad }
            : alla.sorted(by: Self.ordning)
        let visade = läge == .klart && !visaAllaKlara ? Array(ivarje.prefix(Self.synligaKlara)) : ivarje
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(läge.namn).font(.subheadline.weight(.semibold))
                Text("\(ivarje.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
            }
            ForEach(visade) { u in kort(u) }
            if läge == .klart, ivarje.count > Self.synligaKlara {
                Button(visaAllaKlara ? "Visa bara de senaste" : "… och \(ivarje.count - Self.synligaKlara) till") {
                    visaAllaKlara.toggle()
                }
                .buttonStyle(.link).font(.caption)
            }
            Spacer(minLength: 0)
        }
        // Spalterna är lika höga. En tom spalt som bara var så hög som sin
        // rubrik gav en centimeter att sikta på, och då gick korten inte att
        // flytta.
        .frame(maxWidth: .infinity, minHeight: 320, alignment: .topLeading)
        .padding(10)
        .background(.quaternary.opacity(mål == läge ? 0.7 : 0.3), in: .rect(cornerRadius: 10))
        // Släpp ett kort i spalten för att flytta det dit.
        .dropDestination(for: String.self) { id, _ in
            flytta(id.first, till: läge)
        } isTargeted: { över in
            mål = över ? läge : (mål == läge ? nil : mål)
        }
    }

    private func flytta(_ id: String?, till läge: Uppgift.Läge) -> Bool {
        guard let id, let u = uppgifter.first(where: { $0.id.uuidString == id }),
              u.läge != läge else { return false }
        var flyttad = u
        flyttad.läge = läge
        try? arkiv.uppdatera(flyttad, för: kund)
        läsOm()
        return true
    }

    private func kort(_ u: Uppgift) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(u.vad)
                .font(.callout)
                .strikethrough(u.läge == .klart)
                .foregroundStyle(u.läge == .klart ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)

            if u.vem != nil || u.när != nil || u.senast != nil {
                HStack(spacing: 4) {
                    if !u.mitt {
                        Image(systemName: "hourglass").font(.system(size: 9))
                            .help("Något jag väntar på")
                    }
                    if let vem = u.vem { Text(vem) }
                    if let rad = närtext(u) {
                        if u.vem != nil { Text("·") }
                        Text(rad).foregroundStyle(u.försenad ? Color.red : Color.secondary)
                    }
                }
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
        .kort(hörn: Stil.radhörn)
        .contentShape(.rect(cornerRadius: 8))
        .draggable(u.id.uuidString)
        .onTapGesture { redigerad = u }
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
        _ = try? arkiv.läggTill([Uppgift(vad: text, projekt: projekt?.namn)], för: kund)
        ny = ""
        läsOm()
    }

    /// Datumet när det finns, annars orden som de föll — "före fredag" säger
    /// mer än ingenting.
    private func närtext(_ u: Uppgift) -> String? {
        u.senast.map { DateFormatter.kortdag.string(from: $0) } ?? u.när
    }

    private func läsOm() { uppgifter = arkiv.uppgifter(för: kund) }
}

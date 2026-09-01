import SwiftUI

/// Insikterna bredvid live-transkriptet.
///
/// Det som dyker upp här är sådant deltagarna själva undrat över — inte
/// sammanfattningar eller förslag. En assistent som talar oombedd under ett
/// möte blir avstängd.
struct Insiktspanel: View {
    @ObservedObject var insikter: Liveinsikter

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Insikter").font(.headline)
                if insikter.granskar {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Toggle("", isOn: $insikter.på)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .help(insikter.på ? "Sluta lyssna efter frågeställningar" : "Lyssna efter frågeställningar")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()

            if let varning = insikter.varning {
                Label(varning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
            }

            ScrollViewReader { rulle in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if insikter.insikter.isEmpty { tomtLäge }
                        ForEach(insikter.insikter) { i in kort(i).id(i.id) }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: insikter.insikter.count) {
                    if let sista = insikter.insikter.last {
                        withAnimation { rulle.scrollTo(sista.id, anchor: .bottom) }
                    }
                }
            }
        }
    }

    private var tomtLäge: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(insikter.på ? "Lyssnar efter frågeställningar" : "Avstängt")
                .font(.callout.weight(.medium))
            Text(insikter.på
                 ? "När någon undrar över något som står i tidigare möten, mejl eller anteckningar dyker svaret upp här."
                 : "Slå på för att få svar på det som kommer upp under samtalet.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
    }

    private func kort(_ i: Liveinsikter.Insikt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.secondary)
                Text(i.fråga)
                    .font(.callout.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if i.väntar {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Slår upp …").font(.caption).foregroundStyle(.secondary)
                }
            } else if let fel = i.fel {
                Text(fel)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let svar = i.svar {
                Markdowntext(text: svar)
                    .font(.callout)
                    .textSelection(.enabled)
                if !i.hänvisningar.isEmpty {
                    FlödandeRad(mellanrum: 5) {
                        ForEach(i.hänvisningar) { h in
                            HStack(spacing: 3) {
                                Image(systemName: h.ikon).font(.system(size: 9))
                                Text(h.titel).font(.caption2).lineLimit(1)
                            }
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(.background.opacity(0.6), in: .capsule)
                        }
                    }
                }
            }

            Text(DateFormatter.timme.string(from: i.tid))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .kort()
    }
}

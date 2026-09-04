import SwiftUI

/// Fliken Diagnos under Inställningar: vad som finns på datorn och vilka
/// behörigheter appen har, med besked om hur det som saknas ordnas.
struct Diagnosvy: View {
    @State private var rader: [Diagnos.Rad] = []
    @State private var kontrollerar = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Vad som finns på den här datorn, och vilka behörigheter appen har.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if kontrollerar { ProgressView().controlSize(.small) }
                Button("Kontrollera igen") { Task { await kontrollera() } }
                    .disabled(kontrollerar)
            }
            if rader.isEmpty {
                Text("Kontrollerar …").foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rader.enumerated()), id: \.element.id) { i, r in
                        rad(r)
                        if i < rader.count - 1 { Divider() }
                    }
                }
                .kort(hörn: Stil.radhörn)
                sammanfattning
            }
        }
        .task { await kontrollera() }
    }

    private func rad(_ r: Diagnos.Rad) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(färg(r.läge))
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            Text(r.namn)
                .frame(width: 190, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(r.besked)
                    .font(.caption)
                    .foregroundStyle(r.läge == .ok ? Color.secondary : Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let åtgärd = r.åtgärd {
                    Text(åtgärd)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let länk = r.länk {
                    Button("Öppna Systeminställningar") { NSWorkspace.shared.open(länk) }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var sammanfattning: some View {
        let saknas = rader.filter { $0.läge == .saknas }.count
        let frivilliga = rader.filter { $0.läge == .frivilligt }.count
        let text: String
        if saknas == 0 && frivilliga == 0 {
            text = "Allt finns."
        } else if saknas == 0 {
            text = "Allt appen kräver finns. \(frivilliga) \(frivilliga == 1 ? "sak" : "saker") i grått är frivilliga."
        } else {
            text = "\(saknas) \(saknas == 1 ? "sak" : "saker") saknas som appen behöver; se raderna i orange."
        }
        return Text(text)
            .font(.caption)
            .foregroundStyle(saknas == 0 ? Color.secondary : Color.orange)
    }

    private func färg(_ läge: Diagnos.Läge) -> Color {
        switch läge {
        case .ok: .green
        case .saknas: .orange
        case .frivilligt: .gray
        }
    }

    private func kontrollera() async {
        kontrollerar = true
        rader = await Diagnos.kör()
        kontrollerar = false
    }
}

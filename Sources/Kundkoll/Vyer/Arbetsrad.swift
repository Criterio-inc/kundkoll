import SwiftUI

/// Raden längst ned som visar vad appen håller på med, oavsett flik.
///
/// Samma form som Importrad: fel ligger kvar tills de stängs, pågående
/// jobb visas med steg och andel. Ett klick på raden fäller ut hela listan.
struct Arbetsrad: View {
    @ObservedObject private var arbeten = Arbeten.delad
    @State private var utfälld = false

    var body: some View {
        ForEach(arbeten.fel) { k in
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("\(k.kund): \(k.titel) — \(k.fel ?? "")")
                    .lineLimit(1).foregroundStyle(.secondary)
                    .help(k.fel ?? "")
                Spacer()
                Button("OK") { arbeten.stängFel(k.id) }
            }
            .controlSize(.small)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
        if let första = arbeten.pågående.first {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: första.lämnarDatorn ? "icloud.and.arrow.up" : "gearshape.2")
                        .foregroundStyle(första.lämnarDatorn ? Color.orange : Color.accentColor)
                    Text(arbeten.beskrivning ?? "")
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                    if let andel = första.andel {
                        ProgressView(value: andel).frame(width: 120)
                        Text("\(Int(andel * 100)) %")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                    if arbeten.pågående.count > 1 {
                        Button(utfälld ? "Dölj" : "Visa alla") { utfälld.toggle() }
                            .buttonStyle(.link)
                    }
                }
                if utfälld {
                    ForEach(arbeten.pågående.dropFirst()) { a in
                        HStack(spacing: 10) {
                            Image(systemName: "circle.dotted").foregroundStyle(.tertiary)
                            Text("\(a.kund): \(a.titel)\(a.steg.isEmpty ? "" : " — \(a.steg)")")
                                .lineLimit(1).foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .controlSize(.small)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
    }
}

import SwiftUI
import AppKit

/// Appens gemensamma formspråk.
///
/// Innan det här fanns var varje yta sin egen: gråa boxar i olika toner,
/// rubriker i olika vikter, avstånd på känsla. Ett formspråk är inte pynt —
/// det är att samma sak ser likadan ut överallt, så att ögat slipper lära om
/// per flik.
///
/// Grunden: sidorna ligger på en dämpad botten och innehållet på vita kort
/// med hårfin kant. Det ger djup utan skuggor och följer mörkt läge gratis,
/// eftersom båda färgerna är systemets egna.
enum Stil {
    static let hörn: CGFloat = 10
    static let radhörn: CGFloat = 8

    /// Sidans botten — snäppet mörkare än korten, så att de lyfter.
    /// windowBackgroundColor är systemets egna inställningsgrå; under-
    /// varianten såg ut som betong i ett aktivt fönster.
    static var botten: Color { Color(nsColor: .windowBackgroundColor) }
    /// Kortens yta.
    static var yta: Color { Color(nsColor: .controlBackgroundColor) }
}

// MARK: - Kort

/// Ett kort: innehållsyta med hårfin kant på sidans botten.
struct Kortstil: ViewModifier {
    var hörn: CGFloat = Stil.hörn
    func body(content: Content) -> some View {
        content
            .background(Stil.yta, in: .rect(cornerRadius: hörn))
            .overlay(RoundedRectangle(cornerRadius: hörn)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6)))
    }
}

extension View {
    func kort(hörn: CGFloat = Stil.hörn) -> some View {
        modifier(Kortstil(hörn: hörn))
    }
}

// MARK: - Rubriker

/// Avsnittsrubrik: liten, versal, spärrad — som systemets egna inställningar.
struct Avsnittsrubrik: View {
    let text: String
    var räknare: Int?

    init(_ text: String, räknare: Int? = nil) {
        self.text = text
        self.räknare = räknare
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(text.uppercased())
                .font(.caption.weight(.semibold))
                .kerning(0.6)
                .foregroundStyle(.secondary)
            if let räknare {
                Text("\(räknare)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Märken

/// Ett litet kapselmärke: «live», «pågår», «importerad».
struct Märke: View {
    let text: String
    var färg: Color = .secondary
    var ikon: String?

    var body: some View {
        HStack(spacing: 3) {
            if let ikon { Image(systemName: ikon).font(.system(size: 8)) }
            Text(text)
        }
        .font(.caption2.weight(.medium))
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .foregroundStyle(färg)
        .background(färg.opacity(0.13), in: .capsule)
    }
}

// MARK: - Kundsigill

/// Kundens initialer i en färgad bricka. Färgen kommer ur namnet och är
/// därmed stabil — samma kund ser likadan ut i sidopanelen, rubriken och
/// sökresultaten.
struct Sigill: View {
    let namn: String
    var sida: CGFloat = 26

    var body: some View {
        Text(initialer)
            .font(.system(size: sida * 0.42, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: sida, height: sida)
            .background(
                LinearGradient(colors: [färg, färg.opacity(0.75)],
                               startPoint: .top, endPoint: .bottom),
                in: .rect(cornerRadius: sida * 0.28))
    }

    private var initialer: String {
        let ord = namn.split(separator: " ").prefix(2)
        let bokstäver = ord.compactMap(\.first)
        return bokstäver.isEmpty ? "?" : String(bokstäver).uppercased()
    }

    private var färg: Color {
        // Ett stabilt val ur en handplockad palett, så att grannfärgerna
        // aldrig blir skrikiga.
        let paletten: [Color] = [.blue, .indigo, .teal, .purple,
                                 .orange, .pink, .cyan, .mint]
        var summa = 0
        for tecken in namn.unicodeScalars { summa = (summa &* 31 &+ Int(tecken.value)) }
        return paletten[abs(summa) % paletten.count]
    }
}

// MARK: - Tomma lägen

/// Ett vänligt tomt läge i stället för en ensam grå rad.
struct TomtLäge: View {
    let ikon: String
    let rubrik: String
    var text: String?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: ikon)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
            Text(rubrik)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            if let text {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

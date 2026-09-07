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
    static let hörn: CGFloat = 12
    static let radhörn: CGFloat = 10

    /// En färg som följer ljust och mörkt läge.
    static func dynamisk(ljus: (Double, Double, Double), mörk: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { utseende in
            let m = utseende.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let (r, g, b) = m ? mörk : ljus
            return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        })
    }

    // MARK: Färger med en betydelse

    /// Appens egen färg: petrol. Val, knappar, det som pågår.
    static let accent = dynamisk(ljus: (0.09, 0.44, 0.52), mörk: (0.33, 0.68, 0.76))
    /// Material lämnar datorn. Orange betyder bara det.
    static let moln = Color.orange
    /// Något gick fel eller saknas.
    static let fel = Color.red
    /// Försenat.
    static let sen = Color.red
    /// Inspelning pågår.
    static let live = Color.red
    /// Klart, fungerar.
    static let klart = Color.green
    /// Pågår.
    static let pågår = accent
    /// Väntar på någon annan, eller på att något ska hända.
    static let väntar = Color.indigo

    /// Tavlans spalter i fast ordning: Att göra grå, Pågår accent, Klart grön.
    static func färg(_ läge: Uppgift.Läge) -> Color {
        switch läge {
        case .attGöra: .secondary
        case .pågår: pågår
        case .klart: klart
        }
    }

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

// MARK: - Kundfärg

/// Kundens färg: vald i sidopanelens meny, annars lottad ur namnet så att
/// samma kund ser likadan ut överallt. Sex dämpade toner, ingen orange:
/// den betyder att material lämnar datorn.
enum Kundfärg: String, CaseIterable, Codable, Identifiable {
    case petrol, hav, plommon, skog, ockra, rost, skiffer
    var id: String { rawValue }

    var namn: String {
        switch self {
        case .petrol: "Petrol"
        case .hav: "Hav"
        case .plommon: "Plommon"
        case .skog: "Skog"
        case .ockra: "Ockra"
        case .rost: "Rost"
        case .skiffer: "Skiffer"
        }
    }

    var färg: Color {
        switch self {
        case .petrol: Stil.dynamisk(ljus: (0.10, 0.45, 0.53), mörk: (0.30, 0.65, 0.72))
        case .hav: Stil.dynamisk(ljus: (0.18, 0.40, 0.68), mörk: (0.42, 0.60, 0.85))
        case .plommon: Stil.dynamisk(ljus: (0.48, 0.30, 0.58), mörk: (0.66, 0.50, 0.76))
        case .skog: Stil.dynamisk(ljus: (0.22, 0.50, 0.36), mörk: (0.42, 0.68, 0.52))
        case .ockra: Stil.dynamisk(ljus: (0.72, 0.52, 0.18), mörk: (0.85, 0.68, 0.35))
        case .rost: Stil.dynamisk(ljus: (0.68, 0.34, 0.28), mörk: (0.84, 0.52, 0.45))
        case .skiffer: Stil.dynamisk(ljus: (0.36, 0.42, 0.50), mörk: (0.56, 0.62, 0.70))
        }
    }

    /// Ett stabilt val ur namnet.
    static func för(namn: String) -> Kundfärg {
        var summa = 0
        for tecken in namn.unicodeScalars { summa = (summa &* 31 &+ Int(tecken.value)) }
        return allCases[abs(summa) % allCases.count]
    }

    /// En fylld rund bricka för menyer, där SwiftUI-färger inte når.
    var bricka: NSImage {
        let bild = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            NSColor(self.färg).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        bild.isTemplate = false
        return bild
    }
}

// MARK: - Kundsigill

/// Kundens initialer i en färgad bricka. Färgen är kundens valda, annars
/// den namnet ger — samma kund ser likadan ut i sidopanelen, rubriken och
/// sökresultaten.
struct Sigill: View {
    let namn: String
    var färg: Color?
    var sida: CGFloat = 26

    var body: some View {
        let ton = färg ?? Kundfärg.för(namn: namn).färg
        Text(initialer)
            .font(.system(size: sida * 0.42, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: sida, height: sida)
            .background(
                LinearGradient(colors: [ton, ton.opacity(0.78)],
                               startPoint: .top, endPoint: .bottom),
                in: .rect(cornerRadius: sida * 0.28))
    }

    private var initialer: String {
        let ord = namn.split(separator: " ").prefix(2)
        let bokstäver = ord.compactMap(\.first)
        return bokstäver.isEmpty ? "?" : String(bokstäver).uppercased()
    }
}

/// Kontaktens ansikte: profilbilden när en finns, annars initialerna.
struct Kontaktsigill: View {
    let kontakt: Kontakt
    let kund: Kund
    var sida: CGFloat = 26

    @EnvironmentObject private var arkiv: Arkivet

    var body: some View {
        if let url = arkiv.kontaktbild(för: kontakt, hos: kund),
           let bild = NSImage(contentsOf: url) {
            Image(nsImage: bild)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: sida, height: sida)
                .clipShape(.rect(cornerRadius: sida * 0.28))
        } else {
            Sigill(namn: kontakt.namn, sida: sida)
        }
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

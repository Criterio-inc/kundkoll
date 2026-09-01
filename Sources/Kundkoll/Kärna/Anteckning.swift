import Foundation

/// En anteckning är en markdownfil i en `Anteckningar`-mapp.
///
/// Ingen databas och inget eget format: filen är anteckningen. Det gör att den
/// går lika bra att öppna och redigera i Obsidian, och att bilder länkas med
/// wikilänkar som Obsidian visar direkt.
struct Anteckning: Identifiable, Hashable {
    var id: String { fil.path }
    var titel: String
    var text: String
    var ändrad: Date
    var fil: URL

    /// Bildmappen ligger bredvid anteckningarna, gemensam för dem alla.
    static let bildmapp = "bilder"

    /// Första raden med innehåll, till listan.
    var utdrag: String {
        text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("---") } ?? ""
    }

    /// Bilder som anteckningen hänvisar till, i den ordning de förekommer.
    var bilder: [String] {
        var ut: [String] = []
        var rest = Substring(text)
        while let start = rest.range(of: "![["), let slut = rest.range(of: "]]", range: start.upperBound..<rest.endIndex) {
            let namn = String(rest[start.upperBound..<slut.lowerBound])
            if namn.hasPrefix("\(Self.bildmapp)/") { ut.append(namn) }
            rest = rest[slut.upperBound...]
        }
        return ut
    }
}

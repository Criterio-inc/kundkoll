import SwiftUI

/// Visar markdown som modellen skriver.
///
/// SwiftUI klarar inline-formatering — fet, kursiv, kod — via AttributedString,
/// men inte punktlistor eller rubriker. De vanligaste blocken hanteras därför
/// rad för rad här. Ett fullständigt markdownbibliotek vore mer än vad ett
/// chattsvar behöver.
struct Markdowntext: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(block.enumerated()), id: \.offset) { _, b in
                switch b {
                case .stycke(let s):
                    inline(s)
                case .punkt(let s, let nivå):
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("•").foregroundStyle(.secondary)
                        inline(s)
                    }
                    .padding(.leading, CGFloat(nivå) * 14)
                case .numrerad(let nummer, let s, let nivå):
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("\(nummer).").foregroundStyle(.secondary)
                            .monospacedDigit()
                        inline(s)
                    }
                    .padding(.leading, CGFloat(nivå) * 14)
                case .rubrik(let s):
                    inline(s).font(.headline)
                }
            }
        }
    }

    private func inline(_ s: String) -> Text {
        // Faller tillbaka på råtexten om markdown inte går att tolka, hellre
        // än att visa ingenting.
        if let a = try? AttributedString(
            markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(a)
        }
        return Text(s)
    }

    // MARK: - Tolkning

    enum Block: Equatable {
        case stycke(String)
        case punkt(String, nivå: Int)
        case numrerad(Int, String, nivå: Int)
        case rubrik(String)
    }

    private var block: [Block] { Self.tolka(text) }

    static func tolka(_ text: String) -> [Block] {
        var ut: [Block] = []
        var stycke: [String] = []

        func stängStycke() {
            let s = stycke.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !s.isEmpty { ut.append(.stycke(s)) }
            stycke = []
        }

        for rad in text.components(separatedBy: .newlines) {
            let indrag = rad.prefix { $0 == " " }.count
            let nivå = min(2, indrag / 2)
            let t = rad.trimmingCharacters(in: .whitespaces)

            if t.isEmpty {
                stängStycke()
                continue
            }
            if t.hasPrefix("#") {
                stängStycke()
                ut.append(.rubrik(t.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)))
                continue
            }
            if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("• ") {
                stängStycke()
                ut.append(.punkt(String(t.dropFirst(2)), nivå: nivå))
                continue
            }
            // "1. text" och "1) text"
            if let punkt = t.firstIndex(where: { $0 == "." || $0 == ")" }),
               punkt < t.index(t.startIndex, offsetBy: min(3, t.count)),
               let nummer = Int(t[t.startIndex..<punkt]),
               t.index(after: punkt) < t.endIndex,
               t[t.index(after: punkt)] == " " {
                stängStycke()
                ut.append(.numrerad(nummer,
                                    String(t[t.index(punkt, offsetBy: 2)...]),
                                    nivå: nivå))
                continue
            }
            stycke.append(t)
        }
        stängStycke()
        return ut
    }
}

import SwiftUI

/// Lägger sina element på rad och bryter när bredden tar slut.
///
/// Behövs för källhänvisningar och förslag: de är olika breda och ska ta så
/// lite plats som möjligt, inte en rad var.
struct FlödandeRad: Layout {
    var mellanrum: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let bredd = proposal.width ?? .infinity
        let rader = lägg(subviews, iBredd: bredd)
        let höjd = rader.last.map { $0.y + $0.höjd } ?? 0
        return CGSize(width: bredd == .infinity ? (rader.map(\.bredd).max() ?? 0) : bredd,
                      height: höjd)
    }

    func placeSubviews(in ram: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        for rad in lägg(subviews, iBredd: ram.width) {
            var x = ram.minX
            for i in rad.index {
                let storlek = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: ram.minY + rad.y),
                                  proposal: ProposedViewSize(storlek))
                x += storlek.width + mellanrum
            }
        }
    }

    private struct Rad {
        var index: [Int] = []
        var y: CGFloat = 0
        var höjd: CGFloat = 0
        var bredd: CGFloat = 0
    }

    private func lägg(_ subviews: Subviews, iBredd bredd: CGFloat) -> [Rad] {
        var rader: [Rad] = []
        var nuvarande = Rad()
        var x: CGFloat = 0
        var y: CGFloat = 0

        for (i, vy) in subviews.enumerated() {
            let storlek = vy.sizeThatFits(.unspecified)
            if x + storlek.width > bredd, !nuvarande.index.isEmpty {
                nuvarande.bredd = x - mellanrum
                rader.append(nuvarande)
                y += nuvarande.höjd + mellanrum
                nuvarande = Rad(y: y)
                x = 0
            }
            nuvarande.index.append(i)
            nuvarande.höjd = max(nuvarande.höjd, storlek.height)
            x += storlek.width + mellanrum
        }
        if !nuvarande.index.isEmpty {
            nuvarande.bredd = x - mellanrum
            rader.append(nuvarande)
        }
        return rader
    }
}

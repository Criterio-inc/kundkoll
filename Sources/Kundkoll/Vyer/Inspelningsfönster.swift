import SwiftUI
import AppKit

/// Inspelningen i ett eget fönster.
///
/// Ett möte varar i timmen, och under den tiden ska resten av appen gå att
/// använda — slå upp vad som sades förra gången, skriva en anteckning, fråga
/// chatten. Ett eget fönster går dessutom att lägga bredvid Teams eller på en
/// andra skärm.
///
/// SwiftUI:s fönsterhantering på macOS passar inte en vy som ska styras
/// utifrån och bära ett pågående tillstånd, så fönstret byggs med AppKit.
@MainActor
enum Inspelningsfönster {
    fileprivate static var fönster: NSWindow?
    private static let vakt = Fönstervakt()

    static func öppna(kund: Kund, projekt: Projekt?, möte: Kalendern.Möte?) {
        if let f = fönster {
            // Pågår något visas fönstret som det är. Annars byggs det om för
            // den kund som bads om: ett fönster stängt med röda knappen kom
            // förut tillbaka med förra kundens namn och sida.
            let s = Inspelningssession.delad
            switch s.läge {
            case .förbereder, .spelarIn, .avslutar:
                f.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            case .vilande, .fel, .klar:
                f.delegate = nil
                f.close()
                fönster = nil
                s.återställ()
            }
        }
        let vy = Inspelningsvy(kund: kund, projekt: projekt, möte: möte)
            .environmentObject(Arkivet.shared)
            .environmentObject(Inspelningssession.delad)
            .environmentObject(Adressboken.shared)

        let f = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        f.title = möte?.titel ?? kund.namn
        f.contentView = NSHostingView(rootView: vy)
        f.isReleasedWhenClosed = false
        f.center()
        // Fönstret ska kunna ligga kvar synligt bredvid mötesverktyget.
        f.level = .normal
        f.delegate = vakt
        f.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        fönster = f
    }

    static func visa() {
        fönster?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func stäng() {
        fönster?.close()
        fönster = nil
    }

    static var öppet: Bool { fönster?.isVisible == true }
}

/// Röda knappen ska betyda samma sak som «Klar»: fönstret glöms och
/// sessionen nollställs om den inte spelar in.
private final class Fönstervakt: NSObject, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            Inspelningsfönster.fönster = nil
            Inspelningssession.delad.återställ()
        }
    }
}

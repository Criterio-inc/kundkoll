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
    private static var fönster: NSWindow?

    static func öppna(kund: Kund, projekt: Projekt?, möte: Kalendern.Möte?) {
        if let f = fönster {
            f.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
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

import Foundation
import UserNotifications

/// Säger till när sådant som blir klart i bakgrunden är värt att titta på.
///
/// Sammanfattningen skrivs minuter efter att mötet tagit slut, och utan en
/// notis blir den klar i tysthet. macOS visar bara banderollen när appen
/// ligger i bakgrunden, så det stör aldrig den som redan tittar.
@MainActor
enum Notiser {

    /// Notiser kräver ett appaket. Körd som kommandorad — testerna,
    /// provkommandona — finns inget, och då är detta tyst och ofarligt.
    private static var kanNotisa: Bool { Bundle.main.bundleIdentifier != nil }

    /// Frågas första gången något startas som kommer att bli klart i
    /// bakgrunden, inte vid appstart — då förstår man varför frågan kommer.
    static func begär() {
        guard kanNotisa else { return }
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// En notis nu. `kund` följer med så att ett klick kan öppna rätt ställe.
    static func skicka(titel: String, text: String, kund: String? = nil) {
        guard kanNotisa else { return }
        let innehåll = UNMutableNotificationContent()
        innehåll.title = titel
        innehåll.body = text
        if let kund { innehåll.userInfo = ["kund": kund] }
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString,
                                  content: innehåll, trigger: nil))
    }

    /// Vad ett färdigbearbetat möte är värt att säga.
    static func mötetKlart(_ inspelning: Inspelning) {
        let antal = inspelning.sammanfattning?.åtaganden.count ?? 0
        let text: String
        switch antal {
        case 0 where inspelning.sammanfattning == nil:
            text = "Transkriptet är klart."
        case 0:
            text = "Sammanfattat — inga åtaganden."
        case 1:
            text = "Sammanfattat — 1 åtagande på tavlan."
        default:
            text = "Sammanfattat — \(antal) åtaganden på tavlan."
        }
        skicka(titel: inspelning.titel, text: text, kund: inspelning.kund)
    }
}

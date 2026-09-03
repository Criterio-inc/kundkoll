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

    /// Bokar en påminnelse en kvart före varje kundmöte, så att briefen
    /// hinner läsas innan mötet börjar. Gamla bokningar rensas först —
    /// flyttade och avbokade möten ska inte spöka.
    static func planeraBriefingar(för möten: [(kund: String, möte: Kalendern.Möte)]) {
        guard kanNotisa else { return }
        let central = UNUserNotificationCenter.current()
        central.getPendingNotificationRequests { väntande in
            // Hämtas på nytt här hellre än fångas: klassen är inte Sendable.
            let central = UNUserNotificationCenter.current()
            central.removePendingNotificationRequests(
                withIdentifiers: väntande.map(\.identifier).filter { $0.hasPrefix("brief-") })
            for (kund, m) in möten {
                let när = m.start.addingTimeInterval(-15 * 60)
                guard när > Date() else { continue }
                let innehåll = UNMutableNotificationContent()
                innehåll.title = "Om en kvart: \(m.titel)"
                innehåll.body = "Läs på inför mötet — senaste mötet, öppna åtaganden "
                    + "och nya mejl hos \(kund)."
                innehåll.userInfo = ["kund": kund, "möte": m.id]
                let delar = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: när)
                central.add(UNNotificationRequest(
                    identifier: "brief-\(m.id)",
                    content: innehåll,
                    trigger: UNCalendarNotificationTrigger(dateMatching: delar, repeats: false)))
            }
        }
    }

    /// Tar emot klick på notiser och skickar dem vidare in i appen.
    static func startaMottagning() {
        guard kanNotisa else { return }
        let central = UNUserNotificationCenter.current()
        central.delegate = Mottagare.delad
        // Tidursfrågan har två svar direkt i notisen.
        let logga = UNNotificationAction(identifier: "tidur-logga", title: "Logga tiden")
        let fortsätt = UNNotificationAction(identifier: "tidur-fortsätt",
                                            title: "Fortsätt räkna")
        central.setNotificationCategories([
            UNNotificationCategory(identifier: "tidur", actions: [logga, fortsätt],
                                   intentIdentifiers: []),
        ])
    }

    /// Frågan när datorn vaknat med uret pausat.
    static func tidursfråga(_ text: String) {
        guard kanNotisa else { return }
        let innehåll = UNMutableNotificationContent()
        innehåll.title = "Uret står stilla"
        innehåll.body = text
        innehåll.categoryIdentifier = "tidur"
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "tidur-paus", content: innehåll, trigger: nil))
    }

    final class Mottagare: NSObject, UNUserNotificationCenterDelegate {
        static let delad = Mottagare()

        func userNotificationCenter(_ central: UNUserNotificationCenter,
                                    didReceive svar: UNNotificationResponse) async {
            switch svar.actionIdentifier {
            case "tidur-logga":
                _ = await MainActor.run { Tidur.delad.stoppa() }
                return
            case "tidur-fortsätt":
                await MainActor.run { Tidur.delad.fortsätt() }
                return
            default:
                break
            }
            let info = svar.notification.request.content.userInfo
            guard let kund = info["kund"] as? String else { return }
            let möte = info["möte"] as? String
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .öppnaKund, object: kund,
                    userInfo: möte.map { ["möte": $0] } ?? [:])
            }
        }
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

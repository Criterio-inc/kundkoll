import Foundation
import EventKit

/// Skickar uppgifter till macOS Påminnelser, för den som lever där.
///
/// Envägs med flit: tavlan är sanningen och påminnelsen en spegel. Att bocka
/// av i appen bockar av påminnelsen, men det som ändras i Påminnelser rör
/// inte tavlan — två håll skulle betyda att appen skriver om användarens
/// egna listor i bakgrunden, och de delas med telefonen.
@MainActor
final class Påminnelser {
    static let delad = Påminnelser()

    private let butik = EKEventStore()

    var harTillgång: Bool {
        EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    func begär() async -> Bool {
        if harTillgång { return true }
        return (try? await butik.requestFullAccessToReminders()) ?? false
    }

    /// Lägger uppgiften i listan Kundkoll och ger påminnelsens id, som sparas
    /// på uppgiften så att avbockningar hittar rätt.
    func läggIn(_ uppgift: Uppgift, kund: String) async -> String? {
        guard await begär(), let lista = lista() else { return nil }
        let p = EKReminder(eventStore: butik)
        p.calendar = lista
        p.title = uppgift.vad
        p.notes = ([kund, uppgift.vem].compactMap { $0 }).joined(separator: " · ")
        if let senast = uppgift.senast {
            p.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day], from: senast)
        }
        p.isCompleted = uppgift.läge == .klart
        do { try butik.save(p, commit: true) } catch { return nil }
        return p.calendarItemIdentifier
    }

    /// Speglar en ändrad uppgift till dess påminnelse: avbockning, ny text,
    /// flyttat datum. Gör ingenting för uppgifter som inte lagts in.
    func spegla(_ uppgift: Uppgift) {
        guard harTillgång, let id = uppgift.påminnelse,
              let p = butik.calendarItem(withIdentifier: id) as? EKReminder else { return }
        let klar = uppgift.läge == .klart
        let datum = uppgift.senast.map {
            Calendar.current.dateComponents([.year, .month, .day], from: $0)
        }
        guard p.isCompleted != klar || p.title != uppgift.vad
                || p.dueDateComponents != datum else { return }
        p.isCompleted = klar
        p.title = uppgift.vad
        p.dueDateComponents = datum
        try? butik.save(p, commit: true)
    }

    /// Listan Kundkoll i Påminnelser. Skapas första gången.
    private func lista() -> EKCalendar? {
        if let c = butik.calendars(for: .reminder).first(where: { $0.title == "Critero-kundkoll" }) {
            return c
        }
        guard let källa = butik.defaultCalendarForNewReminders()?.source
                ?? butik.sources.first(where: { $0.sourceType == .calDAV })
                ?? butik.sources.first else { return nil }
        let c = EKCalendar(for: .reminder, eventStore: butik)
        c.title = "Critero-kundkoll"
        c.source = källa
        do { try butik.saveCalendar(c, commit: true) } catch { return nil }
        return c
    }
}

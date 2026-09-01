import Foundation

/// Ett minimalt testramverk.
///
/// Varken Swift Testing eller XCTest följer med Command Line Tools, och att
/// kräva en Xcode-installation för att kunna köra testerna vore ett för högt
/// pris. Testerna körs i stället som ett läge i appen: `Kundkoll --test`.
enum Prov {
    nonisolated(unsafe) static var godkända = 0
    nonisolated(unsafe) static var fällda: [String] = []
    nonisolated(unsafe) private static var svit = ""

    static func svit(_ namn: String) {
        svit = namn
        print("\n\u{001B}[1m\(namn)\u{001B}[0m")
    }

    static func kolla(_ villkor: Bool, _ vad: String, fil: String = #fileID, rad: Int = #line) {
        if villkor {
            godkända += 1
            print("  \u{001B}[32m✓\u{001B}[0m \(vad)")
        } else {
            let text = "\(svit) › \(vad)  (\(fil):\(rad))"
            fällda.append(text)
            print("  \u{001B}[31m✗ \(vad)\u{001B}[0m  \(fil):\(rad)")
        }
    }

    static func lika<T: Equatable>(_ a: T, _ b: T, _ vad: String, fil: String = #fileID, rad: Int = #line) {
        if a == b {
            godkända += 1
            print("  \u{001B}[32m✓\u{001B}[0m \(vad)")
        } else {
            let text = "\(svit) › \(vad): \(a) ≠ \(b)  (\(fil):\(rad))"
            fällda.append(text)
            print("  \u{001B}[31m✗ \(vad)\u{001B}[0m  \(a) ≠ \(b)  \(fil):\(rad)")
        }
    }

    static func sammanfatta() -> Int32 {
        print("")
        if fällda.isEmpty {
            print("\u{001B}[32m\(godkända) test godkända.\u{001B}[0m")
            return 0
        }
        print("\u{001B}[31m\(fällda.count) av \(godkända + fällda.count) test fällda:\u{001B}[0m")
        for f in fällda { print("  · \(f)") }
        return 1
    }
}

import Foundation

/// En loggfil för det som annars försvinner i ett `try?`.
///
/// Ligger i ~/Library/Logs/Kundkoll.log, där Konsol hittar den. Ett fel i
/// bakgrunden fick förut inget spår alls; nu finns åtminstone en rad att
/// visa upp när något «bara inte hände».
enum Logg {
    static let fil = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Logs/Kundkoll.log")

    /// Provsviten avslutar jobb med påhittade fel («når inte Mail» hos Acme).
    /// De ska inte hamna i den riktiga loggen bland Pärs egna kunder.
    nonisolated(unsafe) static var tyst = false

    private static let kö = DispatchQueue(label: "kundkoll.logg")
    private static let stämpel: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func fel(_ text: String, i var_: String) {
        guard !tyst else { return }
        let rad = "\(stämpel.string(from: Date())) [\(var_)] \(text)\n"
        kö.async {
            guard let data = rad.data(using: .utf8) else { return }
            if let h = try? FileHandle(forWritingTo: fil) {
                h.seekToEndOfFile(); h.write(data); try? h.close()
            } else {
                try? data.write(to: fil)
            }
        }
    }
}

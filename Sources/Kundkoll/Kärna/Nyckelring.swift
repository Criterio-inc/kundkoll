import Foundation
import Security

/// API-nyckeln i macOS nyckelring.
///
/// Inte i en fil i kundmappen: den mappen ligger i Dokument och kan hamna i
/// iCloud, i en säkerhetskopia eller i ett delat valv.
enum Nyckelring {
    private static let tjänst = "com.brattoo.kundkoll"

    static func hämta(_ konto: String, miljö: String? = nil) -> String? {
        // En nyckel i miljön vinner, så att en nyckel man redan har i skalet
        // fungerar utan att läggas in på nytt. Notera att en app startad från
        // Finder inte ser skalets variabler — bara en startad från terminalen.
        for namn in [miljö, konto].compactMap({ $0 }) {
            if let ur = ProcessInfo.processInfo.environment[namn], !ur.isEmpty { return ur }
        }

        let fråga: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tjänst,
            kSecAttrAccount as String: konto,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var resultat: CFTypeRef?
        guard SecItemCopyMatching(fråga as CFDictionary, &resultat) == errSecSuccess,
              let data = resultat as? Data,
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty else { return nil }
        return text
    }

    @discardableResult
    static func spara(_ värde: String, som konto: String) -> Bool {
        let bas: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tjänst,
            kSecAttrAccount as String: konto,
        ]
        SecItemDelete(bas as CFDictionary)
        guard !värde.isEmpty else { return true }
        var ny = bas
        ny[kSecValueData as String] = Data(värde.utf8)
        return SecItemAdd(ny as CFDictionary, nil) == errSecSuccess
    }

    /// Nyckeln för en leverantör: miljön först, sedan nyckelringen.
    static func förLeverantör(_ l: Leverantör) -> String? {
        hämta(l.nyckelkonto, miljö: l.miljövariabel)
    }
}

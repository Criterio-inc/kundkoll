import Foundation

/// Ställer en fråga till en kopplad mapp, som chatten gör.
///
///     Kundkoll --prov-kodagent <mapp> "<fråga>"
enum Kodagentprov {
    static func kör(mapp väg: String, fråga: String) async -> Int32 {
        let agent = Kodagent()
        Prov.svit("Kodagent")

        guard await agent.finns else {
            print("Claude Code hittades inte.")
            Prov.kolla(false, "Claude Code finns")
            return Prov.sammanfatta()
        }
        let mapp = URL(fileURLWithPath: väg)
        print("Frågar \(mapp.lastPathComponent): «\(fråga)»")

        do {
            let svar = try await agent.fråga(fråga, i: mapp, om: "prov", projekt: nil)
            print("\nSvar efter \(String(format: "%.0f", svar.sekunder)) s:\n")
            print(svar.text)
            print("")
            Prov.kolla(!svar.text.isEmpty, "agenten svarade")
            Prov.kolla(svar.text.count > 40, "svaret är mer än en rad")
            Prov.kolla(svar.sekunder < 300, "svaret kom inom rimlig tid")
        } catch {
            print("Gick inte: \(error.localizedDescription)")
            Prov.kolla(false, "agenten kunde köras")
        }
        return Prov.sammanfatta()
    }
}

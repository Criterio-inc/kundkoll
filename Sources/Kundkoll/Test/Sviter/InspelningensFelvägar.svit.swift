import Foundation

extension Tester {
    static func inspelningensFelvägar() {
        Prov.svit("Inspelningens felvägar")

        do {   // WAV-huvudet skrivs löpande, så en krasch inte ger en tom fil
            let mapp = FileManager.default.temporaryDirectory
                .appending(path: "kundkoll-test-\(UUID().uuidString)")
            try! FileManager.default.createDirectory(at: mapp, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: mapp) }
            let fil = mapp.appending(path: "jag.wav")
            let skrivare = try! Spårskrivare(fil: fil)
            func datalängd() -> UInt32 {
                let d = try! Data(contentsOf: fil)
                return d.subdata(in: 40..<44).withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
            }
            skrivare.skriv([Float](repeating: 0.1, count: 16_000 * 3))
            Prov.lika(datalängd(), 0, "efter tre sekunder står huvudet fortfarande på noll")
            skrivare.skriv([Float](repeating: 0.1, count: 16_000 * 8))
            Prov.lika(datalängd(), UInt32(16_000 * 11 * 2), "efter elva sekunder är huvudet uppdaterat utan att filen stängts")
            Prov.kolla(!Inspelningssession.saknarLjud(mapp), "mappen räknas som en med ljud")
            skrivare.stäng()
            Prov.lika(datalängd(), UInt32(16_000 * 11 * 2), "och stängningen skriver samma längd")
        }

        do {   // en mapp utan ljud känns igen och kan städas
            let mapp = FileManager.default.temporaryDirectory
                .appending(path: "kundkoll-test-\(UUID().uuidString)")
            try! FileManager.default.createDirectory(at: mapp, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: mapp) }
            _ = try! Spårskrivare(fil: mapp.appending(path: "jag.wav"))
            _ = try! Spårskrivare(fil: mapp.appending(path: "motpart.wav"))
            Prov.kolla(Inspelningssession.saknarLjud(mapp), "två filer med bara huvud är en mapp utan ljud")
        }

        do {   // felet pekar på rätt ruta i Systeminställningar
            Prov.kolla(Inspelningsvy.inställningslänk(för: "Datorljudet kräver Skärminspelning. …")?
                           .absoluteString.contains("Privacy_ScreenCapture") == true,
                       "skärminspelning öppnar rätt ruta")
            Prov.kolla(Inspelningsvy.inställningslänk(för: "Mikrofonen är inte tillåten.")?
                           .absoluteString.contains("Privacy_Microphone") == true,
                       "mikrofon öppnar rätt ruta")
            Prov.lika(Inspelningsvy.inställningslänk(för: "whisper-server svarade inte"), nil,
                      "andra fel får ingen knapp")
        }
    }
}

import Foundation
import AVFoundation
import CoreGraphics

/// Vad som finns på den här datorn och vilka behörigheter appen har.
///
/// Samma kontroller som `scripts/installera.sh --kontrollera`, men i appen:
/// en ny användare ska inte behöva terminalen för att få veta vad som
/// saknas och hur det ordnas.
@MainActor
enum Diagnos {

    enum Läge {
        /// Finns och fungerar.
        case ok
        /// Saknas, och något i appen går inte utan.
        case saknas
        /// Saknas, men appen klarar sig med sämre resultat.
        case frivilligt
    }

    struct Rad: Identifiable {
        let id: String
        let namn: String
        let läge: Läge
        /// Kort besked, «svarar på 127.0.0.1:11434» eller «inte beviljad».
        let besked: String
        /// Hur det ordnas, när det saknas.
        var åtgärd: String?
        /// Systeminställningarnas sida för en behörighet.
        var länk: URL?
    }

    /// Alla rader: det som går att se på disk och i behörigheterna direkt,
    /// och därefter det som kräver att en server svarar.
    static func kör() async -> [Rad] {
        var rader = lokala()
        rader += await servrar()
        rader += behörigheter()
        return rader
    }

    // MARK: - Filer på disk

    static func lokala() -> [Rad] {
        var ut: [Rad] = []
        let fm = FileManager.default
        let hem = fm.homeDirectoryForCurrentUser

        let whisper = Whisper.Sökvägar.standard
        let brister = whisper.brister
        ut.append(Rad(id: "whisper", namn: "whisper.cpp",
                      läge: brister.isEmpty ? .ok : .saknas,
                      besked: brister.isEmpty ? förkorta(whisper.rot.path) : brister.joined(separator: " · "),
                      åtgärd: brister.isEmpty ? nil : "scripts/installera.sh bygger whisper.cpp och hämtar modellerna"))

        let röst = Röstanalys.Sökvägar.standard
        let röstbrister = röst.brister
        ut.append(Rad(id: "python", namn: "Röstanalys (Python)",
                      läge: röstbrister.isEmpty ? .ok : .saknas,
                      besked: röstbrister.isEmpty ? förkorta(röst.python.path) : röstbrister.joined(separator: " · "),
                      åtgärd: röstbrister.isEmpty ? nil : "scripts/installera.sh skapar Pythonmiljön med torch, speechbrain och pyannote"))

        ut.append(Rad(id: "pyannote", namn: "pyannote",
                      läge: röst.harDiarisering ? .ok : .frivilligt,
                      besked: röst.harDiarisering ? "modellen finns i huggingface-cachen"
                          : "saknas i cachen; rösterna delas upp med klustring, som är sämre",
                      åtgärd: röst.harDiarisering ? nil : "scripts/installera.sh hämtar pyannote/speaker-diarization-3.1 (kräver en Hugging Face-inloggning)"))

        let mlx = MlxWhisper.körbar
        let harMlx = fm.isExecutableFile(atPath: mlx.path)
        ut.append(Rad(id: "mlx", namn: "mlx_whisper",
                      läge: harMlx ? .ok : .frivilligt,
                      besked: harMlx ? förkorta(mlx.path) : "saknas; engelska möten behöver den eller en molnmotor",
                      åtgärd: harMlx ? nil : "pip install mlx-whisper i Pythonmiljön"))

        let claude = Kodagent.hitta()
        let harClaude = fm.isExecutableFile(atPath: claude.path)
        ut.append(Rad(id: "claude", namn: "Claude Code",
                      läge: harClaude ? .ok : .frivilligt,
                      besked: harClaude ? "kopplade kodmappar kan genomsökas när Anthropic är valt"
                          : "saknas; kodmappar genomsöks inte",
                      åtgärd: harClaude ? nil : "Installera Claude Code, så hittas den i \(förkorta(hem.appending(path: ".local/bin").path))"))
        return ut
    }

    // MARK: - Servrar

    static func servrar() async -> [Rad] {
        var ut: [Rad] = []
        let val = Modellval.läs()
        let bas = val.lokalBas ?? URL(string: "http://127.0.0.1:11434")!
        let modeller = await ollamaModeller(bas)
        let värd = "\(bas.host ?? "127.0.0.1"):\(bas.port ?? 11434)"

        if let modeller {
            ut.append(Rad(id: "ollama", namn: "Ollama", läge: .ok, besked: "svarar på \(värd)"))
            if val.leverantör == .lokal {
                let finns = modeller.contains { $0.hasPrefix(val.modell) }
                ut.append(Rad(id: "chattmodell", namn: "Modellen \(val.modell)",
                              läge: finns ? .ok : .saknas,
                              besked: finns ? "hämtad, används för chatt och sammanfattningar"
                                  : "finns inte hos \(värd)",
                              åtgärd: finns ? nil : "ollama pull \(val.modell)"))
            }
            let insikt = Inställningar.insiktsmodell
            let harInsikt = modeller.contains { $0.hasPrefix(insikt) }
            ut.append(Rad(id: "insiktsmodell", namn: "Insikter · \(insikt)",
                          läge: harInsikt ? .ok : .frivilligt,
                          besked: harInsikt ? "lyssnar efter frågeställningar under samtal"
                              : "saknas; inga insikter under samtal",
                          åtgärd: harInsikt ? nil : "ollama pull \(insikt)"))
            let harBge = modeller.contains { $0.hasPrefix(Inbäddare.modell) }
            ut.append(Rad(id: "bge", namn: Inbäddare.modell,
                          läge: harBge ? .ok : .frivilligt,
                          besked: harBge ? "betydelsesökningen är på" : "saknas; sökningen går bara på ord",
                          åtgärd: harBge ? nil : "ollama pull \(Inbäddare.modell)"))
        } else {
            ut.append(Rad(id: "ollama", namn: "Ollama",
                          läge: val.leverantör == .lokal ? .saknas : .frivilligt,
                          besked: "svarar inte på \(värd)",
                          åtgärd: "Starta Ollama (brew services start ollama) eller peka ut en annan adress under Modell"))
        }
        return ut
    }

    /// Modellnamnen hos en Ollama-server, nil när den inte svarar.
    static func ollamaModeller(_ bas: URL) async -> [String]? {
        var r = URLRequest(url: bas.appending(path: "api/tags"))
        r.timeoutInterval = 2
        guard let (data, _) = try? await URLSession.shared.data(for: r),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modeller = json["models"] as? [[String: Any]] else { return nil }
        return modeller.compactMap { $0["name"] as? String }
    }

    // MARK: - Behörigheter

    static func behörigheter() -> [Rad] {
        func rad(_ id: String, _ namn: String, _ beviljad: Bool, _ sida: String,
                 utan: String, frivillig: Bool = false) -> Rad {
            Rad(id: id, namn: namn,
                läge: beviljad ? .ok : (frivillig ? .frivilligt : .saknas),
                besked: beviljad ? "beviljad" : "inte beviljad; \(utan)",
                åtgärd: beviljad ? nil : "Systeminställningar › Integritet och säkerhet › \(sida)",
                länk: beviljad ? nil : URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(id)"))
        }
        let mik = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let skärm = CGPreflightScreenCaptureAccess()
        return [
            rad("Microphone", "Mikrofon", mik, "Mikrofon", utan: "ditt eget spår kan inte spelas in"),
            rad("ScreenCapture", "Skärminspelning (datorljud)", skärm, "Skärminspelning",
                utan: "motpartens ljud i Teams och Zoom kan inte fångas"),
            rad("Calendars", "Kalender", Kalendern.shared.harTillgång, "Kalendrar",
                utan: "inga kommande möten och ingen brief", frivillig: true),
            rad("Contacts", "Kontakter", Adressboken.shared.harTillgång, "Kontakter",
                utan: "inga förslag ur macOS Kontakter", frivillig: true),
            rad("Reminders", "Påminnelser", Påminnelser.delad.harTillgång, "Påminnelser",
                utan: "kort kan inte läggas i Påminnelser", frivillig: true),
            Rad(id: "Automation", namn: "Mail (automatisering)", läge: .frivilligt,
                besked: "frågas första gången mejl hämtas; ett nej syns som «når inte Mail» i arbetsraden",
                åtgärd: "Systeminställningar › Integritet och säkerhet › Automatisering › Critero-kundkoll › Mail",
                länk: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")),
        ]
    }

    private static func förkorta(_ väg: String) -> String {
        let hem = FileManager.default.homeDirectoryForCurrentUser.path
        return väg.hasPrefix(hem) ? "~" + väg.dropFirst(hem.count) : väg
    }
}

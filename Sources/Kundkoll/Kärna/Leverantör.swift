import Foundation

/// Var modellen körs.
///
/// Alla utom Anthropic talar OpenAI:s chat/completions-format, så det finns i
/// praktiken två dialekter att hantera. En lokal modell (Ollama, LM Studio,
/// llama.cpp) talar också OpenAI-formatet och behöver ingen nyckel — den är
/// vägen att gå när materialet inte får lämna datorn alls.
enum Leverantör: String, Codable, CaseIterable, Identifiable {
    case openrouter, anthropic, openai, azure, lokal

    var id: String { rawValue }

    var namn: String {
        switch self {
        case .openrouter: "OpenRouter"
        case .anthropic: "Anthropic"
        case .openai: "OpenAI"
        case .azure: "Azure OpenAI"
        case .lokal: "Lokal modell"
        }
    }

    var beskrivning: String {
        switch self {
        case .openrouter: "En nyckel till många modeller."
        case .anthropic: "Claude direkt från Anthropic."
        case .openai: "GPT direkt från OpenAI."
        case .azure: "OpenAI-modeller i din egen Azure-resurs."
        case .lokal: "Ollama, LM Studio, MLX (mlx_lm) eller llama.cpp på den här datorn. Inget material lämnar maskinen."
        }
    }

    /// Anthropic har ett eget format; övriga följer OpenAI:s.
    var talarAnthropic: Bool { self == .anthropic }

    var behöverNyckel: Bool { self != .lokal }

    /// Azure lägger resurs och distribution i adressen, så den måste anges.
    var behöverEgenAdress: Bool { self == .azure || self == .lokal }

    var standardadress: String {
        switch self {
        case .openrouter: "https://openrouter.ai/api/v1/chat/completions"
        case .anthropic: "https://api.anthropic.com/v1/messages"
        case .openai: "https://api.openai.com/v1/chat/completions"
        case .azure: "https://DIN-RESURS.openai.azure.com/openai/deployments/DIN-DISTRIBUTION/chat/completions?api-version=2025-01-01-preview"
        case .lokal: "http://127.0.0.1:11434/v1/chat/completions"
        }
    }

    var standardmodell: String {
        switch self {
        // Sonnet 5 räcker gott för att sammanfatta och svara ur ett underlag,
        // till halva priset mot Opus. Byt till claude-opus-5 för svårare frågor.
        case .openrouter: "anthropic/claude-sonnet-5"
        case .anthropic: "claude-sonnet-5"
        case .openai: "gpt-5"
        case .azure: ""          // distributionen står i adressen
        case .lokal: "qwen3:8b"
        }
    }

    var nyckelkonto: String { "kundkoll-\(rawValue)" }

    /// Miljövariabeln som gäller före nyckelringen, så att en nyckel man
    /// redan har i skalet fungerar utan att läggas in på nytt.
    var miljövariabel: String {
        switch self {
        case .openrouter: "OPENROUTER_API_KEY"
        case .anthropic: "ANTHROPIC_API_KEY"
        case .openai: "OPENAI_API_KEY"
        case .azure: "AZURE_OPENAI_API_KEY"
        case .lokal: "KUNDKOLL_LOKAL_NYCKEL"
        }
    }

    /// Var man hämtar en nyckel, för hjälptexten i inställningarna.
    var nyckeladress: String? {
        switch self {
        case .openrouter: "openrouter.ai/keys"
        case .anthropic: "console.anthropic.com"
        case .openai: "platform.openai.com/api-keys"
        case .azure: "Azure-portalen, under din OpenAI-resurs"
        case .lokal: nil
        }
    }
}

/// Vald leverantör och dess inställningar.
struct Modellval: Codable, Hashable {
    // Lokalt är standard: appen lovar att inget lämnar datorn utan ett val,
    // och då kan inte ett moln vara det man får utan att välja.
    var leverantör: Leverantör = .lokal
    var modell: String = Leverantör.lokal.standardmodell
    /// Tom betyder leverantörens standardadress.
    var adress: String = ""

    init(leverantör: Leverantör = .lokal, modell: String? = nil, adress: String = "") {
        self.leverantör = leverantör
        self.modell = modell ?? leverantör.standardmodell
        self.adress = adress
    }

    /// Skriven för hand: se `Inspelning`.
    init(from avkodare: Decoder) throws {
        let c = try avkodare.container(keyedBy: CodingKeys.self)
        leverantör = try c.decodeIfPresent(Leverantör.self, forKey: .leverantör) ?? .lokal
        modell = try c.decodeIfPresent(String.self, forKey: .modell) ?? leverantör.standardmodell
        adress = try c.decodeIfPresent(String.self, forKey: .adress) ?? ""
    }

    var url: URL? {
        URL(string: adress.isEmpty ? leverantör.standardadress : adress)
    }

    /// Sant bara när adressen pekar på den här datorn. «Lokal modell» med
    /// en adress ute på nätet är ett moln, hur leverantören än heter.
    var ärLokalAdress: Bool {
        guard let u = url, let värd = URLComponents(url: u, resolvingAgainstBaseURL: false)?.host?.lowercased()
        else { return false }
        return ["127.0.0.1", "localhost", "::1", "0.0.0.0"].contains(värd)
    }

    /// Lämnar materialet datorn med det här valet?
    var lämnarDatorn: Bool { !ärLokalAdress }

    /// Servern bakom «Lokal modell», utan sökväg: det insikterna och
    /// inbäddningen frågar via Ollamas eget API. Stod förut inskrivet som
    /// 127.0.0.1:11434 på fem ställen, så adressfältet gällde bara chatten.
    var lokalBas: URL? {
        guard leverantör == .lokal, let u = url,
              var d = URLComponents(url: u, resolvingAgainstBaseURL: false) else { return nil }
        d.path = ""; d.query = nil
        return d.url
    }

    /// Att visa där valet får verkan: «Lokalt · qwen3:8b», «Anthropic · claude-sonnet-5».
    var etikett: String {
        let m = modell.isEmpty ? "distributionen i adressen" : modell
        return leverantör == .lokal && ärLokalAdress ? "Lokalt · \(m)" : "\(leverantör.namn) · \(m)"
    }

    /// Molnleverantörer som redan har en nyckel i nyckelringen, för
    /// «Kör via …» på jobb Pär startar själv. Azure kräver egen adress och
    /// väljs bara via inställningarna.
    static func molnAlternativ() -> [Modellval] {
        Leverantör.allCases
            .filter { $0 != .lokal && $0 != .azure && Nyckelring.förLeverantör($0) != nil }
            .map { Modellval(leverantör: $0) }
    }

    var färdig: Bool {
        guard url != nil else { return false }
        if leverantör.behöverNyckel && Nyckelring.förLeverantör(leverantör) == nil {
            return false
        }
        if leverantör == .azure { return !adress.isEmpty && !adress.contains("DIN-RESURS") }
        return !modell.isEmpty || leverantör == .azure
    }

    /// Sparas som inställning, inte i en kundmapp — valet gäller hela appen.
    private static let nyckel = "kundkoll.modellval"

    static func läs() -> Modellval {
        guard let data = UserDefaults.standard.data(forKey: nyckel),
              let v = try? JSONDecoder().decode(Modellval.self, from: data) else {
            return Modellval()
        }
        return v
    }

    func spara() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.nyckel)
    }
}

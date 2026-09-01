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
        case .lokal: "Ollama, LM Studio eller llama.cpp på den här datorn. Inget material lämnar maskinen."
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
        case .lokal: "llama3.1:8b"
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
    var leverantör: Leverantör = .openrouter
    var modell: String = Leverantör.openrouter.standardmodell
    /// Tom betyder leverantörens standardadress.
    var adress: String = ""

    var url: URL? {
        URL(string: adress.isEmpty ? leverantör.standardadress : adress)
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

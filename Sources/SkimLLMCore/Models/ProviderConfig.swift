import Foundation

public enum ProviderPreset: String, Codable, CaseIterable, Sendable {
    case openAICompatible
    case deepSeek

    public var label: String {
        switch self {
        case .openAICompatible:
            return "OpenAI compatible"
        case .deepSeek:
            return "DeepSeek"
        }
    }
}

public enum PDFContextMode: String, Codable, CaseIterable, Sendable {
    case retrieval
    case deepSeekLongContext

    public var label: String {
        switch self {
        case .retrieval:
            return "Retrieval"
        case .deepSeekLongContext:
            return "DeepSeek long context"
        }
    }
}

public enum DeepSeekReasoningEffort: String, Codable, CaseIterable, Sendable {
    case high
    case max
}

public enum DeepSeekInteractionMode: String, Codable, CaseIterable, Sendable {
    case fastReading
    case deepAnalysis

    public var label: String {
        switch self {
        case .fastReading:
            return "Fast Reading"
        case .deepAnalysis:
            return "Deep Analysis"
        }
    }

    public var shortLabel: String {
        switch self {
        case .fastReading:
            return "Fast"
        case .deepAnalysis:
            return "Deep"
        }
    }

    public var model: String {
        switch self {
        case .fastReading:
            return "deepseek-v4-flash"
        case .deepAnalysis:
            return "deepseek-v4-pro"
        }
    }

    public var thinkingEnabled: Bool {
        switch self {
        case .fastReading:
            return false
        case .deepAnalysis:
            return true
        }
    }
}

public struct LLMProviderConfig: Codable, Equatable, Sendable {
    public var providerPreset: ProviderPreset
    public var baseURL: String
    public var model: String
    public var supportsPDFInput: Bool
    public var useFullPDFWhenAvailable: Bool
    public var contextMode: PDFContextMode
    public var deepSeekInteractionMode: DeepSeekInteractionMode
    public var deepSeekThinkingEnabled: Bool
    public var deepSeekReasoningEffort: DeepSeekReasoningEffort
    public var maxLongContextCharacters: Int
    public var autoDockToSkim: Bool
    public var sidebarWidth: Double

    public init(
        providerPreset: ProviderPreset = .deepSeek,
        baseURL: String = "https://api.deepseek.com",
        model: String = "deepseek-v4-flash",
        supportsPDFInput: Bool = false,
        useFullPDFWhenAvailable: Bool = false,
        contextMode: PDFContextMode = .deepSeekLongContext,
        deepSeekInteractionMode: DeepSeekInteractionMode = .fastReading,
        deepSeekThinkingEnabled: Bool = false,
        deepSeekReasoningEffort: DeepSeekReasoningEffort = .high,
        maxLongContextCharacters: Int = 700_000,
        autoDockToSkim: Bool = true,
        sidebarWidth: Double = 440
    ) {
        self.providerPreset = providerPreset
        self.baseURL = baseURL
        self.model = model
        self.supportsPDFInput = supportsPDFInput
        self.useFullPDFWhenAvailable = useFullPDFWhenAvailable
        self.contextMode = contextMode
        self.deepSeekInteractionMode = deepSeekInteractionMode
        self.deepSeekThinkingEnabled = deepSeekThinkingEnabled
        self.deepSeekReasoningEffort = deepSeekReasoningEffort
        self.maxLongContextCharacters = maxLongContextCharacters
        self.autoDockToSkim = autoDockToSkim
        self.sidebarWidth = sidebarWidth
    }

    public var normalizedBaseURL: URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    public var isDeepSeekOptimized: Bool {
        providerPreset == .deepSeek || normalizedBaseURL?.host?.contains("deepseek.com") == true
    }

    public mutating func applyDeepSeekDefaults() {
        providerPreset = .deepSeek
        baseURL = "https://api.deepseek.com"
        model = model.isEmpty || model == "gpt-4o-mini" ? "deepseek-v4-flash" : model
        supportsPDFInput = false
        useFullPDFWhenAvailable = false
        contextMode = .deepSeekLongContext
        applyDeepSeekInteractionMode(.fastReading)
        deepSeekInteractionMode = .fastReading
        deepSeekReasoningEffort = .high
        maxLongContextCharacters = 700_000
    }

    public mutating func applyDeepSeekInteractionMode(_ mode: DeepSeekInteractionMode) {
        deepSeekInteractionMode = mode
        model = mode.model
        deepSeekThinkingEnabled = mode.thinkingEnabled
        if mode == .deepAnalysis {
            deepSeekReasoningEffort = .high
        }
    }

    enum CodingKeys: String, CodingKey {
        case providerPreset
        case baseURL
        case model
        case supportsPDFInput
        case useFullPDFWhenAvailable
        case contextMode
        case deepSeekInteractionMode
        case deepSeekThinkingEnabled
        case deepSeekReasoningEffort
        case maxLongContextCharacters
        case autoDockToSkim
        case sidebarWidth
    }

    public init(from decoder: Decoder) throws {
        let defaults = LLMProviderConfig()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        providerPreset = try container.decodeIfPresent(ProviderPreset.self, forKey: .providerPreset) ?? defaults.providerPreset
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? defaults.baseURL
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? defaults.model
        supportsPDFInput = try container.decodeIfPresent(Bool.self, forKey: .supportsPDFInput) ?? defaults.supportsPDFInput
        useFullPDFWhenAvailable = try container.decodeIfPresent(Bool.self, forKey: .useFullPDFWhenAvailable) ?? defaults.useFullPDFWhenAvailable
        contextMode = try container.decodeIfPresent(PDFContextMode.self, forKey: .contextMode) ?? defaults.contextMode
        deepSeekInteractionMode = try container.decodeIfPresent(DeepSeekInteractionMode.self, forKey: .deepSeekInteractionMode) ?? defaults.deepSeekInteractionMode
        deepSeekThinkingEnabled = try container.decodeIfPresent(Bool.self, forKey: .deepSeekThinkingEnabled) ?? defaults.deepSeekThinkingEnabled
        deepSeekReasoningEffort = try container.decodeIfPresent(DeepSeekReasoningEffort.self, forKey: .deepSeekReasoningEffort) ?? defaults.deepSeekReasoningEffort
        maxLongContextCharacters = try container.decodeIfPresent(Int.self, forKey: .maxLongContextCharacters) ?? defaults.maxLongContextCharacters
        autoDockToSkim = try container.decodeIfPresent(Bool.self, forKey: .autoDockToSkim) ?? defaults.autoDockToSkim
        sidebarWidth = try container.decodeIfPresent(Double.self, forKey: .sidebarWidth) ?? defaults.sidebarWidth
    }
}

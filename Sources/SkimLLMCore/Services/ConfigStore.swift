import Foundation

public final class ConfigStore {
    private let defaults: UserDefaults
    private let key = "llmProviderConfig"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> LLMProviderConfig {
        guard let data = defaults.data(forKey: key),
              let config = try? JSONDecoder().decode(LLMProviderConfig.self, from: data) else {
            return LLMProviderConfig()
        }
        return config
    }

    public func save(_ config: LLMProviderConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: key)
    }
}


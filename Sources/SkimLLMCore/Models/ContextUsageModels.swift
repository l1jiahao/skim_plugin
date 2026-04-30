import Foundation

public struct ContextUsageSnapshot: Equatable, Sendable {
    public var promptTokens: Int
    public var completionTokens: Int
    public var totalTokens: Int
    public var promptCacheHitTokens: Int?
    public var promptCacheMissTokens: Int?
    public var reasoningTokens: Int?
    public var limitTokens: Int
    public var createdAt: Date?

    public init(
        promptTokens: Int,
        completionTokens: Int,
        totalTokens: Int,
        promptCacheHitTokens: Int? = nil,
        promptCacheMissTokens: Int? = nil,
        reasoningTokens: Int? = nil,
        limitTokens: Int,
        createdAt: Date? = Date()
    ) {
        self.promptTokens = max(0, promptTokens)
        self.completionTokens = max(0, completionTokens)
        self.totalTokens = max(0, totalTokens)
        self.promptCacheHitTokens = promptCacheHitTokens.map { max(0, $0) }
        self.promptCacheMissTokens = promptCacheMissTokens.map { max(0, $0) }
        self.reasoningTokens = reasoningTokens.map { max(0, $0) }
        self.limitTokens = max(1, limitTokens)
        self.createdAt = createdAt
    }

    public static func empty(limitTokens: Int) -> ContextUsageSnapshot {
        ContextUsageSnapshot(
            promptTokens: 0,
            completionTokens: 0,
            totalTokens: 0,
            limitTokens: limitTokens,
            createdAt: nil
        )
    }

    public var hasUsage: Bool {
        createdAt != nil
    }

    public var usageRatio: Double {
        guard hasUsage else { return 0 }
        return min(Double(promptTokens) / Double(limitTokens), 1)
    }

    public var percent: Int {
        Int((usageRatio * 100).rounded())
    }

    public var isWarning: Bool {
        usageRatio >= 0.70
    }

    public var isCritical: Bool {
        usageRatio >= 0.90
    }

    public var displayText: String {
        guard hasUsage else {
            return "Context usage unavailable"
        }
        return "Last context \(Self.compactNumber(promptTokens)) / \(Self.compactNumber(limitTokens))"
    }

    public var detailText: String {
        guard hasUsage else {
            return "Send a message to get real provider usage."
        }

        var parts = [
            "Output \(Self.compactNumber(completionTokens))",
            "Total \(Self.compactNumber(totalTokens))"
        ]
        if let promptCacheHitTokens {
            parts.append("Cache hit \(Self.compactNumber(promptCacheHitTokens))")
        }
        if let promptCacheMissTokens {
            parts.append("Miss \(Self.compactNumber(promptCacheMissTokens))")
        }
        if let reasoningTokens {
            parts.append("Reasoning \(Self.compactNumber(reasoningTokens))")
        }
        return parts.joined(separator: " · ")
    }

    private static func compactNumber(_ value: Int) -> String {
        if value >= 1_000_000 {
            let number = Double(value) / 1_000_000
            return number.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(number))M"
                : String(format: "%.1fM", number)
        }
        if value >= 1_000 {
            let number = Double(value) / 1_000
            return number.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(number))K"
                : String(format: "%.1fK", number)
        }
        return "\(value)"
    }
}

public struct LLMResponseUsage: Equatable, Sendable {
    public var promptTokens: Int
    public var completionTokens: Int
    public var totalTokens: Int
    public var promptCacheHitTokens: Int?
    public var promptCacheMissTokens: Int?
    public var reasoningTokens: Int?

    public init(
        promptTokens: Int,
        completionTokens: Int,
        totalTokens: Int,
        promptCacheHitTokens: Int? = nil,
        promptCacheMissTokens: Int? = nil,
        reasoningTokens: Int? = nil
    ) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.promptCacheHitTokens = promptCacheHitTokens
        self.promptCacheMissTokens = promptCacheMissTokens
        self.reasoningTokens = reasoningTokens
    }
}

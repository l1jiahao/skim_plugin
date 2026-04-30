import Foundation

public final class LLMClient {
    private let session: URLSession
    private let maxPDFBytes = 50 * 1024 * 1024

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func streamChat(
        question: String,
        history: [ChatMessage],
        context: PDFContextPackage,
        config: LLMProviderConfig,
        apiKey: String,
        onDelta: @escaping (String) async -> Void,
        onReasoningDelta: @escaping (String) async -> Void = { _ in },
        onUsage: @escaping (LLMResponseUsage) async -> Void = { _ in }
    ) async throws -> String {
        guard let baseURL = config.normalizedBaseURL else {
            throw LLMClientError.invalidBaseURL
        }
        let url = baseURL
            .appendingPathComponent("chat")
            .appendingPathComponent("completions")
        let payload = try makeChatPayload(
            question: question,
            history: history,
            context: context,
            config: config
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMClientError.invalidResponse
        }

        if !(200..<300).contains(http.statusCode) {
            var body = ""
            for try await line in bytes.lines {
                body += line
            }
            throw LLMClientError.http(status: http.statusCode, body: body)
        }

        var answer = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8) else { continue }
            if let chunk = try? JSONDecoder().decode(ChatCompletionStreamChunk.self, from: data) {
                if let usage = chunk.usage?.snapshot {
                    await onUsage(usage)
                }

                let reasoningDelta = chunk.choices.compactMap { $0.delta?.reasoningContent }.joined()
                if !reasoningDelta.isEmpty {
                    await onReasoningDelta(reasoningDelta)
                }

                let delta = chunk.choices.compactMap { $0.delta?.content }.joined()
                if !delta.isEmpty {
                    answer += delta
                    await onDelta(delta)
                }
            }
        }

        return answer
    }

    private func makeChatPayload(
        question: String,
        history: [ChatMessage],
        context: PDFContextPackage,
        config: LLMProviderConfig
    ) throws -> [String: Any] {
        let messages: [[String: Any]]

        if config.isDeepSeekOptimized && context.contextMode == .deepSeekLongContext {
            messages = makeDeepSeekMessages(question: question, history: history, context: context)
        } else {
            messages = try makeCompatibleMessages(question: question, history: history, context: context)
        }

        var payload: [String: Any] = [
            "model": config.model,
            "messages": messages,
            "stream": true
        ]

        if config.isDeepSeekOptimized {
            payload["stream_options"] = ["include_usage": true]
            payload["thinking"] = ["type": config.deepSeekThinkingEnabled ? "enabled" : "disabled"]
            if config.deepSeekThinkingEnabled {
                payload["reasoning_effort"] = config.deepSeekReasoningEffort.rawValue
            } else {
                payload["temperature"] = 0.2
            }
        }

        return payload
    }

    private func makeDeepSeekMessages(
        question: String,
        history: [ChatMessage],
        context: PDFContextPackage
    ) -> [[String: Any]] {
        var messages: [[String: Any]] = [
            ["role": "system", "content": PromptBuilder.deepSeekSystemPrompt],
            ["role": "user", "content": PromptBuilder.deepSeekDocumentPrompt(context: context)],
            ["role": "assistant", "content": "Document loaded. I will answer future questions using the supplied paper text and page markers."]
        ]

        // DeepSeek chat completions are stateless. Re-send the full local
        // conversation history so Fast/Deep mode switches keep prior turns.
        for message in history where message.role != .system && !message.content.isEmpty {
            messages.append([
                "role": message.role.rawValue,
                "content": message.content
            ])
        }

        messages.append([
            "role": "user",
            "content": PromptBuilder.deepSeekQuestionPrompt(question: question, context: context)
        ])
        return messages
    }

    private func makeCompatibleMessages(
        question: String,
        history: [ChatMessage],
        context: PDFContextPackage
    ) throws -> [[String: Any]] {
        let prompt = PromptBuilder.userPrompt(question: question, context: context)
        var messages: [[String: Any]] = [
            ["role": "system", "content": PromptBuilder.systemPrompt]
        ]

        for message in history.suffix(8) where message.role != .system && !message.content.isEmpty {
            messages.append([
                "role": message.role.rawValue,
                "content": message.content
            ])
        }

        if context.attachFullPDF {
            guard let fileURL = context.fileURL else {
                throw LLMClientError.missingPDF
            }
            let data = try Data(contentsOf: fileURL)
            guard data.count <= maxPDFBytes else {
                throw LLMClientError.pdfTooLarge(maxPDFBytes)
            }
            messages.append([
                "role": "user",
                "content": [
                    [
                        "type": "file",
                        "file": [
                            "filename": fileURL.lastPathComponent,
                            "file_data": "data:application/pdf;base64,\(data.base64EncodedString())"
                        ]
                    ],
                    [
                        "type": "text",
                        "text": prompt
                    ]
                ]
            ])
        } else {
            messages.append(["role": "user", "content": prompt])
        }

        return messages
    }
}

public enum LLMClientError: Error, LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case missingPDF
    case pdfTooLarge(Int)
    case http(status: Int, body: String)

    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "The provider base URL is invalid."
        case .invalidResponse:
            return "The provider returned a non-HTTP response."
        case .missingPDF:
            return "Full PDF mode is enabled, but no PDF file is available."
        case .pdfTooLarge(let maxBytes):
            return "The PDF is larger than the configured \(maxBytes / 1024 / 1024) MB limit."
        case .http(let status, let body):
            let message = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return "Provider request failed with HTTP \(status). \(message)"
        }
    }
}

private struct ChatCompletionStreamChunk: Decodable {
    struct Usage: Decodable {
        struct CompletionTokensDetails: Decodable {
            let reasoningTokens: Int?

            enum CodingKeys: String, CodingKey {
                case reasoningTokens = "reasoning_tokens"
            }
        }

        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int
        let promptCacheHitTokens: Int?
        let promptCacheMissTokens: Int?
        let completionTokensDetails: CompletionTokensDetails?

        var snapshot: LLMResponseUsage {
            LLMResponseUsage(
                promptTokens: promptTokens,
                completionTokens: completionTokens,
                totalTokens: totalTokens,
                promptCacheHitTokens: promptCacheHitTokens,
                promptCacheMissTokens: promptCacheMissTokens,
                reasoningTokens: completionTokensDetails?.reasoningTokens
            )
        }

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
            case promptCacheHitTokens = "prompt_cache_hit_tokens"
            case promptCacheMissTokens = "prompt_cache_miss_tokens"
            case completionTokensDetails = "completion_tokens_details"
        }
    }

    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
            let reasoningContent: String?

            enum CodingKeys: String, CodingKey {
                case content
                case reasoningContent = "reasoning_content"
            }
        }

        let delta: Delta?
    }

    let choices: [Choice]
    let usage: Usage?

    enum CodingKeys: String, CodingKey {
        case choices
        case usage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        choices = try container.decodeIfPresent([Choice].self, forKey: .choices) ?? []
        usage = try container.decodeIfPresent(Usage.self, forKey: .usage)
    }
}

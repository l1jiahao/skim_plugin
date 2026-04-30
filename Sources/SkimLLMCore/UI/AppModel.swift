import AppKit
import Foundation
import SwiftUI

@MainActor
public final class AppModel: ObservableObject {
    @Published public var documentState: SkimDocumentState?
    @Published public var indexState: PDFIndexState = .idle
    @Published public var messages: [ChatMessage] = [
        ChatMessage(role: .assistant, content: "Open a PDF in Skim, then ask a question here.")
    ]
    @Published public var draft: String = ""
    @Published public var config: LLMProviderConfig
    @Published public var apiKeyDraft: String
    @Published public var isSending = false
    @Published public var runtimeError: String?
    @Published public var lastContextChunks: [PDFChunk] = []
    @Published public var sessionSummaries: [ChatSessionSummary] = []
    @Published public var activeSessionID: UUID?

    private let bridge = SkimBridge()
    private let configStore = ConfigStore()
    private let secretStore = LocalSecretStore()
    private let chatSessionStore: ChatSessionStore?
    private let llmClient = LLMClient()
    private let indexService: PDFIndexService?
    private weak var window: NSWindow?
    private var pollTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?
    private var indexingTask: Task<Void, Never>?
    private var indexedPath: String?
    private var activeDocumentKey: String?

    public init() {
        config = configStore.load()
        apiKeyDraft = secretStore.readAPIKey()
        do {
            indexService = try PDFIndexService()
        } catch {
            indexService = nil
            runtimeError = error.localizedDescription
        }
        do {
            chatSessionStore = try ChatSessionStore()
        } catch {
            chatSessionStore = nil
            runtimeError = error.localizedDescription
        }
    }

    deinit {
        pollTask?.cancel()
        sendTask?.cancel()
        indexingTask?.cancel()
    }

    public func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshSkimState()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    public func attach(window: NSWindow) {
        self.window = window
        window.title = "Skim LLM"
        window.minSize = NSSize(width: 360, height: 420)
        window.collectionBehavior.insert(.fullScreenAuxiliary)
    }

    public func persistSettings() {
        configStore.save(config)
        do {
            try secretStore.saveAPIKey(apiKeyDraft)
            runtimeError = nil
        } catch {
            runtimeError = error.localizedDescription
        }
    }

    public func setDeepSeekInteractionMode(_ mode: DeepSeekInteractionMode) {
        config.applyDeepSeekInteractionMode(mode)
        persistSettings()
    }

    public func startNewSession() {
        saveCurrentSessionIfNeeded()
        activeSessionID = nil
        lastContextChunks = []
        if let state = documentState {
            messages = [Self.welcomeMessage(for: state)]
            reloadSessionSummaries(documentKey: activeDocumentKey)
        } else {
            messages = [Self.noDocumentMessage]
            sessionSummaries = []
        }
    }

    public func openSession(_ id: UUID) {
        guard let documentKey = activeDocumentKey, let chatSessionStore else { return }
        if activeSessionID != id {
            saveCurrentSessionIfNeeded()
        }

        do {
            guard let record = try chatSessionStore.loadSession(documentKey: documentKey, id: id) else { return }
            activeSessionID = record.summary.id
            messages = record.messages
            lastContextChunks = []
            reloadSessionSummaries(documentKey: documentKey)
            runtimeError = nil
        } catch {
            runtimeError = error.localizedDescription
        }
    }

    public func deleteSession(_ id: UUID) {
        guard let documentKey = activeDocumentKey, let chatSessionStore else { return }

        do {
            try chatSessionStore.deleteSession(documentKey: documentKey, id: id)
            if activeSessionID == id {
                activeSessionID = nil
                lastContextChunks = []
                if let state = documentState {
                    messages = [Self.welcomeMessage(for: state)]
                } else {
                    messages = [Self.noDocumentMessage]
                }
            }
            reloadSessionSummaries(documentKey: documentKey)
            runtimeError = nil
        } catch {
            runtimeError = error.localizedDescription
        }
    }

    public func sendCurrentDraft() {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        let apiKey = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            runtimeError = "Add an API key in settings before asking a question."
            return
        }
        guard !isSending else { return }

        let history = messages
        let assistantID = UUID()
        messages.append(ChatMessage(role: .user, content: question))
        messages.append(ChatMessage(id: assistantID, role: .assistant, content: ""))
        draft = ""
        isSending = true
        runtimeError = nil

        let currentConfig = config
        sendTask = Task { [weak self] in
            guard let self else { return }
            do {
                let context = await self.makeContext(question: question)
                await MainActor.run {
                    self.lastContextChunks = context.retrievedChunks
                }

                let answer = try await self.llmClient.streamChat(
                    question: question,
                    history: history,
                    context: context,
                    config: currentConfig,
                    apiKey: apiKey
                ) { delta in
                    await MainActor.run {
                        self.append(delta: delta, to: assistantID)
                    }
                } onReasoningDelta: { delta in
                    await MainActor.run {
                        self.append(reasoningDelta: delta, to: assistantID)
                    }
                }

                await MainActor.run {
                    if answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.replaceMessage(id: assistantID, content: "No text was returned by the provider.")
                    }
                    self.saveCurrentSessionIfNeeded()
                    self.isSending = false
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.replaceMessage(id: assistantID, content: "Request cancelled.")
                    self.saveCurrentSessionIfNeeded()
                    self.isSending = false
                }
            } catch {
                await MainActor.run {
                    self.replaceMessage(id: assistantID, content: "Request failed.")
                    self.runtimeError = error.localizedDescription
                    self.saveCurrentSessionIfNeeded()
                    self.isSending = false
                }
            }
        }
    }

    public func cancelSend() {
        sendTask?.cancel()
        sendTask = nil
        isSending = false
    }

    private func refreshSkimState() async {
        let bridge = self.bridge
        let result = await Task.detached {
            (bridge.frontDocument(), bridge.windowFrame())
        }.value

        if let state = result.0 {
            prepareChatSession(for: state)
            documentState = state
            ensureIndexed(state)
        } else {
            clearChatSession()
            documentState = nil
            indexedPath = nil
            indexState = .idle
        }

        if let frame = result.1 {
            dock(to: frame)
        }
    }

    private func ensureIndexed(_ state: SkimDocumentState) {
        guard indexedPath != state.fileURL.path else { return }
        guard let indexService else {
            indexState = .failed("Index service is unavailable.")
            return
        }

        indexedPath = state.fileURL.path
        indexState = .indexing(state.title)
        indexingTask?.cancel()
        indexingTask = Task { [weak self] in
            do {
                let result = try await indexService.index(fileURL: state.fileURL)
                await MainActor.run {
                    if result.hasExtractableText {
                        self?.indexState = .ready(
                            documentID: result.documentID,
                            pageCount: result.pageCount,
                            chunkCount: result.chunkCount
                        )
                    } else {
                        self?.indexState = .noText(documentID: result.documentID, pageCount: result.pageCount)
                    }
                }
            } catch {
                await MainActor.run {
                    self?.indexState = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func dock(to skimFrame: CGRect) {
        guard config.autoDockToSkim, let window else { return }
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? skimFrame
        let width = CGFloat(config.sidebarWidth)
        let gap: CGFloat = 8
        let height = min(max(skimFrame.height, 420), visible.height)
        let y = min(max(skimFrame.minY, visible.minY), visible.maxY - height)
        var x = skimFrame.maxX + gap
        if x + width > visible.maxX {
            x = max(visible.minX, visible.maxX - width)
        }
        window.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true, animate: false)
    }

    private func makeContext(question: String) async -> PDFContextPackage {
        guard let state = documentState else {
            return PDFContextPackage(
                documentTitle: "No Skim document",
                fileURL: nil,
                selectedText: nil,
                currentPageText: nil,
                retrievedChunks: [],
                documentSummary: nil,
                attachFullPDF: false,
                contextMode: config.contextMode
            )
        }

        let attachPDF = config.supportsPDFInput && config.useFullPDFWhenAvailable
        guard let documentID = indexState.documentID, let indexService else {
            return PDFContextPackage(
                documentTitle: state.title,
                fileURL: state.fileURL,
                selectedText: limited(state.selectedText, to: 8_000),
                currentPageText: nil,
                retrievedChunks: [],
                documentSummary: nil,
                attachFullPDF: attachPDF,
                contextMode: config.contextMode
            )
        }

        let pageText = try? await indexService.pageText(documentID: documentID, pageNumber: state.currentPage)
        let fullDocumentText: String?
        if config.contextMode == .deepSeekLongContext {
            fullDocumentText = try? await indexService.fullDocumentText(
                documentID: documentID,
                maxCharacters: config.maxLongContextCharacters
            )
        } else {
            fullDocumentText = nil
        }
        let searchText = "\(question)\n\(state.selectedText)"
        let chunks = (try? await indexService.search(
            documentID: documentID,
            query: searchText,
            currentPage: state.currentPage,
            limit: 8
        )) ?? []
        let summary = try? await indexService.summary(documentID: documentID)

        return PDFContextPackage(
            documentTitle: state.title,
            fileURL: state.fileURL,
            selectedText: limited(state.selectedText, to: 8_000),
            currentPageText: limited(pageText, to: 8_000),
            retrievedChunks: chunks,
            documentSummary: limited(summary, to: 2_500),
            attachFullPDF: attachPDF,
            fullDocumentText: fullDocumentText,
            contextMode: config.contextMode
        )
    }

    private func append(delta: String, to id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content += delta
    }

    private func append(reasoningDelta: String, to id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].reasoningContent += reasoningDelta
    }

    private func replaceMessage(id: UUID, content: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content = content
    }

    private func prepareChatSession(for state: SkimDocumentState) {
        guard let chatSessionStore else { return }
        let documentKey = chatSessionStore.documentKey(for: state.fileURL)
        guard documentKey != activeDocumentKey else { return }

        saveCurrentSessionIfNeeded()
        activeDocumentKey = documentKey
        reloadSessionSummaries(documentKey: documentKey)

        if let latestSession = sessionSummaries.first,
           let record = try? chatSessionStore.loadSession(documentKey: documentKey, id: latestSession.id) {
            activeSessionID = record.summary.id
            messages = record.messages
        } else {
            activeSessionID = nil
            messages = [Self.welcomeMessage(for: state)]
        }
        lastContextChunks = []
    }

    private func clearChatSession() {
        saveCurrentSessionIfNeeded()
        activeDocumentKey = nil
        activeSessionID = nil
        sessionSummaries = []
        lastContextChunks = []
        messages = [Self.noDocumentMessage]
    }

    private func saveCurrentSessionIfNeeded() {
        guard let state = documentState,
              let documentKey = activeDocumentKey,
              let chatSessionStore,
              hasPersistableMessages else {
            return
        }

        do {
            let record = try chatSessionStore.saveSession(
                id: activeSessionID,
                documentKey: documentKey,
                documentTitle: state.title,
                documentPath: state.fileURL.path,
                messages: messages
            )
            activeSessionID = record.summary.id
            reloadSessionSummaries(documentKey: documentKey)
            runtimeError = nil
        } catch {
            runtimeError = error.localizedDescription
        }
    }

    private func reloadSessionSummaries(documentKey: String?) {
        guard let documentKey, let chatSessionStore else {
            sessionSummaries = []
            return
        }

        do {
            sessionSummaries = try chatSessionStore.listSessions(documentKey: documentKey)
        } catch {
            runtimeError = error.localizedDescription
            sessionSummaries = []
        }
    }

    private var hasPersistableMessages: Bool {
        messages.contains { $0.role == .user && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func limited(_ text: String?, to maxLength: Int) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count <= maxLength { return trimmed }
        return String(trimmed.prefix(maxLength)) + "\n\n[truncated]"
    }

    private static let noDocumentMessage = ChatMessage(role: .assistant, content: "Open a PDF in Skim, then ask a question here.")

    private static func welcomeMessage(for state: SkimDocumentState) -> ChatMessage {
        ChatMessage(role: .assistant, content: "Ready for \(state.title). Ask a question or open history to resume an earlier session.")
    }
}

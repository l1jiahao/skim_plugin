import Foundation

public struct ChatSessionSummary: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var documentKey: String
    public var documentTitle: String
    public var documentPath: String
    public var title: String
    public var messageCount: Int
    public var userMessageCount: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var preview: String

    public init(
        id: UUID,
        documentKey: String,
        documentTitle: String,
        documentPath: String,
        title: String,
        messageCount: Int,
        userMessageCount: Int,
        createdAt: Date,
        updatedAt: Date,
        preview: String
    ) {
        self.id = id
        self.documentKey = documentKey
        self.documentTitle = documentTitle
        self.documentPath = documentPath
        self.title = title
        self.messageCount = messageCount
        self.userMessageCount = userMessageCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.preview = preview
    }
}

public struct ChatSessionRecord: Codable, Equatable, Sendable {
    public var summary: ChatSessionSummary
    public var messages: [ChatMessage]

    public init(summary: ChatSessionSummary, messages: [ChatMessage]) {
        self.summary = summary
        self.messages = messages
    }
}

public struct ChatMessageSearchResult: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var sessionID: UUID
    public var sessionTitle: String
    public var role: ChatRole
    public var content: String
    public var createdAt: Date

    public init(
        id: UUID,
        sessionID: UUID,
        sessionTitle: String,
        role: ChatRole,
        content: String,
        createdAt: Date
    ) {
        self.id = id
        self.sessionID = sessionID
        self.sessionTitle = sessionTitle
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

public struct ChatEvidenceReference: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var paperID: String
    public var sessionID: UUID
    public var messageID: UUID
    public var pageNumber: Int
    public var quote: String?
    public var createdAt: Date

    public init(
        id: UUID,
        paperID: String,
        sessionID: UUID,
        messageID: UUID,
        pageNumber: Int,
        quote: String?,
        createdAt: Date
    ) {
        self.id = id
        self.paperID = paperID
        self.sessionID = sessionID
        self.messageID = messageID
        self.pageNumber = pageNumber
        self.quote = quote
        self.createdAt = createdAt
    }
}

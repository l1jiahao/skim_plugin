import Foundation

public enum ChatRole: String, Codable, Sendable {
    case system
    case user
    case assistant
}

public struct ChatMessage: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var role: ChatRole
    public var content: String
    public var reasoningContent: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        reasoningContent: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.reasoningContent = reasoningContent
        self.createdAt = createdAt
    }
}

public struct PDFChunk: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var documentID: String
    public var ordinal: Int
    public var pageNumber: Int
    public var text: String
    public var sectionHint: String?

    public init(
        id: String,
        documentID: String,
        ordinal: Int,
        pageNumber: Int,
        text: String,
        sectionHint: String? = nil
    ) {
        self.id = id
        self.documentID = documentID
        self.ordinal = ordinal
        self.pageNumber = pageNumber
        self.text = text
        self.sectionHint = sectionHint
    }
}

public struct SkimDocumentState: Identifiable, Codable, Equatable, Sendable {
    public var id: String { fileURL.path }
    public var fileURL: URL
    public var title: String
    public var pageCount: Int
    public var currentPage: Int
    public var selectedText: String

    public init(fileURL: URL, title: String, pageCount: Int, currentPage: Int, selectedText: String = "") {
        self.fileURL = fileURL
        self.title = title
        self.pageCount = pageCount
        self.currentPage = currentPage
        self.selectedText = selectedText
    }
}

public struct PDFContextPackage: Sendable {
    public var documentTitle: String
    public var fileURL: URL?
    public var selectedText: String?
    public var currentPageText: String?
    public var retrievedChunks: [PDFChunk]
    public var documentSummary: String?
    public var attachFullPDF: Bool
    public var fullDocumentText: String?
    public var contextMode: PDFContextMode

    public init(
        documentTitle: String,
        fileURL: URL?,
        selectedText: String?,
        currentPageText: String?,
        retrievedChunks: [PDFChunk],
        documentSummary: String?,
        attachFullPDF: Bool,
        fullDocumentText: String? = nil,
        contextMode: PDFContextMode = .retrieval
    ) {
        self.documentTitle = documentTitle
        self.fileURL = fileURL
        self.selectedText = selectedText
        self.currentPageText = currentPageText
        self.retrievedChunks = retrievedChunks
        self.documentSummary = documentSummary
        self.attachFullPDF = attachFullPDF
        self.fullDocumentText = fullDocumentText
        self.contextMode = contextMode
    }
}

import Foundation

public enum PDFIndexState: Equatable, Sendable {
    case idle
    case indexing(String)
    case ready(documentID: String, pageCount: Int, chunkCount: Int)
    case noText(documentID: String, pageCount: Int)
    case failed(String)

    public var label: String {
        switch self {
        case .idle:
            return "No PDF indexed"
        case .indexing(let title):
            return "Indexing \(title)"
        case .ready(_, let pageCount, let chunkCount):
            return "\(pageCount) pages, \(chunkCount) chunks indexed"
        case .noText(_, let pageCount):
            return "\(pageCount) pages, no extractable text"
        case .failed(let message):
            return "Index failed: \(message)"
        }
    }

    public var documentID: String? {
        switch self {
        case .ready(let documentID, _, _), .noText(let documentID, _):
            return documentID
        case .idle, .indexing, .failed:
            return nil
        }
    }
}

public struct PDFIndexResult: Equatable, Sendable {
    public var documentID: String
    public var pageCount: Int
    public var chunkCount: Int
    public var hasExtractableText: Bool
    public var summary: String?

    public init(documentID: String, pageCount: Int, chunkCount: Int, hasExtractableText: Bool, summary: String?) {
        self.documentID = documentID
        self.pageCount = pageCount
        self.chunkCount = chunkCount
        self.hasExtractableText = hasExtractableText
        self.summary = summary
    }
}

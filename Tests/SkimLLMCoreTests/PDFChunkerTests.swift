import XCTest
@testable import SkimLLMCore

final class PDFChunkerTests: XCTestCase {
    func testChunksKeepPageNumbersAndDocumentID() {
        let text = """
        Introduction

        This paper studies PDF reading workflows with language models.

        Method

        We split text by page and paragraph before indexing.
        """

        let chunks = PDFChunker.chunks(for: text, pageNumber: 7, documentID: "doc", startingOrdinal: 3)

        XCTAssertFalse(chunks.isEmpty)
        XCTAssertEqual(chunks.first?.documentID, "doc")
        XCTAssertEqual(chunks.first?.pageNumber, 7)
        XCTAssertEqual(chunks.first?.ordinal, 3)
    }

    func testLongTextSplitsIntoMultipleChunks() {
        let text = String(repeating: "A sentence about retrieval augmented generation. ", count: 120)
        let chunks = PDFChunker.chunks(for: text, pageNumber: 1, documentID: "doc", startingOrdinal: 0)

        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { $0.text.count <= 1_900 })
    }
}


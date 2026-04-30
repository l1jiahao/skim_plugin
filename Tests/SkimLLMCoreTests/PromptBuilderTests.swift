import XCTest
@testable import SkimLLMCore

final class PromptBuilderTests: XCTestCase {
    func testSystemPromptRequiresEvidenceBoundPaperReading() {
        XCTAssertTrue(PromptBuilder.systemPrompt.contains("Use only the supplied PDF content"))
        XCTAssertTrue(PromptBuilder.systemPrompt.contains("Cite every key paper claim"))
        XCTAssertTrue(PromptBuilder.systemPrompt.contains("say exactly what is missing"))
        XCTAssertTrue(PromptBuilder.systemPrompt.contains("figures, tables, equations, pseudocode"))
        XCTAssertTrue(PromptBuilder.systemPrompt.contains("Separate paper evidence from your own inference"))
    }

    func testDeepSeekSystemPromptUsesSamePaperReadingRules() {
        XCTAssertTrue(PromptBuilder.deepSeekSystemPrompt.contains("stable cached context"))
        XCTAssertTrue(PromptBuilder.deepSeekSystemPrompt.contains("Use only the supplied PDF content"))
        XCTAssertTrue(PromptBuilder.deepSeekSystemPrompt.contains("Cite every key paper claim"))
        XCTAssertTrue(PromptBuilder.deepSeekSystemPrompt.contains("Answer in the user's language"))
    }

    func testPromptIncludesPageCitationsAndFullPDFNotice() {
        let context = PDFContextPackage(
            documentTitle: "Example",
            fileURL: nil,
            selectedText: "Selected equation",
            currentPageText: "Current page",
            retrievedChunks: [
                PDFChunk(id: "c1", documentID: "d", ordinal: 0, pageNumber: 12, text: "Relevant evidence")
            ],
            documentSummary: "Short summary",
            attachFullPDF: true
        )

        let prompt = PromptBuilder.userPrompt(question: "Explain it", context: context)

        XCTAssertTrue(prompt.contains("Document: Example"))
        XCTAssertTrue(prompt.contains("[p. 12]"))
        XCTAssertTrue(prompt.contains("The complete PDF is attached"))
        XCTAssertTrue(prompt.contains("Explain it"))
    }
}

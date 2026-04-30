import Foundation

public enum PromptBuilder {
    private static let paperReadingRules = """
    Paper reading protocol:
    - Use only the supplied PDF content for paper-specific claims. Do not fill gaps with outside knowledge. If the user explicitly asks for background knowledge, label it as background rather than paper evidence.
    - Cite every key paper claim with page markers like [p. N]. When the text exposes a section, figure, table, equation, algorithm, or citation identifier, include that locator too.
    - If the supplied context does not contain enough evidence, say exactly what is missing instead of guessing. If the PDF text appears incomplete, scanned, or OCR-limited, state that limitation directly.
    - For summaries and explanations, prioritize the paper's method, assumptions, experimental design, baselines, metrics, ablations, statistical results, limitations, and failure cases over fluent abstract-style paraphrase.
    - Read figures, tables, equations, pseudocode, and supplementary-material references when they are present in the supplied content. If they are referenced but not visible or extractable, say that you cannot inspect them from the provided context.
    - Separate paper evidence from your own inference. Mark uncertain interpretations as uncertain.
    - Answer in the user's language unless they ask otherwise.
    """

    public static let systemPrompt = """
    You are a careful PDF paper reading assistant connected to Skim.

    \(paperReadingRules)
    """

    public static let deepSeekSystemPrompt = """
    You are a careful PDF paper reading assistant connected to Skim. The full paper text is supplied as a stable cached context with page markers like [p. N].

    \(paperReadingRules)
    """

    public static func userPrompt(question: String, context: PDFContextPackage) -> String {
        var sections: [String] = []
        sections.append("Document: \(context.documentTitle)")

        if let summary = nonEmpty(context.documentSummary) {
            sections.append("""
            Document summary:
            \(summary)
            """)
        }

        if let selected = nonEmpty(context.selectedText) {
            sections.append("""
            User-selected text:
            \(selected)
            """)
        }

        if let current = nonEmpty(context.currentPageText) {
            sections.append("""
            Current page text:
            \(current)
            """)
        }

        if !context.retrievedChunks.isEmpty {
            let chunks = context.retrievedChunks.map { chunk in
                """
                [p. \(chunk.pageNumber)]
                \(chunk.text)
                """
            }.joined(separator: "\n\n---\n\n")
            sections.append("""
            Retrieved PDF context:
            \(chunks)
            """)
        }

        if context.attachFullPDF {
            sections.append("The complete PDF is attached to this request. Use it when the text snippets are not enough.")
        }

        sections.append("""
        User question:
        \(question)
        """)

        return sections.joined(separator: "\n\n")
    }

    public static func deepSeekDocumentPrompt(context: PDFContextPackage) -> String {
        var sections: [String] = []
        sections.append("Document title: \(context.documentTitle)")

        if let fullText = nonEmpty(context.fullDocumentText) {
            sections.append("""
            Full paper text with page markers:
            \(fullText)
            """)
        } else if let summary = nonEmpty(context.documentSummary) {
            sections.append("""
            Full paper text is unavailable. Use this extractive summary as fallback:
            \(summary)
            """)
        } else {
            sections.append("Full paper text is unavailable. The PDF may be scanned or text extraction may have failed.")
        }

        return sections.joined(separator: "\n\n")
    }

    public static func deepSeekQuestionPrompt(question: String, context: PDFContextPackage) -> String {
        var sections: [String] = []

        if let selected = nonEmpty(context.selectedText) {
            sections.append("""
            Current selected text:
            \(selected)
            """)
        }

        if let current = nonEmpty(context.currentPageText) {
            sections.append("""
            Current page text:
            \(current)
            """)
        }

        if context.fullDocumentText == nil, !context.retrievedChunks.isEmpty {
            let chunks = context.retrievedChunks.map { chunk in
                """
                [p. \(chunk.pageNumber)]
                \(chunk.text)
                """
            }.joined(separator: "\n\n---\n\n")
            sections.append("""
            Retrieved fallback context:
            \(chunks)
            """)
        }

        sections.append("""
        User question:
        \(question)
        """)

        return sections.joined(separator: "\n\n")
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

import Foundation

public enum PDFChunker {
    public static func chunks(for pageText: String, pageNumber: Int, documentID: String, startingOrdinal: Int) -> [PDFChunk] {
        let normalized = pageText
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return [] }

        let paragraphs = normalized
            .components(separatedBy: "\n\n")
            .map { collapseWhitespace($0) }
            .filter { !$0.isEmpty }

        let units = paragraphs.isEmpty ? [collapseWhitespace(normalized)] : paragraphs
        var chunks: [PDFChunk] = []
        var buffer = ""
        var ordinal = startingOrdinal
        let maxCharacters = 1_800
        let overlapCharacters = 180

        func flush() {
            let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            let id = "\(documentID)-\(ordinal)"
            chunks.append(PDFChunk(
                id: id,
                documentID: documentID,
                ordinal: ordinal,
                pageNumber: pageNumber,
                text: text,
                sectionHint: likelyHeading(in: text)
            ))
            ordinal += 1
        }

        for unit in units {
            if unit.count > maxCharacters {
                flush()
                buffer = ""
                var start = unit.startIndex
                while start < unit.endIndex {
                    let end = unit.index(start, offsetBy: maxCharacters, limitedBy: unit.endIndex) ?? unit.endIndex
                    buffer = String(unit[start..<end])
                    flush()
                    guard end < unit.endIndex else { break }
                    start = unit.index(end, offsetBy: -min(overlapCharacters, unit.distance(from: unit.startIndex, to: end)))
                }
                buffer = ""
                continue
            }

            if buffer.count + unit.count + 2 > maxCharacters {
                flush()
                let suffix = String(buffer.suffix(overlapCharacters))
                buffer = suffix.isEmpty ? unit : "\(suffix)\n\n\(unit)"
            } else {
                buffer = buffer.isEmpty ? unit : "\(buffer)\n\n\(unit)"
            }
        }

        flush()
        return chunks
    }

    public static func collapseWhitespace(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func likelyHeading(in text: String) -> String? {
        let lines = text.components(separatedBy: ". ")
        guard let first = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines), !first.isEmpty else {
            return nil
        }
        guard first.count <= 96 else { return nil }
        let digitOrLetter = first.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
        return digitOrLetter ? first : nil
    }
}


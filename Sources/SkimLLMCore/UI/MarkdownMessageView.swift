import Foundation
import SwiftUI

struct MarkdownMessageView: View {
    let text: String

    private var blocks: [MarkdownBlock] {
        MarkdownBlockParser.parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let content):
                    InlineMarkdownText(content)
                        .font(level == 1 ? .headline : .subheadline.weight(.semibold))
                        .padding(.top, level == 1 ? 2 : 0)

                case .paragraph(let content):
                    InlineMarkdownText(content)
                        .font(.body)
                        .lineSpacing(4)

                case .unorderedList(let items):
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 12, alignment: .trailing)
                                    .padding(.top, 1)
                                InlineMarkdownText(item)
                                    .font(.body)
                                    .lineSpacing(4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(.vertical, 2)

                case .orderedList(let items):
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1).")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, alignment: .trailing)
                                    .padding(.top, 1)
                                InlineMarkdownText(item)
                                    .font(.body)
                                    .lineSpacing(4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(.vertical, 2)

                case .quote(let content):
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor.opacity(0.35))
                            .frame(width: 3)
                        InlineMarkdownText(content)
                            .font(.body)
                            .lineSpacing(4)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)

                case .code(let language, let content):
                    VStack(alignment: .leading, spacing: 6) {
                        if let language, !language.isEmpty {
                            Text(language)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                        }
                        ScrollView(.horizontal, showsIndicators: true) {
                            Text(content)
                                .font(.system(.callout, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.75))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.18))
                        )
                    }

                case .table(let headers, let alignments, let rows):
                    MarkdownTableView(headers: headers, alignments: alignments, rows: rows)
                }
            }
        }
    }
}

private struct InlineMarkdownText: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        if let attributed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            Text(attributed)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct MarkdownTableView: View {
    let headers: [String]
    let alignments: [MarkdownTableColumnAlignment]
    let rows: [[String]]

    private let minColumnWidth: CGFloat = 120
    private let maxColumnWidth: CGFloat = 260

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(headers.indices, id: \.self) { index in
                        tableCell(headers[index], column: index, isHeader: true)
                    }
                }

                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(headers.indices, id: \.self) { columnIndex in
                            tableCell(cellText(row: row, column: columnIndex), column: columnIndex, isHeader: false)
                                .background(rowIndex.isMultiple(of: 2) ? Color.clear : Color.secondary.opacity(0.035))
                        }
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.18))
            )
        }
        .padding(.vertical, 2)
    }

    private func tableCell(_ content: String, column: Int, isHeader: Bool) -> some View {
        InlineMarkdownText(content.isEmpty ? " " : content)
            .font(isHeader ? .callout.weight(.semibold) : .callout)
            .lineSpacing(3)
            .frame(minWidth: minColumnWidth, maxWidth: maxColumnWidth, alignment: cellAlignment(for: column))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isHeader ? Color.secondary.opacity(0.08) : Color.clear)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.14))
                    .frame(width: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.secondary.opacity(isHeader ? 0.22 : 0.12))
                    .frame(height: 1)
            }
    }

    private func cellText(row: [String], column: Int) -> String {
        column < row.count ? row[column] : ""
    }

    private func cellAlignment(for column: Int) -> Alignment {
        guard column < alignments.count else {
            return .leading
        }

        switch alignments[column] {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }
}

enum MarkdownBlock: Equatable {
    case heading(level: Int, content: String)
    case paragraph(String)
    case unorderedList([String])
    case orderedList([String])
    case quote(String)
    case code(language: String?, content: String)
    case table(headers: [String], alignments: [MarkdownTableColumnAlignment], rows: [[String]])
}

enum MarkdownTableColumnAlignment: Equatable {
    case leading
    case center
    case trailing
}

enum MarkdownBlockParser {
    static func parse(_ rawText: String) -> [MarkdownBlock] {
        let text = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            return [.paragraph("Thinking...")]
        }

        let lines = text.components(separatedBy: "\n")
        var index = 0
        var blocks: [MarkdownBlock] = []

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                index += 1
                var codeLines: [String] = []
                while index < lines.count {
                    let current = lines[index]
                    if current.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        index += 1
                        break
                    }
                    codeLines.append(current)
                    index += 1
                }
                blocks.append(.code(language: language.isEmpty ? nil : language, content: codeLines.joined(separator: "\n")))
                continue
            }

            if let heading = heading(from: trimmed) {
                blocks.append(.heading(level: heading.level, content: heading.content))
                index += 1
                continue
            }

            if let table = table(lines: lines, start: index) {
                blocks.append(.table(headers: table.headers, alignments: table.alignments, rows: table.rows))
                index = table.nextIndex
                continue
            }

            if unorderedItem(from: trimmed) != nil {
                let result = collectUnorderedList(lines: lines, start: index)
                blocks.append(.unorderedList(result.items))
                index = result.nextIndex
                continue
            }

            if orderedItem(from: trimmed) != nil {
                let result = collectOrderedList(lines: lines, start: index)
                blocks.append(.orderedList(result.items))
                index = result.nextIndex
                continue
            }

            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while index < lines.count {
                    let current = lines[index].trimmingCharacters(in: .whitespaces)
                    guard current.hasPrefix(">") else { break }
                    quoteLines.append(String(current.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(.quote(quoteLines.joined(separator: "\n")))
                continue
            }

            let result = collectParagraph(lines: lines, start: index)
            blocks.append(.paragraph(result.content))
            index = result.nextIndex
        }

        return blocks
    }

    private static func heading(from line: String) -> (level: Int, content: String)? {
        guard line.hasPrefix("#") else { return nil }
        let count = line.prefix { $0 == "#" }.count
        guard (1...3).contains(count) else { return nil }
        let rest = line.dropFirst(count)
        guard rest.first == " " else { return nil }
        let content = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        return content.isEmpty ? nil : (count, content)
    }

    private static func collectUnorderedList(lines: [String], start: Int) -> (items: [String], nextIndex: Int) {
        var index = start
        var items: [String] = []

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard let item = unorderedItem(from: trimmed) else { break }
            var itemLines = [item]
            index += 1

            while index < lines.count {
                let next = lines[index]
                let nextTrimmed = next.trimmingCharacters(in: .whitespaces)
                if nextTrimmed.isEmpty {
                    index += 1
                    if index < lines.count, unorderedItem(from: lines[index].trimmingCharacters(in: .whitespaces)) != nil {
                        break
                    }
                    continue
                }
                if startsNewBlock(nextTrimmed) {
                    break
                }
                if next.hasPrefix(" ") || next.hasPrefix("\t") {
                    itemLines.append(nextTrimmed)
                    index += 1
                    continue
                }
                break
            }

            items.append(itemLines.joined(separator: "\n"))
        }

        return (items, index)
    }

    private static func collectOrderedList(lines: [String], start: Int) -> (items: [String], nextIndex: Int) {
        var index = start
        var items: [String] = []

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard let item = orderedItem(from: trimmed) else { break }
            var itemLines = [item]
            index += 1

            while index < lines.count {
                let next = lines[index]
                let nextTrimmed = next.trimmingCharacters(in: .whitespaces)
                if nextTrimmed.isEmpty {
                    index += 1
                    if index < lines.count, orderedItem(from: lines[index].trimmingCharacters(in: .whitespaces)) != nil {
                        break
                    }
                    continue
                }
                if startsNewBlock(nextTrimmed) {
                    break
                }
                if next.hasPrefix(" ") || next.hasPrefix("\t") {
                    itemLines.append(nextTrimmed)
                    index += 1
                    continue
                }
                break
            }

            items.append(itemLines.joined(separator: "\n"))
        }

        return (items, index)
    }

    private static func collectParagraph(lines: [String], start: Int) -> (content: String, nextIndex: Int) {
        var index = start
        var paragraphLines: [String] = []

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                break
            }
            if let table = table(lines: lines, start: index), !table.headers.isEmpty {
                break
            }
            if !paragraphLines.isEmpty, startsNewBlock(trimmed) {
                break
            }
            paragraphLines.append(trimmed)
            index += 1
        }

        return (paragraphLines.joined(separator: "\n"), index)
    }

    private static func startsNewBlock(_ line: String) -> Bool {
        line.hasPrefix("```")
            || heading(from: line) != nil
            || unorderedItem(from: line) != nil
            || orderedItem(from: line) != nil
            || line.hasPrefix(">")
    }

    private static func unorderedItem(from line: String) -> String? {
        for marker in ["- ", "* ", "• "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func orderedItem(from line: String) -> String? {
        guard let dotIndex = line.firstIndex(of: ".") else { return nil }
        let prefix = line[..<dotIndex]
        guard !prefix.isEmpty, prefix.allSatisfy(\.isNumber) else { return nil }
        let afterDot = line[line.index(after: dotIndex)...]
        guard afterDot.first == " " else { return nil }
        return String(afterDot.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    private static func table(
        lines: [String],
        start: Int
    ) -> (headers: [String], alignments: [MarkdownTableColumnAlignment], rows: [[String]], nextIndex: Int)? {
        guard start + 1 < lines.count else { return nil }

        let headerLine = lines[start].trimmingCharacters(in: .whitespaces)
        let separatorLine = lines[start + 1].trimmingCharacters(in: .whitespaces)
        guard looksLikeTableRow(headerLine), looksLikeTableRow(separatorLine) else {
            return nil
        }

        let headers = splitTableRow(headerLine)
        let separators = splitTableRow(separatorLine)
        guard headers.count > 1, separators.count == headers.count else {
            return nil
        }

        let alignments = separators.map(tableAlignment)
        guard alignments.allSatisfy({ $0 != nil }) else {
            return nil
        }

        var index = start + 2
        var rows: [[String]] = []

        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            guard looksLikeTableRow(line) else {
                break
            }

            var row = splitTableRow(line)
            if row.count < headers.count {
                row.append(contentsOf: Array(repeating: "", count: headers.count - row.count))
            } else if row.count > headers.count {
                row = Array(row.prefix(headers.count))
            }

            rows.append(row)
            index += 1
        }

        return (headers, alignments.compactMap { $0 }, rows, index)
    }

    private static func looksLikeTableRow(_ line: String) -> Bool {
        line.contains("|")
    }

    private static func splitTableRow(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") {
            trimmed.removeFirst()
        }
        if trimmed.hasSuffix("|") {
            trimmed.removeLast()
        }

        var cells: [String] = []
        var current = ""
        var isEscaped = false

        for character in trimmed {
            if isEscaped {
                current.append(character)
                isEscaped = false
                continue
            }

            if character == "\\" {
                isEscaped = true
                current.append(character)
                continue
            }

            if character == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }

        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private static func tableAlignment(from separator: String) -> MarkdownTableColumnAlignment? {
        let marker = separator.trimmingCharacters(in: .whitespaces)
        guard marker.count >= 3 else { return nil }

        let hasLeadingColon = marker.hasPrefix(":")
        let hasTrailingColon = marker.hasSuffix(":")
        let hyphenSlice = marker
            .drop { $0 == ":" }
            .dropLast(hasTrailingColon ? 1 : 0)

        guard !hyphenSlice.isEmpty, hyphenSlice.allSatisfy({ $0 == "-" }) else {
            return nil
        }

        if hasLeadingColon && hasTrailingColon {
            return .center
        }
        if hasTrailingColon {
            return .trailing
        }
        return .leading
    }
}

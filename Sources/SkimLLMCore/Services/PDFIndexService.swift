import CSQLite
import CryptoKit
import Foundation
import PDFKit

public actor PDFIndexService {
    private let database: SQLiteDatabase

    public init(databaseURL: URL = AppPaths.indexDatabaseURL) throws {
        database = try SQLiteDatabase(url: databaseURL)
        try Self.migrate(database)
    }

    public func index(fileURL: URL) throws -> PDFIndexResult {
        guard let pdf = PDFDocument(url: fileURL) else {
            throw PDFIndexError.cannotOpenPDF(fileURL.path)
        }

        let documentID = try Self.documentID(for: fileURL)
        let pageCount = pdf.pageCount

        if try isCurrentDocumentIndexed(documentID: documentID), try hasPageText(documentID: documentID) {
            let count = try chunkCount(documentID: documentID)
            let summary = try summary(documentID: documentID)
            return PDFIndexResult(
                documentID: documentID,
                pageCount: pageCount,
                chunkCount: count,
                hasExtractableText: count > 0,
                summary: summary
            )
        }

        try removeDocuments(atPath: fileURL.path)

        let title = pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
        let fallbackTitle = fileURL.deletingPathExtension().lastPathComponent
        var allChunks: [PDFChunk] = []
        var pageTexts: [(pageNumber: Int, text: String)] = []
        var ordinal = 0

        for index in 0..<pageCount {
            guard let page = pdf.page(at: index) else { continue }
            let text = page.string ?? ""
            let cleanedText = Self.cleanPageText(text)
            pageTexts.append((pageNumber: index + 1, text: cleanedText))
            let pageChunks = PDFChunker.chunks(
                for: cleanedText,
                pageNumber: index + 1,
                documentID: documentID,
                startingOrdinal: ordinal
            )
            ordinal += pageChunks.count
            allChunks.append(contentsOf: pageChunks)
        }

        let summary = Self.makeExtractiveSummary(title: title ?? fallbackTitle, pageCount: pageCount, chunks: allChunks)
        try insertDocument(
            id: documentID,
            filePath: fileURL.path,
            title: title ?? fallbackTitle,
            pageCount: pageCount,
            summary: summary
        )
        try insertPages(documentID: documentID, pageTexts: pageTexts)
        try insertChunks(allChunks)

        return PDFIndexResult(
            documentID: documentID,
            pageCount: pageCount,
            chunkCount: allChunks.count,
            hasExtractableText: !allChunks.isEmpty,
            summary: summary
        )
    }

    public func search(documentID: String, query: String, currentPage: Int?, limit: Int = 8) throws -> [PDFChunk] {
        let match = Self.ftsQuery(from: query)
        if match.isEmpty {
            return try nearbyChunks(documentID: documentID, currentPage: currentPage, limit: limit)
        }

        let statement = try database.prepare("""
            SELECT chunk_id, document_id, ordinal, page_number, text, section_hint
            FROM chunks_fts
            WHERE chunks_fts MATCH ? AND document_id = ?
            ORDER BY bm25(chunks_fts)
            LIMIT ?;
            """)
        defer { sqlite3_finalize(statement) }

        try database.bind(match, at: 1, in: statement)
        try database.bind(documentID, at: 2, in: statement)
        try database.bind(limit, at: 3, in: statement)

        var chunks: [PDFChunk] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            chunks.append(Self.readChunk(from: statement))
        }

        if chunks.isEmpty {
            return try nearbyChunks(documentID: documentID, currentPage: currentPage, limit: limit)
        }
        return chunks
    }

    public func pageText(documentID: String, pageNumber: Int) throws -> String? {
        let statement = try database.prepare("""
            SELECT text
            FROM pages
            WHERE document_id = ? AND page_number = ?
            LIMIT 1;
            """)
        defer { sqlite3_finalize(statement) }

        try database.bind(documentID, at: 1, in: statement)
        try database.bind(pageNumber, at: 2, in: statement)

        guard sqlite3_step(statement) == SQLITE_ROW, let pointer = sqlite3_column_text(statement, 0) else {
            return nil
        }
        let value = String(cString: pointer)
        return value.isEmpty ? nil : value
    }

    public func fullDocumentText(documentID: String, maxCharacters: Int) throws -> String? {
        let statement = try database.prepare("""
            SELECT page_number, text
            FROM pages
            WHERE document_id = ?
            ORDER BY page_number ASC;
            """)
        defer { sqlite3_finalize(statement) }

        try database.bind(documentID, at: 1, in: statement)

        var parts: [String] = []
        var remaining = max(0, maxCharacters)
        var truncated = false

        while sqlite3_step(statement) == SQLITE_ROW {
            let pageNumber = Int(sqlite3_column_int64(statement, 0))
            let text = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            guard !text.isEmpty else { continue }

            let pageBlock = "[p. \(pageNumber)]\n\(text)"
            if pageBlock.count + 2 <= remaining {
                parts.append(pageBlock)
                remaining -= pageBlock.count + 2
            } else if remaining > 120 {
                parts.append(String(pageBlock.prefix(remaining)) + "\n[truncated]")
                truncated = true
                break
            } else {
                truncated = true
                break
            }
        }

        if truncated {
            parts.append("[Document text was truncated before sending to the model.]")
        }

        let value = parts.joined(separator: "\n\n")
        return value.isEmpty ? nil : value
    }

    public func summary(documentID: String) throws -> String? {
        let statement = try database.prepare("SELECT summary FROM documents WHERE id = ? LIMIT 1;")
        defer { sqlite3_finalize(statement) }

        try database.bind(documentID, at: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW, let pointer = sqlite3_column_text(statement, 0) else {
            return nil
        }
        let value = String(cString: pointer)
        return value.isEmpty ? nil : value
    }

    private static func migrate(_ database: SQLiteDatabase) throws {
        try database.execute("""
            CREATE TABLE IF NOT EXISTS documents (
                id TEXT PRIMARY KEY,
                file_path TEXT NOT NULL,
                title TEXT NOT NULL,
                page_count INTEGER NOT NULL,
                indexed_at REAL NOT NULL,
                summary TEXT
            );
            """)
        try database.execute("""
            CREATE TABLE IF NOT EXISTS chunks (
                id TEXT PRIMARY KEY,
                document_id TEXT NOT NULL,
                ordinal INTEGER NOT NULL,
                page_number INTEGER NOT NULL,
                text TEXT NOT NULL,
                section_hint TEXT,
                FOREIGN KEY(document_id) REFERENCES documents(id) ON DELETE CASCADE
            );
            """)
        try database.execute("""
            CREATE TABLE IF NOT EXISTS pages (
                document_id TEXT NOT NULL,
                page_number INTEGER NOT NULL,
                text TEXT NOT NULL,
                PRIMARY KEY(document_id, page_number),
                FOREIGN KEY(document_id) REFERENCES documents(id) ON DELETE CASCADE
            );
            """)
        try database.execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(
                chunk_id UNINDEXED,
                document_id UNINDEXED,
                ordinal UNINDEXED,
                page_number UNINDEXED,
                text,
                section_hint,
                tokenize = 'unicode61'
            );
            """)
    }

    private func isCurrentDocumentIndexed(documentID: String) throws -> Bool {
        let statement = try database.prepare("SELECT 1 FROM documents WHERE id = ? LIMIT 1;")
        defer { sqlite3_finalize(statement) }
        try database.bind(documentID, at: 1, in: statement)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func hasPageText(documentID: String) throws -> Bool {
        let statement = try database.prepare("SELECT 1 FROM pages WHERE document_id = ? LIMIT 1;")
        defer { sqlite3_finalize(statement) }
        try database.bind(documentID, at: 1, in: statement)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func chunkCount(documentID: String) throws -> Int {
        let statement = try database.prepare("SELECT COUNT(*) FROM chunks WHERE document_id = ?;")
        defer { sqlite3_finalize(statement) }
        try database.bind(documentID, at: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func removeDocuments(atPath path: String) throws {
        let select = try database.prepare("SELECT id FROM documents WHERE file_path = ?;")
        defer { sqlite3_finalize(select) }
        try database.bind(path, at: 1, in: select)

        var ids: [String] = []
        while sqlite3_step(select) == SQLITE_ROW {
            ids.append(String(cString: sqlite3_column_text(select, 0)))
        }

        for id in ids {
            do {
                let deleteFTS = try database.prepare("DELETE FROM chunks_fts WHERE document_id = ?;")
                defer { sqlite3_finalize(deleteFTS) }
                try database.bind(id, at: 1, in: deleteFTS)
                try database.stepToDone(deleteFTS)
            }
        }

        let deleteDocuments = try database.prepare("DELETE FROM documents WHERE file_path = ?;")
        defer { sqlite3_finalize(deleteDocuments) }
        try database.bind(path, at: 1, in: deleteDocuments)
        try database.stepToDone(deleteDocuments)
    }

    private func insertDocument(id: String, filePath: String, title: String, pageCount: Int, summary: String?) throws {
        let statement = try database.prepare("""
            INSERT INTO documents (id, file_path, title, page_count, indexed_at, summary)
            VALUES (?, ?, ?, ?, ?, ?);
            """)
        defer { sqlite3_finalize(statement) }

        try database.bind(id, at: 1, in: statement)
        try database.bind(filePath, at: 2, in: statement)
        try database.bind(title, at: 3, in: statement)
        try database.bind(pageCount, at: 4, in: statement)
        try database.bind(Date().timeIntervalSince1970, at: 5, in: statement)
        try database.bind(summary, at: 6, in: statement)
        try database.stepToDone(statement)
    }

    private func insertPages(documentID: String, pageTexts: [(pageNumber: Int, text: String)]) throws {
        let statement = try database.prepare("""
            INSERT INTO pages (document_id, page_number, text)
            VALUES (?, ?, ?);
            """)
        defer { sqlite3_finalize(statement) }

        for pageText in pageTexts {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            try database.bind(documentID, at: 1, in: statement)
            try database.bind(pageText.pageNumber, at: 2, in: statement)
            try database.bind(pageText.text, at: 3, in: statement)
            try database.stepToDone(statement)
        }
    }

    private func insertChunks(_ chunks: [PDFChunk]) throws {
        try database.execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            for chunk in chunks {
                try insertChunk(chunk)
            }
            try database.execute("COMMIT;")
        } catch {
            try? database.execute("ROLLBACK;")
            throw error
        }
    }

    private func insertChunk(_ chunk: PDFChunk) throws {
        let chunkStatement = try database.prepare("""
            INSERT INTO chunks (id, document_id, ordinal, page_number, text, section_hint)
            VALUES (?, ?, ?, ?, ?, ?);
            """)
        defer { sqlite3_finalize(chunkStatement) }
        try database.bind(chunk.id, at: 1, in: chunkStatement)
        try database.bind(chunk.documentID, at: 2, in: chunkStatement)
        try database.bind(chunk.ordinal, at: 3, in: chunkStatement)
        try database.bind(chunk.pageNumber, at: 4, in: chunkStatement)
        try database.bind(chunk.text, at: 5, in: chunkStatement)
        try database.bind(chunk.sectionHint, at: 6, in: chunkStatement)
        try database.stepToDone(chunkStatement)

        let ftsStatement = try database.prepare("""
            INSERT INTO chunks_fts (chunk_id, document_id, ordinal, page_number, text, section_hint)
            VALUES (?, ?, ?, ?, ?, ?);
            """)
        defer { sqlite3_finalize(ftsStatement) }
        try database.bind(chunk.id, at: 1, in: ftsStatement)
        try database.bind(chunk.documentID, at: 2, in: ftsStatement)
        try database.bind(chunk.ordinal, at: 3, in: ftsStatement)
        try database.bind(chunk.pageNumber, at: 4, in: ftsStatement)
        try database.bind(chunk.text, at: 5, in: ftsStatement)
        try database.bind(chunk.sectionHint, at: 6, in: ftsStatement)
        try database.stepToDone(ftsStatement)
    }

    private func nearbyChunks(documentID: String, currentPage: Int?, limit: Int) throws -> [PDFChunk] {
        let page = currentPage ?? 1
        let statement = try database.prepare("""
            SELECT id, document_id, ordinal, page_number, text, section_hint
            FROM chunks
            WHERE document_id = ?
            ORDER BY ABS(page_number - ?), ordinal ASC
            LIMIT ?;
            """)
        defer { sqlite3_finalize(statement) }

        try database.bind(documentID, at: 1, in: statement)
        try database.bind(page, at: 2, in: statement)
        try database.bind(limit, at: 3, in: statement)

        var chunks: [PDFChunk] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            chunks.append(Self.readChunk(from: statement))
        }
        return chunks
    }

    private static func readChunk(from statement: OpaquePointer) -> PDFChunk {
        let id = String(cString: sqlite3_column_text(statement, 0))
        let documentID = String(cString: sqlite3_column_text(statement, 1))
        let ordinal = Int(sqlite3_column_int64(statement, 2))
        let pageNumber = Int(sqlite3_column_int64(statement, 3))
        let text = String(cString: sqlite3_column_text(statement, 4))
        let sectionHint: String?
        if let pointer = sqlite3_column_text(statement, 5) {
            sectionHint = String(cString: pointer)
        } else {
            sectionHint = nil
        }
        return PDFChunk(id: id, documentID: documentID, ordinal: ordinal, pageNumber: pageNumber, text: text, sectionHint: sectionHint)
    }

    private static func documentID(for fileURL: URL) throws -> String {
        let values = try fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modified = values.contentModificationDate?.timeIntervalSince1970 ?? 0
        let size = values.fileSize ?? 0
        let raw = "\(fileURL.path)|\(modified)|\(size)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func ftsQuery(from text: String) -> String {
        let tokens = text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 }
            .prefix(12)

        return tokens.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: " OR ")
    }

    private static func makeExtractiveSummary(title: String, pageCount: Int, chunks: [PDFChunk]) -> String? {
        guard !chunks.isEmpty else { return nil }
        let opening = chunks.prefix(3).map(\.text).joined(separator: "\n\n")
        let headings = chunks
            .compactMap(\.sectionHint)
            .filter { $0.count <= 96 }
            .prefix(10)
            .joined(separator: "; ")
        var parts = ["Title: \(title)", "Pages: \(pageCount)"]
        if !headings.isEmpty {
            parts.append("Likely sections: \(headings)")
        }
        parts.append("Opening excerpt: \(String(opening.prefix(1_600)))")
        return parts.joined(separator: "\n")
    }

    private static func cleanPageText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum PDFIndexError: Error, LocalizedError {
    case cannotOpenPDF(String)

    public var errorDescription: String? {
        switch self {
        case .cannotOpenPDF(let path):
            return "Could not open PDF at \(path)"
        }
    }
}

public enum AppPaths {
    public static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("SkimLLMSidebar", isDirectory: true)
    }

    public static var indexDatabaseURL: URL {
        supportDirectory.appendingPathComponent("index.sqlite")
    }

    public static var apiKeyFileURL: URL {
        supportDirectory.appendingPathComponent("provider-api-key")
    }

    public static var chatDatabaseURL: URL {
        supportDirectory.appendingPathComponent("chat.sqlite")
    }
}

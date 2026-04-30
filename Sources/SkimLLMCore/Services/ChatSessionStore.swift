import CSQLite
import CryptoKit
import Foundation

public final class ChatSessionStore {
    private let database: SQLiteDatabase

    public init(databaseURL: URL = AppPaths.chatDatabaseURL) throws {
        database = try SQLiteDatabase(url: databaseURL)
        try Self.migrate(database)
        try migrateLegacyJSONSessionsIfNeeded()
    }

    public func documentKey(for fileURL: URL) -> String {
        let path = fileURL.standardizedFileURL.path
        let digest = SHA256.hash(data: Data(path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public func listSessions(documentKey: String) throws -> [ChatSessionSummary] {
        let statement = try database.prepare("""
            SELECT
                sessions.id,
                papers.id,
                papers.title,
                papers.file_path,
                sessions.title,
                sessions.message_count,
                sessions.user_message_count,
                sessions.created_at,
                sessions.updated_at,
                sessions.preview
            FROM sessions
            JOIN papers ON papers.id = sessions.paper_id
            WHERE sessions.paper_id = ?
            ORDER BY sessions.updated_at DESC, sessions.created_at DESC;
            """)
        defer { sqlite3_finalize(statement) }

        try database.bind(documentKey, at: 1, in: statement)

        var summaries: [ChatSessionSummary] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let summary = Self.readSessionSummary(from: statement) {
                summaries.append(summary)
            }
        }
        return summaries
    }

    public func loadSession(documentKey: String, id: UUID) throws -> ChatSessionRecord? {
        let summaryStatement = try database.prepare("""
            SELECT
                sessions.id,
                papers.id,
                papers.title,
                papers.file_path,
                sessions.title,
                sessions.message_count,
                sessions.user_message_count,
                sessions.created_at,
                sessions.updated_at,
                sessions.preview
            FROM sessions
            JOIN papers ON papers.id = sessions.paper_id
            WHERE sessions.paper_id = ? AND sessions.id = ?
            LIMIT 1;
            """)
        defer { sqlite3_finalize(summaryStatement) }

        try database.bind(documentKey, at: 1, in: summaryStatement)
        try database.bind(id.uuidString, at: 2, in: summaryStatement)

        guard sqlite3_step(summaryStatement) == SQLITE_ROW,
              let summary = Self.readSessionSummary(from: summaryStatement) else {
            return nil
        }

        return ChatSessionRecord(summary: summary, messages: try loadMessages(sessionID: id))
    }

    @discardableResult
    public func saveSession(
        id: UUID?,
        documentKey: String,
        documentTitle: String,
        documentPath: String,
        messages: [ChatMessage]
    ) throws -> ChatSessionRecord {
        let sessionID = id ?? UUID()
        let existing = try loadSession(documentKey: documentKey, id: sessionID)
        let now = Date()
        let createdAt = existing?.summary.createdAt ?? now
        let visibleMessages = messages.filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let summary = ChatSessionSummary(
            id: sessionID,
            documentKey: documentKey,
            documentTitle: documentTitle,
            documentPath: documentPath,
            title: Self.sessionTitle(from: visibleMessages),
            messageCount: visibleMessages.count,
            userMessageCount: visibleMessages.filter { $0.role == .user }.count,
            createdAt: createdAt,
            updatedAt: now,
            preview: Self.preview(from: visibleMessages)
        )

        try database.execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            try upsertPaper(
                id: documentKey,
                title: documentTitle,
                filePath: documentPath,
                now: now
            )
            try upsertSession(summary)
            try syncMessages(messages, sessionID: sessionID, paperID: documentKey)
            try syncEvidenceReferences(messages: messages, sessionID: sessionID, paperID: documentKey)
            try database.execute("COMMIT;")
        } catch {
            try? database.execute("ROLLBACK;")
            throw error
        }

        return ChatSessionRecord(summary: summary, messages: messages)
    }

    public func deleteSession(documentKey: String, id: UUID) throws {
        try database.execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            try deleteMessageFTS(sessionID: id)
            try deleteResearchMemoryFTS(sessionID: id)

            let statement = try database.prepare("DELETE FROM sessions WHERE paper_id = ? AND id = ?;")
            defer { sqlite3_finalize(statement) }
            try database.bind(documentKey, at: 1, in: statement)
            try database.bind(id.uuidString, at: 2, in: statement)
            try database.stepToDone(statement)

            try database.execute("COMMIT;")
        } catch {
            try? database.execute("ROLLBACK;")
            throw error
        }
    }

    public func searchMessages(documentKey: String, query: String, limit: Int = 20) throws -> [ChatMessageSearchResult] {
        let match = Self.ftsQuery(from: query)
        guard !match.isEmpty else { return [] }

        let statement = try database.prepare("""
            SELECT
                messages.id,
                messages.session_id,
                sessions.title,
                messages.role,
                messages.content,
                messages.created_at
            FROM message_fts
            JOIN messages ON messages.id = message_fts.message_id
            JOIN sessions ON sessions.id = messages.session_id
            WHERE message_fts MATCH ? AND message_fts.paper_id = ?
            ORDER BY bm25(message_fts)
            LIMIT ?;
            """)
        defer { sqlite3_finalize(statement) }

        try database.bind(match, at: 1, in: statement)
        try database.bind(documentKey, at: 2, in: statement)
        try database.bind(limit, at: 3, in: statement)

        var results: [ChatMessageSearchResult] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = UUID(uuidString: Self.stringColumn(statement, 0)),
                  let sessionID = UUID(uuidString: Self.stringColumn(statement, 1)),
                  let role = ChatRole(rawValue: Self.stringColumn(statement, 3)) else {
                continue
            }
            results.append(ChatMessageSearchResult(
                id: id,
                sessionID: sessionID,
                sessionTitle: Self.stringColumn(statement, 2),
                role: role,
                content: Self.stringColumn(statement, 4),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
            ))
        }
        return results
    }

    public func listEvidenceReferences(documentKey: String, limit: Int = 200) throws -> [ChatEvidenceReference] {
        let statement = try database.prepare("""
            SELECT id, paper_id, session_id, message_id, page_number, quote, created_at
            FROM evidence_refs
            WHERE paper_id = ?
            ORDER BY created_at DESC
            LIMIT ?;
            """)
        defer { sqlite3_finalize(statement) }

        try database.bind(documentKey, at: 1, in: statement)
        try database.bind(limit, at: 2, in: statement)

        var references: [ChatEvidenceReference] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = UUID(uuidString: Self.stringColumn(statement, 0)),
                  let sessionID = UUID(uuidString: Self.stringColumn(statement, 2)),
                  let messageID = UUID(uuidString: Self.stringColumn(statement, 3)) else {
                continue
            }
            let quote = sqlite3_column_text(statement, 5).map { String(cString: $0) }
            references.append(ChatEvidenceReference(
                id: id,
                paperID: Self.stringColumn(statement, 1),
                sessionID: sessionID,
                messageID: messageID,
                pageNumber: Int(sqlite3_column_int64(statement, 4)),
                quote: quote,
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))
            ))
        }
        return references
    }

    private static func migrate(_ database: SQLiteDatabase) throws {
        try database.execute("""
            CREATE TABLE IF NOT EXISTS papers (
                id TEXT PRIMARY KEY,
                file_path TEXT NOT NULL,
                file_hash TEXT,
                title TEXT NOT NULL,
                doi TEXT,
                arxiv_id TEXT,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                last_opened_at REAL NOT NULL
            );
            """)
        try database.execute("CREATE INDEX IF NOT EXISTS idx_papers_file_path ON papers(file_path);")

        try database.execute("""
            CREATE TABLE IF NOT EXISTS sessions (
                id TEXT PRIMARY KEY,
                paper_id TEXT NOT NULL,
                title TEXT NOT NULL,
                summary TEXT,
                message_count INTEGER NOT NULL,
                user_message_count INTEGER NOT NULL,
                preview TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                FOREIGN KEY(paper_id) REFERENCES papers(id) ON DELETE CASCADE
            );
            """)
        try database.execute("CREATE INDEX IF NOT EXISTS idx_sessions_paper_updated ON sessions(paper_id, updated_at DESC);")

        try database.execute("""
            CREATE TABLE IF NOT EXISTS messages (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                ordinal INTEGER NOT NULL,
                role TEXT NOT NULL,
                content TEXT NOT NULL,
                reasoning_content TEXT NOT NULL,
                model TEXT,
                provider TEXT,
                interaction_mode TEXT,
                created_at REAL NOT NULL,
                FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
            );
            """)
        try database.execute("CREATE INDEX IF NOT EXISTS idx_messages_session_ordinal ON messages(session_id, ordinal);")
        try database.execute("CREATE INDEX IF NOT EXISTS idx_messages_created_at ON messages(created_at);")

        try database.execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS message_fts USING fts5(
                message_id UNINDEXED,
                paper_id UNINDEXED,
                session_id UNINDEXED,
                role UNINDEXED,
                content,
                reasoning_content,
                tokenize = 'unicode61'
            );
            """)

        try database.execute("""
            CREATE TABLE IF NOT EXISTS turn_contexts (
                id TEXT PRIMARY KEY,
                message_id TEXT NOT NULL,
                session_id TEXT NOT NULL,
                paper_id TEXT NOT NULL,
                current_page INTEGER,
                selected_text TEXT,
                retrieved_chunk_ids TEXT,
                prompt_hash TEXT,
                system_prompt_version TEXT,
                full_document_prefix_hash TEXT,
                created_at REAL NOT NULL,
                FOREIGN KEY(message_id) REFERENCES messages(id) ON DELETE CASCADE,
                FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE,
                FOREIGN KEY(paper_id) REFERENCES papers(id) ON DELETE CASCADE
            );
            """)
        try database.execute("CREATE INDEX IF NOT EXISTS idx_turn_contexts_paper ON turn_contexts(paper_id, created_at DESC);")

        try database.execute("""
            CREATE TABLE IF NOT EXISTS evidence_refs (
                id TEXT PRIMARY KEY,
                message_id TEXT NOT NULL,
                session_id TEXT NOT NULL,
                paper_id TEXT NOT NULL,
                page_number INTEGER NOT NULL,
                section TEXT,
                figure TEXT,
                table_name TEXT,
                equation TEXT,
                quote TEXT,
                chunk_id TEXT,
                confidence REAL,
                created_at REAL NOT NULL,
                FOREIGN KEY(message_id) REFERENCES messages(id) ON DELETE CASCADE,
                FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE,
                FOREIGN KEY(paper_id) REFERENCES papers(id) ON DELETE CASCADE
            );
            """)
        try database.execute("CREATE INDEX IF NOT EXISTS idx_evidence_refs_paper_page ON evidence_refs(paper_id, page_number);")
        try database.execute("CREATE INDEX IF NOT EXISTS idx_evidence_refs_session ON evidence_refs(session_id, created_at DESC);")

        try database.execute("""
            CREATE TABLE IF NOT EXISTS research_memory (
                id TEXT PRIMARY KEY,
                paper_id TEXT NOT NULL,
                session_id TEXT,
                source_message_id TEXT,
                evidence_ref_id TEXT,
                type TEXT NOT NULL,
                status TEXT,
                content TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                FOREIGN KEY(paper_id) REFERENCES papers(id) ON DELETE CASCADE,
                FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE SET NULL,
                FOREIGN KEY(source_message_id) REFERENCES messages(id) ON DELETE SET NULL,
                FOREIGN KEY(evidence_ref_id) REFERENCES evidence_refs(id) ON DELETE SET NULL
            );
            """)
        try database.execute("CREATE INDEX IF NOT EXISTS idx_research_memory_paper_type ON research_memory(paper_id, type);")

        try database.execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS research_memory_fts USING fts5(
                memory_id UNINDEXED,
                paper_id UNINDEXED,
                session_id UNINDEXED,
                type UNINDEXED,
                content,
                tokenize = 'unicode61'
            );
            """)
    }

    private func upsertPaper(id: String, title: String, filePath: String, now: Date) throws {
        let statement = try database.prepare("""
            INSERT INTO papers (id, file_path, title, created_at, updated_at, last_opened_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                file_path = excluded.file_path,
                title = excluded.title,
                updated_at = excluded.updated_at,
                last_opened_at = excluded.last_opened_at;
            """)
        defer { sqlite3_finalize(statement) }

        let timestamp = now.timeIntervalSince1970
        try database.bind(id, at: 1, in: statement)
        try database.bind(filePath, at: 2, in: statement)
        try database.bind(title, at: 3, in: statement)
        try database.bind(timestamp, at: 4, in: statement)
        try database.bind(timestamp, at: 5, in: statement)
        try database.bind(timestamp, at: 6, in: statement)
        try database.stepToDone(statement)
    }

    private func migrateLegacyJSONSessionsIfNeeded() throws {
        let legacyRoot = AppPaths.supportDirectory.appendingPathComponent("chat-sessions", isDirectory: true)
        guard FileManager.default.fileExists(atPath: legacyRoot.path) else { return }

        let decoder = JSONDecoder()
        let documentDirectories = try FileManager.default.contentsOfDirectory(
            at: legacyRoot,
            includingPropertiesForKeys: [.isDirectoryKey]
        )

        for documentDirectory in documentDirectories {
            let values = try? documentDirectory.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }
            let documentKey = documentDirectory.lastPathComponent
            let sessionFiles = (try? FileManager.default.contentsOfDirectory(
                at: documentDirectory,
                includingPropertiesForKeys: nil
            )) ?? []

            for sessionFile in sessionFiles where sessionFile.pathExtension == "json" {
                guard let data = try? Data(contentsOf: sessionFile),
                      var record = try? decoder.decode(ChatSessionRecord.self, from: data),
                      (try loadSession(documentKey: documentKey, id: record.summary.id)) == nil else {
                    continue
                }

                record.summary.documentKey = documentKey
                try importLegacyRecord(record)
            }
        }
    }

    private func importLegacyRecord(_ record: ChatSessionRecord) throws {
        let now = record.summary.updatedAt
        try database.execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            try upsertPaper(
                id: record.summary.documentKey,
                title: record.summary.documentTitle,
                filePath: record.summary.documentPath,
                now: now
            )
            try upsertSession(record.summary)
            try syncMessages(record.messages, sessionID: record.summary.id, paperID: record.summary.documentKey)
            try syncEvidenceReferences(messages: record.messages, sessionID: record.summary.id, paperID: record.summary.documentKey)
            try database.execute("COMMIT;")
        } catch {
            try? database.execute("ROLLBACK;")
            throw error
        }
    }

    private func upsertSession(_ summary: ChatSessionSummary) throws {
        let statement = try database.prepare("""
            INSERT INTO sessions (
                id, paper_id, title, summary, message_count, user_message_count, preview, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                paper_id = excluded.paper_id,
                title = excluded.title,
                message_count = excluded.message_count,
                user_message_count = excluded.user_message_count,
                preview = excluded.preview,
                updated_at = excluded.updated_at;
            """)
        defer { sqlite3_finalize(statement) }

        try database.bind(summary.id.uuidString, at: 1, in: statement)
        try database.bind(summary.documentKey, at: 2, in: statement)
        try database.bind(summary.title, at: 3, in: statement)
        try database.bind(nil as String?, at: 4, in: statement)
        try database.bind(summary.messageCount, at: 5, in: statement)
        try database.bind(summary.userMessageCount, at: 6, in: statement)
        try database.bind(summary.preview, at: 7, in: statement)
        try database.bind(summary.createdAt.timeIntervalSince1970, at: 8, in: statement)
        try database.bind(summary.updatedAt.timeIntervalSince1970, at: 9, in: statement)
        try database.stepToDone(statement)
    }

    private func syncMessages(_ messages: [ChatMessage], sessionID: UUID, paperID: String) throws {
        let existingIDs = try messageIDs(sessionID: sessionID)
        let incomingIDs = Set(messages.map(\.id))
        for staleID in existingIDs.subtracting(incomingIDs) {
            try deleteMessageFTS(messageID: staleID)
            let delete = try database.prepare("DELETE FROM messages WHERE id = ?;")
            defer { sqlite3_finalize(delete) }
            try database.bind(staleID.uuidString, at: 1, in: delete)
            try database.stepToDone(delete)
        }

        for (ordinal, message) in messages.enumerated() {
            try upsertMessage(message, sessionID: sessionID, ordinal: ordinal)
            try refreshMessageFTS(message, sessionID: sessionID, paperID: paperID)
        }
    }

    private func messageIDs(sessionID: UUID) throws -> Set<UUID> {
        let statement = try database.prepare("SELECT id FROM messages WHERE session_id = ?;")
        defer { sqlite3_finalize(statement) }
        try database.bind(sessionID.uuidString, at: 1, in: statement)

        var ids = Set<UUID>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let id = UUID(uuidString: Self.stringColumn(statement, 0)) {
                ids.insert(id)
            }
        }
        return ids
    }

    private func loadMessages(sessionID: UUID) throws -> [ChatMessage] {
        let statement = try database.prepare("""
            SELECT id, role, content, reasoning_content, created_at
            FROM messages
            WHERE session_id = ?
            ORDER BY ordinal ASC;
            """)
        defer { sqlite3_finalize(statement) }

        try database.bind(sessionID.uuidString, at: 1, in: statement)

        var messages: [ChatMessage] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = UUID(uuidString: Self.stringColumn(statement, 0)),
                  let role = ChatRole(rawValue: Self.stringColumn(statement, 1)) else {
                continue
            }
            messages.append(ChatMessage(
                id: id,
                role: role,
                content: Self.stringColumn(statement, 2),
                reasoningContent: Self.stringColumn(statement, 3),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
            ))
        }
        return messages
    }

    private func upsertMessage(_ message: ChatMessage, sessionID: UUID, ordinal: Int) throws {
        let statement = try database.prepare("""
            INSERT INTO messages (
                id, session_id, ordinal, role, content, reasoning_content, model, provider, interaction_mode, created_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                session_id = excluded.session_id,
                ordinal = excluded.ordinal,
                role = excluded.role,
                content = excluded.content,
                reasoning_content = excluded.reasoning_content,
                created_at = excluded.created_at;
            """)
        defer { sqlite3_finalize(statement) }

        try database.bind(message.id.uuidString, at: 1, in: statement)
        try database.bind(sessionID.uuidString, at: 2, in: statement)
        try database.bind(ordinal, at: 3, in: statement)
        try database.bind(message.role.rawValue, at: 4, in: statement)
        try database.bind(message.content, at: 5, in: statement)
        try database.bind(message.reasoningContent, at: 6, in: statement)
        try database.bind(nil as String?, at: 7, in: statement)
        try database.bind(nil as String?, at: 8, in: statement)
        try database.bind(nil as String?, at: 9, in: statement)
        try database.bind(message.createdAt.timeIntervalSince1970, at: 10, in: statement)
        try database.stepToDone(statement)
    }

    private func refreshMessageFTS(_ message: ChatMessage, sessionID: UUID, paperID: String) throws {
        try deleteMessageFTS(messageID: message.id)

        let searchableText = "\(message.content)\n\(message.reasoningContent)"
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !searchableText.isEmpty else { return }

        let statement = try database.prepare("""
            INSERT INTO message_fts (message_id, paper_id, session_id, role, content, reasoning_content)
            VALUES (?, ?, ?, ?, ?, ?);
            """)
        defer { sqlite3_finalize(statement) }

        try database.bind(message.id.uuidString, at: 1, in: statement)
        try database.bind(paperID, at: 2, in: statement)
        try database.bind(sessionID.uuidString, at: 3, in: statement)
        try database.bind(message.role.rawValue, at: 4, in: statement)
        try database.bind(message.content, at: 5, in: statement)
        try database.bind(message.reasoningContent, at: 6, in: statement)
        try database.stepToDone(statement)
    }

    private func syncEvidenceReferences(messages: [ChatMessage], sessionID: UUID, paperID: String) throws {
        let delete = try database.prepare("DELETE FROM evidence_refs WHERE session_id = ?;")
        defer { sqlite3_finalize(delete) }
        try database.bind(sessionID.uuidString, at: 1, in: delete)
        try database.stepToDone(delete)

        var seen = Set<String>()
        for message in messages where message.role == .assistant {
            for evidence in Self.pageEvidence(in: message.content) {
                let key = "\(message.id.uuidString)|\(evidence.pageNumber)|\(evidence.quote ?? "")"
                guard seen.insert(key).inserted else { continue }
                try insertEvidenceReference(
                    messageID: message.id,
                    sessionID: sessionID,
                    paperID: paperID,
                    pageNumber: evidence.pageNumber,
                    quote: evidence.quote,
                    createdAt: message.createdAt
                )
            }
        }
    }

    private func insertEvidenceReference(
        messageID: UUID,
        sessionID: UUID,
        paperID: String,
        pageNumber: Int,
        quote: String?,
        createdAt: Date
    ) throws {
        let statement = try database.prepare("""
            INSERT INTO evidence_refs (
                id, message_id, session_id, paper_id, page_number, section, figure, table_name, equation, quote, chunk_id, confidence, created_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """)
        defer { sqlite3_finalize(statement) }

        try database.bind(UUID().uuidString, at: 1, in: statement)
        try database.bind(messageID.uuidString, at: 2, in: statement)
        try database.bind(sessionID.uuidString, at: 3, in: statement)
        try database.bind(paperID, at: 4, in: statement)
        try database.bind(pageNumber, at: 5, in: statement)
        try database.bind(nil as String?, at: 6, in: statement)
        try database.bind(nil as String?, at: 7, in: statement)
        try database.bind(nil as String?, at: 8, in: statement)
        try database.bind(nil as String?, at: 9, in: statement)
        try database.bind(quote, at: 10, in: statement)
        try database.bind(nil as String?, at: 11, in: statement)
        try database.bind(1.0, at: 12, in: statement)
        try database.bind(createdAt.timeIntervalSince1970, at: 13, in: statement)
        try database.stepToDone(statement)
    }

    private func deleteMessageFTS(sessionID: UUID) throws {
        let statement = try database.prepare("DELETE FROM message_fts WHERE session_id = ?;")
        defer { sqlite3_finalize(statement) }
        try database.bind(sessionID.uuidString, at: 1, in: statement)
        try database.stepToDone(statement)
    }

    private func deleteMessageFTS(messageID: UUID) throws {
        let statement = try database.prepare("DELETE FROM message_fts WHERE message_id = ?;")
        defer { sqlite3_finalize(statement) }
        try database.bind(messageID.uuidString, at: 1, in: statement)
        try database.stepToDone(statement)
    }

    private func deleteResearchMemoryFTS(sessionID: UUID) throws {
        let statement = try database.prepare("DELETE FROM research_memory_fts WHERE session_id = ?;")
        defer { sqlite3_finalize(statement) }
        try database.bind(sessionID.uuidString, at: 1, in: statement)
        try database.stepToDone(statement)
    }

    private static func readSessionSummary(from statement: OpaquePointer) -> ChatSessionSummary? {
        guard let id = UUID(uuidString: stringColumn(statement, 0)) else {
            return nil
        }
        return ChatSessionSummary(
            id: id,
            documentKey: stringColumn(statement, 1),
            documentTitle: stringColumn(statement, 2),
            documentPath: stringColumn(statement, 3),
            title: stringColumn(statement, 4),
            messageCount: Int(sqlite3_column_int64(statement, 5)),
            userMessageCount: Int(sqlite3_column_int64(statement, 6)),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 7)),
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 8)),
            preview: stringColumn(statement, 9)
        )
    }

    private static func pageEvidence(in text: String) -> [(pageNumber: Int, quote: String?)] {
        guard !text.isEmpty,
              let expression = try? NSRegularExpression(
                pattern: #"(?i)\[(?:p|page)\.?\s*(\d+)\]"#,
                options: []
              ) else {
            return []
        }

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return expression.matches(in: text, options: [], range: range).compactMap { match in
            guard match.numberOfRanges >= 2,
                  let pageRange = Range(match.range(at: 1), in: text),
                  let pageNumber = Int(text[pageRange]) else {
                return nil
            }
            let quoteRange = nsText.lineRange(for: match.range)
            let quote = nsText.substring(with: quoteRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (pageNumber, quote.isEmpty ? nil : String(quote.prefix(500)))
        }
    }

    private static func sessionTitle(from messages: [ChatMessage]) -> String {
        let firstUserMessage = messages.first { $0.role == .user }?.content
        let title = cleanSingleLine(firstUserMessage) ?? "New paper chat"
        return String(title.prefix(80))
    }

    private static func preview(from messages: [ChatMessage]) -> String {
        let content = messages.reversed().first { $0.role != .system && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?.content
        return String((cleanSingleLine(content) ?? "No messages yet").prefix(140))
    }

    private static func cleanSingleLine(_ value: String?) -> String? {
        let trimmed = value?
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
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

    private static func stringColumn(_ statement: OpaquePointer, _ index: Int32) -> String {
        sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
    }
}

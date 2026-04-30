import Foundation

public final class LocalSecretStore {
    private let fileURL: URL

    public init(fileURL: URL = AppPaths.apiKeyFileURL) {
        self.fileURL = fileURL
    }

    public func readAPIKey() -> String {
        guard let data = try? Data(contentsOf: fileURL),
              let value = String(data: data, encoding: .utf8) else {
            return ""
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func saveAPIKey(_ apiKey: String) throws {
        FileManager.default.createDirectoryIfNeeded(at: fileURL.deletingLastPathComponent())

        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try deleteAPIKey()
            return
        }

        try Data(trimmed.utf8).write(to: fileURL, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: fileURL.path
        )
    }

    public func deleteAPIKey() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}

import AppKit
import Foundation

public final class SkimBridge {
    public init() {}

    public func frontDocument() -> SkimDocumentState? {
        let separator = "<<<SKIM_LLM_FIELD>>>"
        let script = """
        tell application "System Events"
            if not (exists process "Skim") then return "NOT_RUNNING"
        end tell

        tell application "Skim"
            if (count of documents) is 0 then return "NO_DOCUMENT"
            set theDoc to front document
            set docPath to ""
            try
                set docPath to POSIX path of ((file of theDoc) as alias)
            on error
                try
                    set docPath to path of theDoc
                end try
            end try
            set docTitle to name of theDoc
            set pageTotal to count of pages of theDoc
            set currentPageIndex to 1
            try
                set currentPageIndex to index of current page of theDoc
            on error
                try
                    set currentPageIndex to index of current page of front window
                end try
            end try
            set selectedTextValue to ""
            try
                set selectedTextValue to (obtain text for (selection of theDoc)) as text
            end try
            return docPath & "\(separator)" & docTitle & "\(separator)" & (pageTotal as text) & "\(separator)" & (currentPageIndex as text) & "\(separator)" & selectedTextValue
        end tell
        """

        guard let value = run(script: script), value != "NOT_RUNNING", value != "NO_DOCUMENT" else {
            return nil
        }

        let parts = value.components(separatedBy: separator)
        guard parts.count >= 4, !parts[0].isEmpty, let pageCount = Int(parts[2]) else {
            return nil
        }
        let currentPage = Int(parts[3]) ?? 1
        let selectedText = parts.dropFirst(4).joined(separator: separator)
        return SkimDocumentState(
            fileURL: URL(fileURLWithPath: parts[0]),
            title: parts[1],
            pageCount: pageCount,
            currentPage: max(currentPage, 1),
            selectedText: selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    public func windowFrame() -> CGRect? {
        let separator = "<<<SKIM_LLM_FIELD>>>"
        let script = """
        tell application "System Events"
            if not (exists process "Skim") then return ""
            tell process "Skim"
                if (count of windows) is 0 then return ""
                set windowPosition to position of window 1
                set windowSize to size of window 1
                return (item 1 of windowPosition as text) & "\(separator)" & (item 2 of windowPosition as text) & "\(separator)" & (item 1 of windowSize as text) & "\(separator)" & (item 2 of windowSize as text)
            end tell
        end tell
        """

        guard let value = run(script: script), !value.isEmpty else { return nil }
        let numbers = value.components(separatedBy: separator).compactMap(Double.init)
        guard numbers.count == 4 else { return nil }

        let x = numbers[0]
        let topY = numbers[1]
        let width = numbers[2]
        let height = numbers[3]
        let screenHeight = NSScreen.main?.frame.height ?? 0
        let appKitY = screenHeight > 0 ? screenHeight - topY - height : topY
        return CGRect(x: x, y: appKitY, width: width, height: height)
    }

    private func run(script source: String) -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let descriptor = script.executeAndReturnError(&error)
        if error != nil {
            return nil
        }
        return descriptor.stringValue
    }
}

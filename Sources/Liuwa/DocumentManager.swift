import Foundation
import AppKit

/// Manages static documents loaded from user-configured directory.
@MainActor
final class DocumentManager {
    private weak var overlay: OverlayController?
    private var documents: [(name: String, content: String)] = []
    private var currentIndex: Int = 0

    init(overlay: OverlayController) {
        self.overlay = overlay
        reload()
    }

    func showDocuments() {
        if documents.isEmpty {
            let dir = AppSettings.shared.docsDirectory
            overlay?.appendText("\nDocs directory empty: \(dir)\nPlace .txt/.md/.py/etc files there, then ⌘⌥D again.\n", to: .aiResponse)
        } else {
            showCurrentDocument()
        }
    }

    func nextDocument() {
        guard !documents.isEmpty else { return }
        currentIndex = (currentIndex + 1) % documents.count
        showCurrentDocument()
    }

    func previousDocument() {
        guard !documents.isEmpty else { return }
        currentIndex = (currentIndex - 1 + documents.count) % documents.count
        showCurrentDocument()
    }

    func reload() {
        let dir = AppSettings.shared.docsDirectory
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir) { try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true) }

        documents = []
        guard let files = try? fm.contentsOfDirectory(atPath: dir) else { return }

        let exts = Set(["txt","md","json","swift","py","js","ts","html","css","yaml","yml","toml","xml","csv","log","sh","c","cpp","h","java","go","rs","rb"])

        for file in files.sorted() {
            let ext = (file as NSString).pathExtension.lowercased()
            guard exts.contains(ext) else { continue }
            let path = (dir as NSString).appendingPathComponent(file)
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            let truncated = content.count > 50_000
                ? String(content.prefix(50_000)) + "\n\n… (truncated)"
                : content
            documents.append((name: file, content: truncated))
        }
        print("Loaded \(documents.count) docs from \(dir)")
    }

    func getAllDocumentsText() -> String {
        documents.map { "=== \($0.name) ===\n\($0.content)" }.joined(separator: "\n\n")
    }

    private func showCurrentDocument() {
        guard !documents.isEmpty else { return }
        let doc = documents[currentIndex]
        let preview = String(doc.content.prefix(500))
        overlay?.appendText("\n📄 [\(currentIndex+1)/\(documents.count)] \(doc.name)\n\(preview)\n…\n", to: .aiResponse)
    }
}

import Foundation
import AppKit

/// Manages static documents loaded from user-configured directory.
@MainActor
final class DocumentManager {
    private weak var overlay: OverlayController?
    private var documents: [(name: String, content: String)] = []
    private(set) var currentIndex: Int = 0
    private(set) var isShowingDocs: Bool = false

    init(overlay: OverlayController) {
        self.overlay = overlay
        reload()
    }

    func showDocuments() {
        if documents.isEmpty {
            let dir = AppSettings.shared.docsDirectory
            overlay?.appendText("\nDocs directory empty: \(dir)\nPlace .txt/.md/.py/etc files there, then press docs hotkey again.\n", to: .aiResponse)
        } else {
            isShowingDocs = true
            showCurrentDocument()
        }
    }

    func nextDocument() {
        guard !documents.isEmpty else { return }
        currentIndex = (currentIndex + 1) % documents.count
        isShowingDocs = true
        showCurrentDocument()
    }

    func previousDocument() {
        guard !documents.isEmpty else { return }
        currentIndex = (currentIndex - 1 + documents.count) % documents.count
        isShowingDocs = true
        showCurrentDocument()
    }

    func hideDocs() { isShowingDocs = false }

    func reload() {
        let dir = AppSettings.shared.docsDirectory
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir) { try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true) }

        documents = []
        guard let files = try? fm.contentsOfDirectory(atPath: dir) else { return }

        let exts = Set(["txt","md","json","swift","py","js","ts","html","css","yaml","yml","toml","xml","csv","log","sh","c","cpp","h","java","go","rs","rb","pdf"])

        for file in files.sorted() {
            let ext = (file as NSString).pathExtension.lowercased()
            guard exts.contains(ext) else { continue }
            let path = (dir as NSString).appendingPathComponent(file)
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            // Allow very long files; only truncate beyond 10k characters
            let truncated = content.count > 10_000
                ? String(content.prefix(10_000)) + "\n\n… (truncated at 10k chars)"
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
        let header = "📄 [\(currentIndex+1)/\(documents.count)] \(doc.name)  ◀ prev | next ▶\n"
        overlay?.setText(header + doc.content, for: .aiResponse)
    }

    /// The number of loaded documents.
    var count: Int { documents.count }
}

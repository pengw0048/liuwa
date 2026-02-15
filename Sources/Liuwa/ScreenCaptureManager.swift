import AppKit
import Vision
import ScreenCaptureKit

@MainActor
final class ScreenCaptureManager {
    private weak var overlay: OverlayController?
    private(set) var lastCapturedText: String = ""
    private(set) var lastCapturedImage: CGImage?

    init(overlay: OverlayController) { self.overlay = overlay }

    /// Capture based on current settings (text and/or screenshot)
    func capture() async {
        let s = AppSettings.shared
        if s.sendScreenText { lastCapturedText = getAccessibilityText() ?? "" }
        else { lastCapturedText = "" }

        if s.sendScreenshot {
            if let img = try? await captureScreenshot() {
                lastCapturedImage = img
                // Also OCR for text-only models
                if lastCapturedText.isEmpty, let ocr = try? await performOCR(on: img) {
                    lastCapturedText = ocr
                }
            }
        } else { lastCapturedImage = nil }

        let parts = [s.sendScreenText ? "\(lastCapturedText.count)ch text" : nil,
                     s.sendScreenshot ? "screenshot" : nil].compactMap { $0 }
        if !parts.isEmpty { print("Screen: \(parts.joined(separator: " + "))") }
    }

    // MARK: - AX

    private func getAccessibilityText() -> String? {
        let sys = AXUIElementCreateSystemWide()
        var app: AnyObject?
        guard AXUIElementCopyAttributeValue(sys, kAXFocusedApplicationAttribute as CFString, &app) == .success else { return nil }
        var win: AnyObject?
        guard AXUIElementCopyAttributeValue(app as! AXUIElement, kAXFocusedWindowAttribute as CFString, &win) == .success else { return nil }
        var texts: [String] = []
        collectText(from: win as! AXUIElement, into: &texts, depth: 0, maxDepth: 30)
        var seen = Set<String>()
        return texts.filter { let t = $0.trimmingCharacters(in: .whitespacesAndNewlines); guard !t.isEmpty, t.count > 1, !seen.contains(t) else { return false }; seen.insert(t); return true }.joined(separator: "\n")
    }

    private func collectText(from el: AXUIElement, into texts: inout [String], depth: Int, maxDepth: Int) {
        guard depth < maxDepth else { return }
        var v: AnyObject?
        if AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &v) == .success,
           let t = v as? String, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { texts.append(t) }
        var r: AnyObject?; AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &r)
        let role = r as? String ?? ""
        if role != "AXStaticText" && role != "AXTextField" && role != "AXTextArea" {
            var t: AnyObject?
            if AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &t) == .success,
               let s = t as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { texts.append(s) }
        }
        var d: AnyObject?
        if AXUIElementCopyAttributeValue(el, kAXDescriptionAttribute as CFString, &d) == .success,
           let s = d as? String, s.count > 3 { texts.append(s) }
        var c: AnyObject?
        if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &c) == .success,
           let ch = c as? [AXUIElement] { for child in ch { collectText(from: child, into: &texts, depth: depth+1, maxDepth: maxDepth) } }
    }

    // MARK: - Screenshot

    private func captureScreenshot() async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let app = NSWorkspace.shared.frontmostApplication else { throw CaptureError.noWindow }
        guard let win = content.windows.first(where: { $0.owningApplication?.processID == app.processIdentifier && $0.isOnScreen }) else { throw CaptureError.noWindow }
        let filter = SCContentFilter(desktopIndependentWindow: win)
        let cfg = SCStreamConfiguration(); cfg.width = Int(win.frame.width) * 2; cfg.height = Int(win.frame.height) * 2
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
    }

    private func performOCR(on image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            let req = VNRecognizeTextRequest { req, err in
                if let err { cont.resume(throwing: err); return }
                let text = (req.results as? [VNRecognizedTextObservation])?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n") ?? ""
                cont.resume(returning: text)
            }
            req.recognitionLevel = .accurate; req.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]; req.usesLanguageCorrection = true
            do { try VNImageRequestHandler(cgImage: image, options: [:]).perform([req]) }
            catch { cont.resume(throwing: error) }
        }
    }
}

enum CaptureError: Error, LocalizedError {
    case noWindow, ocrFailed
    var errorDescription: String? { switch self { case .noWindow: "No foreground window"; case .ocrFailed: "OCR failed" } }
}

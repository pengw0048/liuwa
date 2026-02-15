import AppKit

enum PanelType: String, CaseIterable {
    case transcription, documents, aiResponse
}

// MARK: - Section

@MainActor
private final class SectionView {
    let container: NSView
    let hintLabel: NSTextField
    let hint2Label: NSTextField?  // optional second line
    let scrollView: NSScrollView
    let textView: NSTextView
    private let hasSecondHint: Bool

    init(hints: String, hints2: String? = nil, frame: NSRect, font: NSFont) {
        hasSecondHint = hints2 != nil
        container = NSView(frame: frame)

        let hdrH: CGFloat = hasSecondHint ? 26 : 14
        let sep = NSView(frame: NSRect(x: 0, y: frame.height - 2, width: frame.width, height: 2))
        sep.wantsLayer = true; sep.layer?.backgroundColor = NSColor(white: 1, alpha: 0.35).cgColor
        container.addSubview(sep)

        hintLabel = NSTextField(labelWithString: hints)
        hintLabel.font = .monospacedSystemFont(ofSize: 9, weight: .medium)
        hintLabel.textColor = NSColor(white: 1, alpha: 0.55)
        hintLabel.frame = NSRect(x: 4, y: frame.height - 13, width: frame.width - 8, height: 12)
        hintLabel.isEditable = false; hintLabel.isBezeled = false; hintLabel.drawsBackground = false
        container.addSubview(hintLabel)

        if let hints2 {
            let h2 = NSTextField(labelWithString: hints2)
            h2.font = .monospacedSystemFont(ofSize: 9, weight: .medium)
            h2.textColor = NSColor(white: 1, alpha: 0.55)
            h2.frame = NSRect(x: 4, y: frame.height - 25, width: frame.width - 8, height: 12)
            h2.isEditable = false; h2.isBezeled = false; h2.drawsBackground = false
            container.addSubview(h2)
            hint2Label = h2
        } else {
            hint2Label = nil
        }

        let sf = NSRect(x: 2, y: 0, width: frame.width - 4, height: frame.height - hdrH - 2)
        scrollView = NSScrollView(frame: sf)
        scrollView.hasVerticalScroller = true; scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true; scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay; scrollView.scrollerKnobStyle = .light

        let sz = scrollView.contentSize
        textView = NSTextView(frame: NSRect(x: 0, y: 0, width: sz.width, height: sz.height))
        textView.isEditable = false; textView.isSelectable = false; textView.drawsBackground = false
        textView.textColor = .white
        textView.font = font
        textView.textContainerInset = NSSize(width: 4, height: 2)
        textView.isVerticallyResizable = true; textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true; textView.autoresizingMask = [.width]
        scrollView.documentView = textView
        container.addSubview(scrollView)
    }

    /// Resize the section to a new frame without recreating subviews
    func resize(to f: NSRect) {
        container.frame = f
        let hdrH: CGFloat = hasSecondHint ? 26 : 14
        // Separator
        if let sep = container.subviews.first {
            sep.frame = NSRect(x: 0, y: f.height - 1, width: f.width, height: 1)
        }
        hintLabel.frame = NSRect(x: 4, y: f.height - 13, width: f.width - 8, height: 12)
        hint2Label?.frame = NSRect(x: 4, y: f.height - 25, width: f.width - 8, height: 12)
        scrollView.frame = NSRect(x: 2, y: 0, width: f.width - 4, height: f.height - hdrH - 2)
    }

    func setText(_ t: String) { textView.string = t; textView.scrollToEndOfDocument(nil) }
    func setTextScrollTop(_ t: String) {
        textView.string = t
        scrollView.contentView.scroll(to: NSPoint.zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
    func pageUp() {
        let v = scrollView.contentView.bounds
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: max(v.origin.y - v.height * 0.8, 0)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
    func pageDown() {
        let v = scrollView.contentView.bounds; let dh = textView.frame.height
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: min(v.origin.y + v.height * 0.8, max(dh - v.height, 0))))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}

// MARK: - Draggable Container (handles section divider drag)

@MainActor
private final class DraggableContainer: NSView {
    /// Y positions of section boundaries (in this view's coordinate space)
    var handlePositions: [CGFloat] = []
    /// Called with (handleIndex, deltaY in points)
    var onDrag: ((Int, CGFloat) -> Void)?
    var onDragEnd: (() -> Void)?

    private var activeHandle: Int = -1
    private var lastY: CGFloat = 0

    override func mouseDown(with event: NSEvent) {
        let y = convert(event.locationInWindow, from: nil).y
        for (i, hy) in handlePositions.enumerated() {
            if abs(y - hy) < 5 {
                activeHandle = i
                lastY = y
                return  // consume event — prevent window drag
            }
        }
        activeHandle = -1
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard activeHandle >= 0 else { super.mouseDragged(with: event); return }
        let y = convert(event.locationInWindow, from: nil).y
        let delta = y - lastY
        lastY = y
        onDrag?(activeHandle, delta)
    }

    override func mouseUp(with event: NSEvent) {
        if activeHandle >= 0 {
            activeHandle = -1
            onDragEnd?()
        }
        super.mouseUp(with: event)
    }

    override func resetCursorRects() {
        for hy in handlePositions {
            addCursorRect(NSRect(x: 0, y: hy - 4, width: bounds.width, height: 8), cursor: .resizeUpDown)
        }
    }
}

// MARK: - Draggable Top Bar (window drag from top line only)

@MainActor
private final class WindowDragBar: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

// MARK: - Controller

@MainActor
final class OverlayController: @unchecked Sendable {
    let window: GhostWindow
    private var sections: [PanelType: SectionView] = [:]
    private var panelContents: [PanelType: String] = [.transcription: "", .aiResponse: "", .documents: ""]
    private var isCollapsed = false
    private var contentContainer: DraggableContainer!
    private var topBar: WindowDragBar!
    private var topLine: NSTextField!
    private var root: NSView!

    private var panelW: CGFloat, panelH: CGFloat
    private var micActive = false, sysActive = false

    // Separate transcript buffers for WYSIWYG context
    private var micTranscript: String = ""
    private var sysTranscript: String = ""

    private let collapsedH: CGFloat = 16
    private let minRatio: CGFloat = 0.05

    init() {
        let s = AppSettings.shared
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let sw = screen.frame.width, sh = screen.frame.height
        panelW = s.width
        panelH = min(sh * s.heightRatio, sh - 60)

        let frame = NSRect(x: sw - panelW - s.marginRight, y: (sh - panelH) / 2, width: panelW, height: panelH)
        window = GhostWindow(contentRect: frame)
        window.setBaseAlpha(s.transparency)

        root = NSView(frame: NSRect(x: 0, y: 0, width: panelW, height: panelH))
        root.wantsLayer = true
        root.layer?.cornerRadius = s.cornerRadius; root.layer?.masksToBounds = true
        root.layer?.backgroundColor = s.bgColor.cgColor
        root.layer?.borderWidth = 0.5; root.layer?.borderColor = NSColor(white: 1, alpha: 0.1).cgColor

        let tlH: CGFloat = 16
        topBar = WindowDragBar(frame: NSRect(x: 0, y: panelH - tlH, width: panelW, height: tlH))
        topLine = NSTextField(labelWithString: buildTopLine())
        topLine.font = .monospacedSystemFont(ofSize: 8, weight: .medium)
        topLine.textColor = NSColor(white: 1, alpha: 0.5)
        topLine.frame = NSRect(x: 4, y: 1, width: panelW - 8, height: 12)
        topLine.isEditable = false; topLine.isBezeled = false; topLine.drawsBackground = false
        topLine.alignment = .center
        topBar.addSubview(topLine)
        root.addSubview(topBar)

        let cH = panelH - tlH - 2
        contentContainer = DraggableContainer(frame: NSRect(x: 3, y: 2, width: panelW - 6, height: cH))
        contentContainer.onDrag = { [weak self] handle, delta in self?.handleDividerDrag(handle: handle, delta: delta) }
        contentContainer.onDragEnd = { AppSettings.shared.save() }
        root.addSubview(contentContainer)

        buildSections()
        window.contentView = root
        window.alphaValue = s.transparency
        window.orderFrontRegardless()
    }

    // ── Divider drag logic ──
    // macOS Y increases upward; drag up (positive delta) → divider moves up
    private func handleDividerDrag(handle: Int, delta: CGFloat) {
        let s = AppSettings.shared
        let h = contentContainer.frame.height
        let usable = h - 4  // 2 gaps * 2px
        let ratioDelta = delta / usable

        if handle == 0 {
            // Between transcription (top) and documents (middle)
            // Drag up → trans shrinks, docs grows
            var newTrans = s.transcriptionRatio - ratioDelta
            var newDoc = s.docRatio + ratioDelta
            newTrans = max(minRatio, newTrans)
            newDoc = max(minRatio, newDoc)
            if 1.0 - newTrans - newDoc < minRatio { return }
            s.transcriptionRatio = newTrans
            s.docRatio = newDoc
        } else if handle == 1 {
            // Between documents (middle) and AI (bottom)
            // Drag up → docs shrinks, AI grows
            var newDoc = s.docRatio - ratioDelta
            newDoc = max(minRatio, newDoc)
            if 1.0 - s.transcriptionRatio - newDoc < minRatio { return }
            s.docRatio = newDoc
        }

        relayoutSections()
    }

    private func relayoutSections() {
        let s = AppSettings.shared
        let w = contentContainer.frame.width, h = contentContainer.frame.height
        let gap: CGFloat = 2
        let usable = h - gap * 2
        let transH = usable * s.transcriptionRatio
        let docH = usable * s.docRatio
        let aiH = usable * (1.0 - s.transcriptionRatio - s.docRatio)

        sections[.transcription]?.resize(to: NSRect(x: 0, y: h - transH, width: w, height: transH))
        sections[.documents]?.resize(to: NSRect(x: 0, y: h - transH - gap - docH, width: w, height: docH))
        sections[.aiResponse]?.resize(to: NSRect(x: 0, y: 0, width: w, height: aiH))

        // Update drag handle positions
        contentContainer.handlePositions = [
            h - transH - gap / 2,    // between trans and docs
            aiH + gap / 2,           // between docs and AI
        ]
        contentContainer.window?.invalidateCursorRects(for: contentContainer)
    }

    // ── Top line: global toggles with descriptions ──
    private func buildTopLine() -> String {
        let s = AppSettings.shared
        let ghost = window.ghostModeOn ? "👻" : "👁"
        let click = window.clickThroughOn ? "🔒" : "🖱"
        return "\(ghost)\(s.keyFor("toggleGhost")) ghost  \(click)\(s.keyFor("toggleClickThrough")) click  👁‍🗨\(s.keyFor("toggleOverlay")) hide  🔧\(s.keyFor("openSettings")) cfg  ❌\(s.keyFor("quit")) quit"
    }

    private func buildCollapsedLine() -> String {
        let s = AppSettings.shared
        return "⌘⌥\(s.keyFor("toggleOverlay")) expand  |  Liuwa"
    }

    // ── Transcription hints ──
    private func buildTranscriptionHints() -> String {
        let s = AppSettings.shared
        let mic = micActive ? "🟢" : "⚫"
        let sys = sysActive ? "🟢" : "⚫"
        return "\(mic)🎤\(s.keyFor("toggleTranscription")) mic  \(sys)🔊\(s.keyFor("toggleSystemAudio")) sys  🗑\(s.keyFor("clearTranscription")) clear"
    }

    // ── Doc hints ──
    private func buildDocHints() -> String {
        let s = AppSettings.shared
        let attach = s.attachDocToContext ? "🟢" : "⚫"
        return "📂\(s.keyFor("showDocs")) open  ←→ nav  \(attach)📎\(s.keyFor("toggleAttachDoc")) ctx"
    }

    // ── AI hints: line 1 = presets, line 2 = tools ──
    private func buildAIHintsLine1() -> String {
        let s = AppSettings.shared
        return s.presets.enumerated().map { "\($0.offset+1):\($0.element.label)" }.joined(separator: " ")
    }

    private func buildAIHintsLine2() -> String {
        let s = AppSettings.shared
        let txt = s.sendScreenText ? "🟢" : "⚫"
        let img = s.sendScreenshot ? "🟢" : "⚫"
        return "\(txt)📝\(s.keyFor("cycleScreenText")) text  \(img)📷\(s.keyFor("cycleScreenshot")) img  🧹\(s.keyFor("clearAI")) clear  ↑↓ scroll"
    }

    func refreshStatus() {
        if isCollapsed {
            topLine.stringValue = buildCollapsedLine()
        } else {
            topLine.stringValue = buildTopLine()
        }
        sections[.transcription]?.hintLabel.stringValue = buildTranscriptionHints()
        sections[.documents]?.hintLabel.stringValue = buildDocHints()
        sections[.aiResponse]?.hintLabel.stringValue = buildAIHintsLine1()
        sections[.aiResponse]?.hint2Label?.stringValue = buildAIHintsLine2()
    }

    private func buildSections() {
        contentContainer.subviews.forEach { $0.removeFromSuperview() }
        sections.removeAll()
        let s = AppSettings.shared
        let w = contentContainer.frame.width, h = contentContainer.frame.height
        let gap: CGFloat = 2
        let usable = h - gap * 2
        let transH = usable * s.transcriptionRatio
        let docH = usable * s.docRatio
        let aiH = usable * (1.0 - s.transcriptionRatio - s.docRatio)

        // Top: transcription
        let ts = SectionView(hints: buildTranscriptionHints(), frame: NSRect(x: 0, y: h - transH, width: w, height: transH), font: s.font)
        sections[.transcription] = ts; contentContainer.addSubview(ts.container)

        // Middle: documents
        let ds = SectionView(hints: buildDocHints(), frame: NSRect(x: 0, y: h - transH - gap - docH, width: w, height: docH), font: s.font)
        sections[.documents] = ds; contentContainer.addSubview(ds.container)

        // Bottom: AI response
        let ai = SectionView(hints: buildAIHintsLine1(), hints2: buildAIHintsLine2(), frame: NSRect(x: 0, y: 0, width: w, height: aiH), font: s.font)
        sections[.aiResponse] = ai; contentContainer.addSubview(ai.container)

        // Set drag handle positions
        contentContainer.handlePositions = [
            h - transH - gap / 2,
            aiH + gap / 2,
        ]

        for (p, sec) in sections {
            if p == .documents {
                sec.setTextScrollTop(panelContents[p] ?? "")
            } else {
                sec.setText(panelContents[p] ?? "")
            }
        }
    }

    // MARK: Public

    func toggleVisibility() {
        let s = AppSettings.shared
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let sw = screen.frame.width, sh = screen.frame.height

        if isCollapsed {
            panelW = s.width
            panelH = min(sh * s.heightRatio, sh - 60)
            let frame = NSRect(x: sw - panelW - s.marginRight, y: (sh - panelH) / 2, width: panelW, height: panelH)
            window.setFrame(frame, display: false)

            root.frame = NSRect(x: 0, y: 0, width: panelW, height: panelH)
            root.layer?.cornerRadius = s.cornerRadius

            let tlH: CGFloat = 16
            topBar.frame = NSRect(x: 0, y: panelH - tlH, width: panelW, height: tlH)
            topLine.frame = NSRect(x: 4, y: 1, width: panelW - 8, height: 12)
            contentContainer.frame = NSRect(x: 3, y: 2, width: panelW - 6, height: panelH - tlH - 2)
            contentContainer.isHidden = false
            topBar.isHidden = false
            buildSections()

            isCollapsed = false
            refreshStatus()
        } else {
            let barW: CGFloat = 160
            let frame = NSRect(x: sw - barW - s.marginRight, y: sh - collapsedH - 40, width: barW, height: collapsedH)
            window.setFrame(frame, display: false)

            root.frame = NSRect(x: 0, y: 0, width: barW, height: collapsedH)
            root.layer?.cornerRadius = 4

            topBar.frame = NSRect(x: 0, y: 0, width: barW, height: collapsedH)
            topLine.frame = NSRect(x: 4, y: 1, width: barW - 8, height: collapsedH - 2)
            contentContainer.isHidden = true

            isCollapsed = true
            refreshStatus()
        }
    }

    func toggleGhostMode() { window.toggleGhostMode(); refreshStatus() }
    func toggleClickThrough() { window.toggleClickThrough(); refreshStatus() }

    func showPanel(_ p: PanelType, withText t: String? = nil) {
        if let t { panelContents[p] = t }; sections[p]?.setText(panelContents[p] ?? "")
    }
    func appendText(_ t: String, to p: PanelType) {
        panelContents[p] = (panelContents[p] ?? "") + t; sections[p]?.setText(panelContents[p] ?? "")
    }
    func setText(_ t: String, for p: PanelType) {
        panelContents[p] = t
        if p == .documents {
            sections[p]?.setTextScrollTop(t)
        } else {
            sections[p]?.setText(t)
        }
    }
    func getPanelContent(_ p: PanelType) -> String? { panelContents[p] }
    func switchToPanel(_ p: PanelType) { showPanel(p) }
    func cyclePanel() {}

    func setMicActive(_ a: Bool) { micActive = a; refreshStatus() }
    func setSysAudioActive(_ a: Bool) { sysActive = a; refreshStatus() }

    func setMicTranscript(_ text: String) {
        micTranscript = text; rebuildTranscriptPanel()
    }
    func setSysTranscript(_ text: String) {
        sysTranscript = text; rebuildTranscriptPanel()
    }
    func clearTranscripts() {
        micTranscript = ""; sysTranscript = ""; rebuildTranscriptPanel()
    }
    private func rebuildTranscriptPanel() {
        var combined = ""
        if !micTranscript.isEmpty { combined += micTranscript }
        if !sysTranscript.isEmpty {
            if !combined.isEmpty { combined += "\n---\n" }
            combined += sysTranscript
        }
        panelContents[.transcription] = combined
        sections[.transcription]?.setText(combined)
    }

    func scrollAIUp() { sections[.aiResponse]?.pageUp() }
    func scrollAIDown() { sections[.aiResponse]?.pageDown() }

    func refreshPresetLabels() { refreshStatus() }

    /// Full rebuild: resize window, rebuild sections, refresh everything
    func applySettings() {
        let s = AppSettings.shared
        guard !isCollapsed else {
            window.setBaseAlpha(s.transparency); window.alphaValue = s.transparency
            return
        }

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let sw = screen.frame.width, sh = screen.frame.height
        panelW = s.width
        panelH = min(sh * s.heightRatio, sh - 60)

        let frame = NSRect(x: sw - panelW - s.marginRight, y: (sh - panelH) / 2, width: panelW, height: panelH)
        window.setFrame(frame, display: false)
        window.setBaseAlpha(s.transparency); window.alphaValue = s.transparency

        root.frame = NSRect(x: 0, y: 0, width: panelW, height: panelH)
        root.layer?.backgroundColor = s.bgColor.cgColor

        let tlH: CGFloat = 16
        topBar.frame = NSRect(x: 0, y: panelH - tlH, width: panelW, height: tlH)
        topLine.frame = NSRect(x: 4, y: 1, width: panelW - 8, height: 12)
        contentContainer.frame = NSRect(x: 3, y: 2, width: panelW - 6, height: panelH - tlH - 2)
        buildSections()
        refreshStatus()
    }

    /// Live preview during slider drag — does full visual update
    func livePreview() {
        applySettings()
    }
}

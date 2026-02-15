@preconcurrency import AVFoundation
import Speech

@MainActor
final class TranscriptionManager {
    private weak var overlay: OverlayController?
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var analyzerFormat: AVAudioFormat?
    private var audioHelper: AudioCaptureHelper?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var recognizerTask: Task<Void, Never>?
    private var finalizedTranscript = ""
    private var volatileTranscript = ""
    private(set) var isRunning = false

    init(overlay: OverlayController) { self.overlay = overlay }

    func toggle() {
        if isRunning { stop() } else { Task { await start() } }
    }

    func start() async {
        guard !isRunning else { return }
        isRunning = true
        finalizedTranscript = ""; volatileTranscript = ""
        overlay?.setMicActive(true)
        do {
            try await setupAndRun()
        } catch {
            overlay?.setMicActive(false)
            isRunning = false
            overlay?.setMicTranscript("⚠️ Mic error: \(error.localizedDescription)")
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        audioHelper?.stop(); audioHelper = nil
        inputBuilder?.finish(); inputBuilder = nil
        Task {
            try? await analyzer?.finalizeAndFinishThroughEndOfInput()
            try? await Task.sleep(for: .milliseconds(500))
            recognizerTask?.cancel(); recognizerTask = nil
            analyzer = nil; transcriber = nil; analyzerFormat = nil
            overlay?.setMicTranscript(finalizedTranscript)
            overlay?.setMicActive(false)
        }
    }

    func getTranscript() -> String { finalizedTranscript + volatileTranscript }

    func clearTranscript() {
        finalizedTranscript = ""; volatileTranscript = ""
        overlay?.setMicTranscript("")
    }

    private func setupAndRun() async throws {
        let locale = Locale(identifier: AppSettings.shared.transcriptionLocale)
        let t = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        self.transcriber = t

        let status = await AssetInventory.status(forModules: [t])
        switch status {
        case .unsupported:
            throw TranscriptionError.localeNotSupported
        case .supported, .downloading:
            if let req = try await AssetInventory.assetInstallationRequest(supporting: [t]) {
                try await req.downloadAndInstall()
            }
        case .installed: break
        @unknown default: break
        }

        analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [t])
        let (stream, builder) = AsyncStream.makeStream(of: AnalyzerInput.self)
        self.inputBuilder = builder
        self.analyzer = SpeechAnalyzer(inputSequence: stream, modules: [t])

        recognizerTask = Task { [weak self] in
            do {
                for try await result in t.results {
                    guard let self else { break }
                    let text = String(result.text.characters)
                    if result.isFinal {
                        self.finalizedTranscript += text + "\n"
                        self.volatileTranscript = ""
                    } else {
                        self.volatileTranscript = text
                    }
                    self.overlay?.setMicTranscript(self.finalizedTranscript + self.volatileTranscript)
                }
            } catch {
                if !Task.isCancelled { print("Transcription error: \(error)") }
            }
        }

        let helper = AudioCaptureHelper()
        self.audioHelper = helper
        try helper.start(targetFormat: analyzerFormat, inputBuilder: builder)
    }
}

final class AudioCaptureHelper: @unchecked Sendable {
    private var audioEngine: AVAudioEngine?

    func start(targetFormat: AVAudioFormat?, inputBuilder: AsyncStream<AnalyzerInput>.Continuation) throws {
        let engine = AVAudioEngine()
        self.audioEngine = engine
        let inputNode = engine.inputNode
        let hwFmt = inputNode.outputFormat(forBus: 0)
        guard let targetFormat else { throw TranscriptionError.noFormat }

        let needsConvert = hwFmt.sampleRate != targetFormat.sampleRate || hwFmt.channelCount != targetFormat.channelCount
        let converter: AVAudioConverter? = needsConvert ? AVAudioConverter(from: hwFmt, to: targetFormat) : nil

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFmt) { buffer, _ in
            if let converter {
                let cap = AVAudioFrameCount(Double(buffer.frameLength) * targetFormat.sampleRate / hwFmt.sampleRate)
                guard cap > 0, let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: cap) else { return }
                nonisolated(unsafe) var consumed = false
                let status = converter.convert(to: out, error: nil) { _, outStatus in
                    if consumed { outStatus.pointee = .noDataNow; return nil }
                    consumed = true; outStatus.pointee = .haveData; return buffer
                }
                if status == .haveData || status == .inputRanDry { inputBuilder.yield(AnalyzerInput(buffer: out)) }
            } else {
                inputBuilder.yield(AnalyzerInput(buffer: buffer))
            }
        }
        try engine.start()
    }

    func stop() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop(); audioEngine = nil
    }
}

enum TranscriptionError: Error, LocalizedError {
    case initFailed, noFormat, localeNotSupported
    var errorDescription: String? {
        switch self {
        case .initFailed: "SpeechTranscriber init failed"
        case .noFormat: "Could not get audio format"
        case .localeNotSupported: "Locale not supported for local transcription"
        }
    }
}

@preconcurrency import AVFoundation
import Speech

/// Manages real-time mic transcription using SpeechTranscriber (macOS 26+).
@MainActor
final class TranscriptionManager {
    private weak var overlay: OverlayController?

    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var analyzerFormat: AVAudioFormat?

    private var audioHelper: AudioCaptureHelper?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?

    private var recognizerTask: Task<Void, Never>?

    private var finalizedTranscript: String = ""
    private var volatileTranscript: String = ""

    private(set) var isRunning = false

    init(overlay: OverlayController) {
        self.overlay = overlay
    }

    // MARK: - Public

    func toggle() {
        if isRunning { stop() } else { Task { await start() } }
    }

    func start() async {
        guard !isRunning else { return }
        isRunning = true
        finalizedTranscript = ""
        volatileTranscript = ""
        overlay?.setText("Initializing mic transcription…", for: .transcription)
        overlay?.setMicActive(true)

        do {
            try await setupAndRun()
        } catch {
            overlay?.setText("Mic init failed: \(error.localizedDescription)", for: .transcription)
            overlay?.setMicActive(false)
            isRunning = false
            print("Transcription error: \(error)")
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        audioHelper?.stop()
        audioHelper = nil

        inputBuilder?.finish()
        inputBuilder = nil

        Task {
            try? await analyzer?.finalizeAndFinishThroughEndOfInput()
            try? await Task.sleep(for: .milliseconds(500))
            recognizerTask?.cancel()
            recognizerTask = nil
            analyzer = nil
            transcriber = nil
            analyzerFormat = nil

            let finalText = finalizedTranscript.isEmpty ? "(no content)" : finalizedTranscript
            overlay?.setText("Mic stopped.\n\n\(finalText)", for: .transcription)
            overlay?.setMicActive(false)
        }
    }

    func getTranscript() -> String {
        return finalizedTranscript + volatileTranscript
    }

    // MARK: - Private Setup

    private func setupAndRun() async throws {
        let locale = Locale(identifier: "zh-Hans")

        let newTranscriber = SpeechTranscriber(
            locale: locale,
            preset: .progressiveTranscription
        )
        self.transcriber = newTranscriber

        let status = await AssetInventory.status(forModules: [newTranscriber])
        switch status {
        case .unsupported:
            throw TranscriptionError.localeNotSupported
        case .supported, .downloading:
            overlay?.setText("Downloading speech model…", for: .transcription)
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [newTranscriber]) {
                try await request.downloadAndInstall()
            }
        case .installed:
            break
        @unknown default:
            break
        }

        analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [newTranscriber])

        let (stream, builder) = AsyncStream.makeStream(of: AnalyzerInput.self)
        self.inputBuilder = builder

        let newAnalyzer = SpeechAnalyzer(
            inputSequence: stream,
            modules: [newTranscriber]
        )
        self.analyzer = newAnalyzer

        overlay?.setText("Listening (mic)…\n\n", for: .transcription)

        startResultProcessing()

        let helper = AudioCaptureHelper()
        self.audioHelper = helper
        try helper.start(targetFormat: analyzerFormat, inputBuilder: builder)
    }

    private func startResultProcessing() {
        guard let transcriber = transcriber else { return }

        recognizerTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard let self = self else { break }

                    let text = String(result.text.characters)

                    if result.isFinal {
                        self.finalizedTranscript += text + "\n"
                        self.volatileTranscript = ""
                    } else {
                        self.volatileTranscript = text
                    }

                    let display = self.finalizedTranscript + self.volatileTranscript
                    self.overlay?.setText("Listening (mic)…\n\n\(display)", for: .transcription)
                }
            } catch {
                if !Task.isCancelled {
                    print("Transcription result error: \(error)")
                }
            }
        }
    }
}

// MARK: - Audio Capture Helper (non-isolated, safe for realtime audio thread)

final class AudioCaptureHelper: @unchecked Sendable {
    private var audioEngine: AVAudioEngine?

    func start(targetFormat: AVAudioFormat?, inputBuilder: AsyncStream<AnalyzerInput>.Continuation) throws {
        let engine = AVAudioEngine()
        self.audioEngine = engine

        let inputNode = engine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)

        guard let targetFormat = targetFormat else {
            throw TranscriptionError.noFormat
        }

        let needsConversion = hardwareFormat.sampleRate != targetFormat.sampleRate ||
            hardwareFormat.channelCount != targetFormat.channelCount
        let converter: AVAudioConverter? = needsConversion
            ? AVAudioConverter(from: hardwareFormat, to: targetFormat)
            : nil

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { buffer, _ in
            if let converter = converter {
                let ratio = targetFormat.sampleRate / hardwareFormat.sampleRate
                let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
                guard frameCapacity > 0,
                      let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else {
                    return
                }

                nonisolated(unsafe) var consumed = false
                let status = converter.convert(to: convertedBuffer, error: nil) { _, outStatus in
                    if consumed {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                    consumed = true
                    outStatus.pointee = .haveData
                    return buffer
                }
                if status == .haveData || status == .inputRanDry {
                    inputBuilder.yield(AnalyzerInput(buffer: convertedBuffer))
                }
            } else {
                inputBuilder.yield(AnalyzerInput(buffer: buffer))
            }
        }

        try engine.start()
        print("Audio engine started, format: \(hardwareFormat)")
    }

    func stop() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
    }
}

enum TranscriptionError: Error, LocalizedError {
    case initFailed
    case noFormat
    case localeNotSupported

    var errorDescription: String? {
        switch self {
        case .initFailed: return "SpeechTranscriber init failed"
        case .noFormat: return "Could not get audio format"
        case .localeNotSupported: return "Locale not supported for local transcription"
        }
    }
}

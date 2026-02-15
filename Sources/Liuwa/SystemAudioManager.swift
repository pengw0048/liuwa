@preconcurrency import AVFoundation
import CoreAudio
import Speech

/// Captures system audio via Core Audio Process Tap and feeds to SpeechTranscriber.
@MainActor
final class SystemAudioManager {
    private weak var overlay: OverlayController?

    private var tapID: AudioObjectID = 0
    private var aggregateDeviceID: AudioObjectID = 0
    private var audioHelper: SystemAudioCaptureHelper?
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var recognizerTask: Task<Void, Never>?

    private var finalizedTranscript: String = ""
    private var volatileTranscript: String = ""
    private(set) var isRunning = false

    init(overlay: OverlayController) {
        self.overlay = overlay
    }

    func toggle() {
        if isRunning { stop() } else { Task { await start() } }
    }

    func start() async {
        guard !isRunning else { return }
        isRunning = true
        finalizedTranscript = ""
        volatileTranscript = ""

        overlay?.setSysAudioActive(true)

        do {
            try await setupSystemAudioTap()
        } catch {
            overlay?.setSysAudioActive(false)
            print("System audio error: \(error)")
            isRunning = false
            print("System audio error: \(error)")
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
            try? await Task.sleep(for: .milliseconds(300))
            recognizerTask?.cancel()
            recognizerTask = nil
            analyzer = nil
            transcriber = nil
        }

        if tapID != 0 {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = 0
        }

        overlay?.setSysTranscript(finalizedTranscript)
        overlay?.setSysAudioActive(false)
    }

    func getTranscript() -> String {
        return finalizedTranscript + volatileTranscript
    }

    func clearTranscript() {
        finalizedTranscript = ""
        volatileTranscript = ""
        overlay?.setSysTranscript("")
    }

    // MARK: - Private

    private func setupSystemAudioTap() async throws {
        let tapDesc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDesc.name = "Liuwa System Audio Tap"
        tapDesc.muteBehavior = .unmuted

        var newTapID: AudioObjectID = 0
        let status = AudioHardwareCreateProcessTap(tapDesc, &newTapID)
        guard status == noErr else {
            throw SystemAudioError.tapCreationFailed(status)
        }
        self.tapID = newTapID

        let tapUID = try getStringProperty(forObject: newTapID, selector: kAudioTapPropertyTapUID)
        aggregateDeviceID = try createAggregateDevice(tapUID: tapUID)

        let locale = Locale(identifier: "zh-Hans")
        let newTranscriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        self.transcriber = newTranscriber

        let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [newTranscriber])
        let (stream, builder) = AsyncStream.makeStream(of: AnalyzerInput.self)
        self.inputBuilder = builder

        let newAnalyzer = SpeechAnalyzer(inputSequence: stream, modules: [newTranscriber])
        self.analyzer = newAnalyzer

        startResultProcessing()

        let helper = SystemAudioCaptureHelper()
        self.audioHelper = helper
        try helper.start(aggregateDeviceID: aggregateDeviceID, targetFormat: analyzerFormat, inputBuilder: builder)

        print("System audio listening…")
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
                    self.overlay?.setSysTranscript(display)
                }
            } catch {
                if !Task.isCancelled {
                    print("System audio transcription error: \(error)")
                }
            }
        }
    }

    // MARK: - Audio Object Helpers

    private func getStringProperty(forObject objectID: AudioObjectID, selector: AudioObjectPropertySelector) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &dataSize)
        guard status == noErr else { throw SystemAudioError.propertyError(status) }

        var cfStr: Unmanaged<CFString>?
        status = withUnsafeMutablePointer(to: &cfStr) { ptr in
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, ptr)
        }
        guard status == noErr, let result = cfStr?.takeUnretainedValue() else {
            throw SystemAudioError.propertyError(status)
        }
        return result as String
    }

    private func createAggregateDevice(tapUID: String) throws -> AudioObjectID {
        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "Liuwa Tap Aggregate",
            kAudioAggregateDeviceUIDKey as String: "com.liuwa.tap-aggregate-\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceTapListKey as String: [
                [kAudioSubTapUIDKey as String: tapUID]
            ],
            kAudioAggregateDeviceTapAutoStartKey as String: true,
        ]

        var aggregateID: AudioObjectID = 0
        let status = AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &aggregateID)
        guard status == noErr else {
            throw SystemAudioError.aggregateDeviceFailed(status)
        }
        return aggregateID
    }
}

// MARK: - Non-isolated Audio Capture Helper

final class SystemAudioCaptureHelper: @unchecked Sendable {
    private var audioEngine: AVAudioEngine?

    func start(aggregateDeviceID: AudioObjectID, targetFormat: AVAudioFormat?, inputBuilder: AsyncStream<AnalyzerInput>.Continuation) throws {
        let engine = AVAudioEngine()

        let audioUnit = engine.inputNode.audioUnit!
        var deviceID = aggregateDeviceID
        AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioObjectID>.size)
        )

        self.audioEngine = engine

        let inputNode = engine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)

        let converter: AVAudioConverter?
        if let targetFormat = targetFormat,
           (hardwareFormat.sampleRate != targetFormat.sampleRate || hardwareFormat.channelCount != targetFormat.channelCount) {
            converter = AVAudioConverter(from: hardwareFormat, to: targetFormat)
        } else {
            converter = nil
        }

        let resolvedFormat = targetFormat ?? hardwareFormat

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { buffer, _ in
            if let converter = converter {
                let ratio = resolvedFormat.sampleRate / hardwareFormat.sampleRate
                let cap = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
                guard cap > 0,
                      let converted = AVAudioPCMBuffer(pcmFormat: resolvedFormat, frameCapacity: cap) else { return }

                nonisolated(unsafe) var consumed = false
                let _ = converter.convert(to: converted, error: nil) { _, outStatus in
                    if consumed { outStatus.pointee = .noDataNow; return nil }
                    consumed = true
                    outStatus.pointee = .haveData
                    return buffer
                }
                inputBuilder.yield(AnalyzerInput(buffer: converted))
            } else {
                inputBuilder.yield(AnalyzerInput(buffer: buffer))
            }
        }

        try engine.start()
        print("System audio engine started, format: \(hardwareFormat)")
    }

    func stop() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
    }
}

private let kAudioTapPropertyTapUID: AudioObjectPropertySelector = 0x74756964

enum SystemAudioError: Error, LocalizedError {
    case tapCreationFailed(OSStatus)
    case aggregateDeviceFailed(OSStatus)
    case propertyError(OSStatus)

    var errorDescription: String? {
        switch self {
        case .tapCreationFailed(let s): return "Audio tap creation failed (OSStatus: \(s))"
        case .aggregateDeviceFailed(let s): return "Aggregate device failed (OSStatus: \(s))"
        case .propertyError(let s): return "Audio property read failed (OSStatus: \(s))"
        }
    }
}

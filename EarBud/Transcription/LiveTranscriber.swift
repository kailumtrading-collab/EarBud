import Speech
import AVFoundation
import CoreMedia

/// Wraps Apple's on-device SpeechAnalyzer/SpeechTranscriber (macOS 26) to turn
/// a live stream of microphone buffers into timestamped transcript chunks.
final class LiveTranscriber {
    struct TranscribedChunk {
        let text: String
        let range: CMTimeRange
    }

    private let locale: Locale
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var targetFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?

    var onChunk: ((TranscribedChunk) -> Void)?

    init(locale: Locale = Locale(identifier: "en-US")) {
        self.locale = locale
    }

    /// Installs model assets if needed and primes the analyzer. Call once before `start()`.
    func prepare() async throws {
        // Deliberately omit `.volatileResults`: with it enabled, the transcriber
        // repeatedly emits in-progress hypotheses for the same audio span as it
        // revises its guess, and each one was being appended as a separate final
        // chunk — producing duplicated, garbled text. Without it we only get
        // each phrase once, after the model has committed to it.
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )
        self.transcriber = transcriber

        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }

        targetFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        resultsTask = Task { [weak self] in
            guard let resultsSequence = self?.transcriber?.results else { return }
            do {
                for try await result in resultsSequence {
                    let chunk = TranscribedChunk(text: String(result.text.characters), range: result.range)
                    self?.onChunk?(chunk)
                }
            } catch {
                print("LiveTranscriber: results stream ended with error: \(error)")
            }
        }
    }

    /// Begins an analysis session. Feed audio via `ingest(_:)` afterwards.
    func start() async throws {
        // SpeechAnalyzer requires priming with the target format before its
        // input sequence is started; skipping this crashed inside the
        // framework's internal sequence-handling once real audio arrived.
        try await analyzer?.prepareToAnalyze(in: targetFormat)

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputContinuation = continuation
        try await analyzer?.start(inputSequence: stream)
    }

    /// Feeds one microphone buffer, converting it to the analyzer's preferred format if needed.
    func ingest(_ buffer: AVAudioPCMBuffer) {
        guard let targetFormat else { return }

        if buffer.format == targetFormat {
            inputContinuation?.yield(AnalyzerInput(buffer: buffer))
            return
        }

        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: targetFormat)
        }
        guard let converter else { return }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var inputProvided = false
        var conversionError: NSError?
        converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if inputProvided {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputProvided = true
            outStatus.pointee = .haveData
            return buffer
        }

        if conversionError == nil {
            inputContinuation?.yield(AnalyzerInput(buffer: outputBuffer))
        }
    }

    func finish() async {
        inputContinuation?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        resultsTask?.cancel()
    }
}

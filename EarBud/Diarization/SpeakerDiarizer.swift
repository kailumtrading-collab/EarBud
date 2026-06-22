import FluidAudio
import AVFoundation

/// Wraps FluidAudio's on-device (CoreML/ANE) speaker diarization pipeline.
/// Audio is buffered and diarized in fixed-size chunks; FluidAudio's
/// `SpeakerManager` (held inside `DiarizerManager`) keeps speaker identities
/// consistent across chunks within a session.
final class SpeakerDiarizer {
    struct SpeakerSegment {
        let speakerId: String
        let startTime: TimeInterval
        let endTime: TimeInterval
    }

    private let config = DiarizerConfig.default
    private let manager: DiarizerManager
    private let converter = AudioConverter(sampleRate: 16_000)
    private let sampleRate: Double = 16_000
    private let chunkSeconds: TimeInterval = 6.0

    private let lock = NSLock()
    private var pendingSamples: [Float] = []
    private var elapsedSeconds: TimeInterval = 0
    private var isReady = false

    var onSegments: (([SpeakerSegment]) -> Void)?

    init() {
        manager = DiarizerManager(config: config)
    }

    /// Downloads/loads the CoreML models once and reuses them across every
    /// recording session (this was previously re-downloading and
    /// re-initializing on every single `Record` press).
    func prepare() async throws {
        guard !isReady else { return }
        let models = try await DiarizerModels.downloadIfNeeded()
        manager.initialize(models: models)
        isReady = true
    }

    /// Must be called at the start of every new recording session. Without
    /// this, `elapsedSeconds` and FluidAudio's known-speaker identities carry
    /// over from the previous session, so a second recording's diarization
    /// timestamps drift out of sync with that session's transcript timestamps
    /// and every speaker silently resolves to "Unknown".
    func reset() {
        lock.lock()
        pendingSamples.removeAll()
        elapsedSeconds = 0
        lock.unlock()
        manager.speakerManager = SpeakerManager(
            speakerThreshold: config.clusteringThreshold * 1.2,
            embeddingThreshold: config.clusteringThreshold * 0.8,
            minSpeechDuration: config.minSpeechDuration,
            minEmbeddingUpdateDuration: config.minEmbeddingUpdateDuration
        )
    }

    /// Cheap: just resamples and buffers. Call `processAvailableChunks()` from
    /// a background task to actually run inference.
    func ingest(_ buffer: AVAudioPCMBuffer) {
        guard let samples = try? converter.resampleBuffer(buffer) else { return }
        lock.lock()
        pendingSamples.append(contentsOf: samples)
        lock.unlock()
    }

    /// Runs CoreML inference on any full chunks accumulated so far. Intended
    /// to be polled periodically off the main thread while recording.
    func processAvailableChunks() {
        let chunkSampleCount = Int(chunkSeconds * sampleRate)
        while true {
            lock.lock()
            guard pendingSamples.count >= chunkSampleCount else {
                lock.unlock()
                break
            }
            let chunk = Array(pendingSamples.prefix(chunkSampleCount))
            pendingSamples.removeFirst(chunkSampleCount)
            lock.unlock()
            processChunk(chunk)
        }
    }

    /// Flushes any remaining partial chunk. Call once when recording stops.
    func finish() {
        lock.lock()
        let remaining = pendingSamples
        pendingSamples.removeAll()
        lock.unlock()
        guard !remaining.isEmpty else { return }
        processChunk(remaining)
    }

    private func processChunk(_ chunk: [Float]) {
        let startTime = elapsedSeconds
        elapsedSeconds += Double(chunk.count) / sampleRate
        do {
            let result = try manager.performCompleteDiarization(
                chunk, sampleRate: Int(sampleRate), atTime: startTime
            )
            let segments = result.segments.map {
                SpeakerSegment(
                    speakerId: $0.speakerId,
                    startTime: TimeInterval($0.startTimeSeconds),
                    endTime: TimeInterval($0.endTimeSeconds)
                )
            }
            onSegments?(segments)
        } catch {
            print("SpeakerDiarizer: chunk failed: \(error)")
        }
    }
}

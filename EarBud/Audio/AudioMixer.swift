import AVFoundation

/// Resamples two independent audio streams (mic + system output) to a common
/// mono format and sums them into one combined stream, so the rest of the
/// pipeline (transcription + diarization) can treat a video call's local and
/// remote audio as a single coherent conversation.
final class AudioMixer {
    private let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    private var micSamples: [Float] = []
    private var systemSamples: [Float] = []
    private let lock = NSLock()

    private var micConverter: AVAudioConverter?
    private var systemConverter: AVAudioConverter?

    private var continuations: [AsyncStream<AVAudioPCMBuffer>.Continuation] = []

    func makeBufferStream() -> AsyncStream<AVAudioPCMBuffer> {
        AsyncStream { continuation in
            continuations.append(continuation)
        }
    }

    func ingestMic(_ buffer: AVAudioPCMBuffer) {
        guard let samples = resample(buffer, converter: &micConverter) else { return }
        lock.lock()
        micSamples.append(contentsOf: samples)
        lock.unlock()
    }

    func ingestSystem(_ buffer: AVAudioPCMBuffer) {
        guard let samples = resample(buffer, converter: &systemConverter) else { return }
        lock.lock()
        systemSamples.append(contentsOf: samples)
        lock.unlock()
    }

    /// Mixes and emits whatever overlapping audio has accumulated from both
    /// sources, then flushes any leftover audio from whichever source has
    /// more buffered right now (e.g. no call is active so the system tap
    /// only contributes near-silence and falls behind the mic, or vice
    /// versa). Call periodically.
    func drain() {
        lock.lock()
        let overlap = min(micSamples.count, systemSamples.count)
        let micChunk = Array(micSamples.prefix(overlap))
        let systemChunk = Array(systemSamples.prefix(overlap))
        micSamples.removeFirst(overlap)
        systemSamples.removeFirst(overlap)

        let leftoverMic = micSamples
        let leftoverSystem = systemSamples
        micSamples.removeAll()
        systemSamples.removeAll()
        lock.unlock()

        if overlap > 0 {
            var mixed = [Float](repeating: 0, count: overlap)
            for i in 0..<overlap {
                mixed[i] = max(-1, min(1, micChunk[i] + systemChunk[i]))
            }
            emit(mixed)
        }
        if !leftoverMic.isEmpty {
            emit(leftoverMic)
        }
        if !leftoverSystem.isEmpty {
            emit(leftoverSystem)
        }
    }

    /// Call at the end of every recording session. Without clearing the
    /// sample buffers here, any unflushed audio would otherwise bleed into
    /// the start of the next recording.
    func finish() {
        lock.lock()
        micSamples.removeAll()
        systemSamples.removeAll()
        lock.unlock()
        for continuation in continuations {
            continuation.finish()
        }
        continuations.removeAll()
    }

    private func emit(_ samples: [Float]) {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            buffer.floatChannelData?[0].update(from: base, count: samples.count)
        }
        for continuation in continuations {
            continuation.yield(buffer)
        }
    }

    private func resample(_ buffer: AVAudioPCMBuffer, converter: inout AVAudioConverter?) -> [Float]? {
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: format)
        }
        guard let converter else { return nil }

        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

        var inputProvided = false
        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if inputProvided {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputProvided = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard error == nil, let channelData = outputBuffer.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(start: channelData[0], count: Int(outputBuffer.frameLength)))
    }
}

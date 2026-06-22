import AVFoundation

/// Taps the system default microphone and broadcasts copies of each PCM
/// buffer to every active subscriber (the transcriber and the diarizer each
/// need their own independent stream of the same audio).
final class AudioCaptureEngine {
    private let engine = AVAudioEngine()
    private var continuations: [AsyncStream<AVAudioPCMBuffer>.Continuation] = []
    private(set) var isRunning = false

    var inputFormat: AVAudioFormat {
        engine.inputNode.outputFormat(forBus: 0)
    }

    func makeBufferStream() -> AsyncStream<AVAudioPCMBuffer> {
        AsyncStream { continuation in
            continuations.append(continuation)
        }
    }

    func start() throws {
        guard !isRunning else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            for continuation in self.continuations {
                if let copy = buffer.deepCopy() {
                    continuation.yield(copy)
                }
            }
        }
        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        for continuation in continuations {
            continuation.finish()
        }
        continuations.removeAll()
    }
}

extension AVAudioPCMBuffer {
    func deepCopy() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else { return nil }
        copy.frameLength = frameLength
        let channelCount = Int(format.channelCount)
        let frames = Int(frameLength)
        if let src = floatChannelData, let dst = copy.floatChannelData {
            for channel in 0..<channelCount {
                dst[channel].update(from: src[channel], count: frames)
            }
        } else if let src = int16ChannelData, let dst = copy.int16ChannelData {
            for channel in 0..<channelCount {
                dst[channel].update(from: src[channel], count: frames)
            }
        }
        return copy
    }
}

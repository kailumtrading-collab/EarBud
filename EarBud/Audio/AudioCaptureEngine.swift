import AVFoundation

/// Taps the system default microphone and broadcasts copies of each PCM
/// buffer to every active subscriber (the transcriber and the diarizer each
/// need their own independent stream of the same audio).
final class AudioCaptureEngine {
    private let engine = AVAudioEngine()
    private var continuations: [AsyncStream<AVAudioPCMBuffer>.Continuation] = []
    private(set) var isRunning = false
    private var configChangeObserver: NSObjectProtocol?

    var onLevel: ((Float) -> Void)?

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
        installTap()
        engine.prepare()
        try engine.start()
        isRunning = true

        // Switching input devices mid-recording (e.g. AirPods connecting or
        // disconnecting) changes the input node's native format. The engine
        // tears itself down when that happens, so without reinstalling the
        // tap and restarting here, capture would silently go dead until the
        // next manual Record/Stop.
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }
    }

    func stop() {
        guard isRunning else { return }
        if let configChangeObserver {
            NotificationCenter.default.removeObserver(configChangeObserver)
            self.configChangeObserver = nil
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        for continuation in continuations {
            continuation.finish()
        }
        continuations.removeAll()
    }

    private func installTap() {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            for continuation in self.continuations {
                if let copy = buffer.deepCopy() {
                    continuation.yield(copy)
                }
            }
            self.onLevel?(Self.rms(buffer))
        }
    }

    private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let frames = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<frames { sum += channel[i] * channel[i] }
        return sqrt(sum / Float(frames))
    }

    private func handleConfigurationChange() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        installTap()
        engine.prepare()
        do {
            try engine.start()
        } catch {
            print("AudioCaptureEngine: failed to restart after configuration change: \(error)")
        }
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

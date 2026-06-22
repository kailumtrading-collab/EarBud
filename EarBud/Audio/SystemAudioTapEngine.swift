import CoreAudio
import AudioToolbox
import AVFoundation

enum SystemAudioTapError: Error {
    case tapCreationFailed
    case noOutputDevice
    case aggregateDeviceCreationFailed
    case invalidFormat
    case ioProcCreationFailed
}

/// Captures system-wide output audio (e.g. the remote side of a video/voice
/// call playing through speakers) via macOS's Core Audio process-tap API
/// (macOS 14.2+), using the Swift-native `AudioHardwareSystem` wrappers
/// (macOS 15+). Gated behind the same TCC permission as screen recording
/// ("Screen & System Audio Recording" in System Settings).
final class SystemAudioTapEngine {
    private let hardware = AudioHardwareSystem.shared
    private var tap: AudioHardwareTap?
    private var aggregateDevice: AudioHardwareAggregateDevice?
    private var deviceProcID: AudioDeviceIOProcID?
    private var continuations: [AsyncStream<AVAudioPCMBuffer>.Continuation] = []
    private(set) var isRunning = false

    func makeBufferStream() -> AsyncStream<AVAudioPCMBuffer> {
        AsyncStream { continuation in
            continuations.append(continuation)
        }
    }

    func start() throws {
        guard !isRunning else { return }

        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDescription.uuid = UUID()
        tapDescription.muteBehavior = .unmuted

        guard let tap = try hardware.makeProcessTap(description: tapDescription) else {
            throw SystemAudioTapError.tapCreationFailed
        }
        self.tap = tap

        guard let systemOutput = try hardware.defaultOutputDevice else {
            throw SystemAudioTapError.noOutputDevice
        }
        let outputUID = try systemOutput.uid

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "EarBud System Audio Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapDescription.uuid.uuidString,
                ]
            ],
        ]

        guard let aggregateDevice = try hardware.makeAggregateDevice(description: aggregateDescription) else {
            throw SystemAudioTapError.aggregateDeviceCreationFailed
        }
        self.aggregateDevice = aggregateDevice

        var streamDescription = try tap.format
        guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
            throw SystemAudioTapError.invalidFormat
        }

        var procID: AudioDeviceIOProcID?
        let createErr = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateDevice.id, nil) { [weak self] _, inInputData, _, _, _ in
            guard let self else { return }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: inInputData, deallocator: nil) else { return }
            for continuation in self.continuations {
                if let copy = buffer.deepCopy() {
                    continuation.yield(copy)
                }
            }
        }
        guard createErr == noErr, let procID else {
            throw SystemAudioTapError.ioProcCreationFailed
        }
        deviceProcID = procID

        try aggregateDevice.start(IOProcID: procID)
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        if let aggregateDevice, let deviceProcID {
            try? aggregateDevice.stop(IOProcID: deviceProcID)
            AudioDeviceDestroyIOProcID(aggregateDevice.id, deviceProcID)
        }
        if let aggregateDevice {
            try? hardware.destroyAggregateDevice(aggregateDevice)
        }
        if let tap {
            try? hardware.destroyProcessTap(tap)
        }
        aggregateDevice = nil
        tap = nil
        deviceProcID = nil
        isRunning = false
        for continuation in continuations {
            continuation.finish()
        }
        continuations.removeAll()
    }
}

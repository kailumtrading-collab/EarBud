import Foundation
import AVFoundation
import CoreMedia
import Combine

/// Owns one recording session end-to-end: captures mic audio, feeds it to the
/// transcriber and diarizer in parallel, and fuses their output by timestamp
/// into per-speaker transcript turns.
@MainActor
final class ConversationPipeline: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isPreparing = false
    @Published private(set) var liveSegments: [TranscriptSegment] = []
    @Published private(set) var speakers: [Speaker] = []
    @Published private(set) var lastNameDetection: String?
    @Published var lastError: String?

    private let userProfile: UserProfile
    private let audioEngine = AudioCaptureEngine()
    private let systemAudioEngine = SystemAudioTapEngine()
    private let mixer = AudioMixer()
    private let transcriber = LiveTranscriber()
    private let diarizer = SpeakerDiarizer()

    private var diarizationSegments: [SpeakerDiarizer.SpeakerSegment] = []
    private var rawChunks: [(text: String, start: TimeInterval, end: TimeInterval)] = []
    private var lastChunkReceivedAt: Date?
    private var sessionStartedAt: Date?
    private var pollTask: Task<Void, Never>?
    private var micFeedTask: Task<Void, Never>?
    private var systemFeedTask: Task<Void, Never>?
    private var mixedFeedTask: Task<Void, Never>?
    private var nameBannerTask: Task<Void, Never>?

    // The first known speaker to talk is assumed to be the device owner,
    // since you're almost always present from the moment you hit Record.
    // Their name comes from `userProfile`, never from a transcript guess.
    private var selfSpeakerId: String?
    private var speakerNames: [String: String] = [:]
    private var nameDetectionNotices: [String] = []

    init(userProfile: UserProfile) {
        self.userProfile = userProfile
    }

    func start() async {
        guard !isRecording, !isPreparing else { return }
        lastError = nil
        liveSegments = []
        speakers = []
        diarizationSegments = []
        rawChunks = []
        lastChunkReceivedAt = nil
        selfSpeakerId = nil
        speakerNames = [:]
        nameDetectionNotices = []
        lastNameDetection = nil
        sessionStartedAt = Date()
        diarizer.reset()

        isPreparing = true
        do {
            try await transcriber.prepare()
            try await diarizer.prepare()
        } catch {
            isPreparing = false
            lastError = "Setup failed: \(error.localizedDescription)"
            return
        }
        isPreparing = false

        transcriber.onChunk = { [weak self] chunk in
            Task { @MainActor [weak self] in
                self?.handleTranscriptChunk(chunk)
            }
        }
        diarizer.onSegments = { [weak self] segments in
            Task { @MainActor [weak self] in
                self?.handleDiarizationSegments(segments)
            }
        }

        do {
            try audioEngine.start()
            try await transcriber.start()
        } catch {
            lastError = "Could not start audio: \(error.localizedDescription)"
            return
        }

        do {
            try systemAudioEngine.start()
        } catch {
            // Non-fatal: still records the mic-only side of the conversation.
            print("ConversationPipeline: system audio capture unavailable: \(error)")
        }

        isRecording = true

        let micStream = audioEngine.makeBufferStream()
        let systemStream = systemAudioEngine.makeBufferStream()
        let mixedStream = mixer.makeBufferStream()
        let mixer = self.mixer
        let transcriber = self.transcriber
        let diarizer = self.diarizer

        micFeedTask = Task.detached {
            for await buffer in micStream {
                mixer.ingestMic(buffer)
            }
        }
        systemFeedTask = Task.detached {
            for await buffer in systemStream {
                mixer.ingestSystem(buffer)
            }
        }
        mixedFeedTask = Task.detached {
            for await buffer in mixedStream {
                transcriber.ingest(buffer)
                diarizer.ingest(buffer)
            }
        }

        pollTask = Task.detached { [diarizer, mixer] in
            while !Task.isCancelled {
                mixer.drain()
                diarizer.processAvailableChunks()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func stop() async -> ConversationSession? {
        guard isRecording, let startedAt = sessionStartedAt else { return nil }
        isRecording = false
        pollTask?.cancel()
        audioEngine.stop()
        systemAudioEngine.stop()
        micFeedTask?.cancel()
        systemFeedTask?.cancel()
        mixer.drain()
        mixer.finish()
        mixedFeedTask?.cancel()
        diarizer.finish()
        await transcriber.finish()

        return ConversationSession(
            startedAt: startedAt,
            endedAt: Date(),
            speakers: speakers,
            segments: liveSegments,
            nameDetectionNotices: nameDetectionNotices
        )
    }

    private func handleTranscriptChunk(_ chunk: LiveTranscriber.TranscribedChunk) {
        guard !chunk.text.isEmpty else { return }
        let start = chunk.range.start.seconds
        let end = chunk.range.end.seconds
        let now = Date()

        // SpeechTranscriber emits several "final" results for the same
        // utterance, each restating it with more words as it refines its
        // hypothesis (observed even with volatileResults disabled, e.g.
        // "Div" -> "Divor" -> "Divorce" -> "Divorce share" -> ...). Comparing
        // result.range proved unreliable for detecting this (likely an
        // invalid/zero CMTime on some results), so instead treat a new chunk
        // as a revision of the previous one — and replace it rather than
        // appending — whenever the text is a prefix-extension of (or of) the
        // last chunk, or it arrived within a couple seconds of it. A real new
        // utterance after a pause won't match either condition.
        let isRevision: Bool
        if let last = rawChunks.last {
            let textOverlaps = chunk.text.hasPrefix(last.text) || last.text.hasPrefix(chunk.text)
            let arrivedQuickly = now.timeIntervalSince(lastChunkReceivedAt ?? .distantPast) < 2
            isRevision = textOverlaps || arrivedQuickly
        } else {
            isRevision = false
        }
        lastChunkReceivedAt = now

        if isRevision {
            rawChunks[rawChunks.count - 1] = (text: chunk.text, start: rawChunks[rawChunks.count - 1].start, end: end)
        } else {
            rawChunks.append((text: chunk.text, start: start, end: end))
        }
        rebuildSegments()
        detectExchangedNames(in: chunk.text, midpoint: (start + end) / 2)
    }

    private func handleDiarizationSegments(_ segments: [SpeakerDiarizer.SpeakerSegment]) {
        diarizationSegments.append(contentsOf: segments)
        if selfSpeakerId == nil {
            selfSpeakerId = diarizationSegments.first { $0.speakerId != "Unknown" }?.speakerId
        }
        rebuildSegments()
        rebuildSpeakerTalkTime()
    }

    /// Looks for self-introductions ("I'm Sarah") and greetings ("Hi Sarah")
    /// in a finalized line of transcript and, if found, attributes the name
    /// to the right speaker so future turns show their real name.
    private func detectExchangedNames(in text: String, midpoint: TimeInterval) {
        let speaking = speakerId(at: midpoint)
        if let name = SpeakerNameDetector.detectSelfIntroduction(in: text) {
            recordDetectedName(name, for: speaking)
        }
        if let name = SpeakerNameDetector.detectAddressedName(in: text) {
            if let other = mostRecentOtherSpeaker(than: speaking) {
                recordDetectedName(name, for: other)
            }
        }
    }

    private func mostRecentOtherSpeaker(than speakerId: String) -> String? {
        diarizationSegments.reversed().first { $0.speakerId != speakerId && $0.speakerId != "Unknown" }?.speakerId
    }

    private func recordDetectedName(_ name: String, for speakerId: String) {
        // The device owner's name is authoritative from settings — never
        // overwritten by a transcript guess.
        guard speakerId != "Unknown", speakerId != selfSpeakerId, name.count >= 2 else { return }

        let previous = speakerNames[speakerId]
        guard previous != name else { return }
        speakerNames[speakerId] = name

        // SpeechTranscriber's growing hypotheses mean we see the same name
        // captured progressively longer ("S" -> "Sa" -> "Sarah"); only
        // announce when it's a genuinely new identification, not a
        // refinement of the one we just announced.
        if previous == nil || !name.hasPrefix(previous!) {
            announceNameDetection("Identified Speaker \(speakerId) as \(name)")
        }
        rebuildSegments()
        rebuildSpeakerTalkTime()
    }

    private func announceNameDetection(_ notice: String) {
        nameDetectionNotices.append(notice)
        lastNameDetection = notice
        nameBannerTask?.cancel()
        nameBannerTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.lastNameDetection = nil
        }
    }

    private func rebuildSegments() {
        var result: [TranscriptSegment] = []
        for chunk in rawChunks {
            let speakerId = speakerId(at: (chunk.start + chunk.end) / 2)
            if let last = result.last, last.speakerId == speakerId {
                result[result.count - 1].text += " " + chunk.text
                result[result.count - 1].endTime = chunk.end
            } else {
                result.append(
                    TranscriptSegment(
                        speakerId: speakerId, text: chunk.text,
                        startTime: chunk.start, endTime: chunk.end
                    )
                )
            }
        }
        liveSegments = result
    }

    private func speakerId(at time: TimeInterval) -> String {
        diarizationSegments.first { $0.startTime <= time && time <= $0.endTime }?.speakerId ?? "Unknown"
    }

    private func rebuildSpeakerTalkTime() {
        var totals: [String: TimeInterval] = [:]
        for segment in diarizationSegments {
            totals[segment.speakerId, default: 0] += segment.endTime - segment.startTime
        }
        speakers = totals.map { id, talkTime in
            var speaker = Speaker(id: id, displayName: resolvedName(for: id))
            speaker.totalTalkTime = talkTime
            return speaker
        }.sorted { $0.totalTalkTime > $1.totalTalkTime }
    }

    /// Resolves a raw diarization speaker ID to a human label: the device
    /// owner's configured name for the assumed self-speaker, a name detected
    /// from the conversation if one was exchanged, or a generic fallback.
    private func resolvedName(for speakerId: String) -> String {
        if speakerId == "Unknown" { return "Unknown speaker" }
        if speakerId == selfSpeakerId { return userProfile.name }
        if let detected = speakerNames[speakerId] { return detected }
        return "Speaker \(speakerId)"
    }
}

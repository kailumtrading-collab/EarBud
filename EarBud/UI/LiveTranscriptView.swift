import SwiftUI

/// Renders the in-progress transcript while `pipeline` is recording, shared
/// between any surface that wants to show live speaker turns.
struct LiveTranscriptView: View {
    @ObservedObject var pipeline: ConversationPipeline

    var body: some View {
        VStack(spacing: 0) {
            micLevelBar
            audioSourceStatus
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if let notice = pipeline.lastNameDetection {
                            Text("🏷️ \(notice)")
                                .font(.caption.bold())
                                .padding(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.yellow.opacity(0.25))
                                .cornerRadius(4)
                        }
                        if pipeline.liveSegments.isEmpty {
                            Text(pipeline.isPreparing ? "Preparing…" : "Listening…")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(pipeline.liveSegments) { segment in
                            VStack(alignment: .leading, spacing: 2) {
                                speakerLabel(for: segment.speakerId)
                                Text(segment.text)
                            }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: pipeline.liveSegments.count) { _, _ in
                    proxy.scrollTo("bottom")
                }
            }
        }
    }

    private var audioSourceStatus: some View {
        Group {
            if pipeline.isCapturingSystemAudio {
                Text("Mic + system audio")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Mic only · enable Screen & System Audio Recording in System Settings for call audio")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var micLevelBar: some View {
        GeometryReader { geo in
            let db = 20 * log10f(max(pipeline.micLevel, 1e-6))
            let normalized = max(0, min(1, (db + 50) / 45))
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.accentColor.opacity(0.7))
                .frame(width: geo.size.width * CGFloat(normalized))
                .animation(.linear(duration: 0.05), value: normalized)
        }
        .frame(height: 3)
        .background(Color.secondary.opacity(0.12))
    }

    private func speakerLabel(for speakerId: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(SpeakerColor.color(for: speakerId))
                .frame(width: 7, height: 7)
            Text(displayName(for: speakerId))
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
    }

    private func displayName(for speakerId: String) -> String {
        pipeline.speakers.first { $0.id == speakerId }?.displayName
            ?? (speakerId == "Unknown" ? "Unknown speaker" : "Speaker \(speakerId)")
    }
}

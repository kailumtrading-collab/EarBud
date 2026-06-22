import SwiftUI

/// Renders the in-progress transcript while `pipeline` is recording, shared
/// between any surface that wants to show live speaker turns.
struct LiveTranscriptView: View {
    @ObservedObject var pipeline: ConversationPipeline

    var body: some View {
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
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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

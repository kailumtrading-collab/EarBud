import SwiftUI

/// The Record/Stop button shared by the main window and (previously) the
/// menu bar popover, so starting/stopping a session behaves identically
/// everywhere it appears.
struct RecordingControlBar: View {
    @ObservedObject var pipeline: ConversationPipeline
    var onStopped: (ConversationSession) -> Void

    @State private var recordingStartedAt: Date?

    var body: some View {
        HStack {
            if pipeline.isPreparing {
                ProgressView().controlSize(.small)
                Text("Preparing…").font(.caption).foregroundStyle(.secondary)
            } else {
                Button(pipeline.isRecording ? "Stop" : "Record") {
                    Task {
                        if pipeline.isRecording {
                            if let session = await pipeline.stop() {
                                onStopped(session)
                            }
                        } else {
                            await pipeline.start()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)

                if pipeline.isRecording, let start = recordingStartedAt {
                    TimelineView(.periodic(from: start, by: 1)) { context in
                        Text(formatElapsed(context.date.timeIntervalSince(start)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
        .onChange(of: pipeline.isRecording) { _, isRecording in
            recordingStartedAt = isRecording ? Date() : nil
        }
    }

    private func formatElapsed(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

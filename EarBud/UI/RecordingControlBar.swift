import SwiftUI

/// The Record/Stop button shared by the main window and (previously) the
/// menu bar popover, so starting/stopping a session behaves identically
/// everywhere it appears.
struct RecordingControlBar: View {
    @ObservedObject var pipeline: ConversationPipeline
    var onStopped: (ConversationSession) -> Void

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
            }
            Spacer()
        }
    }
}

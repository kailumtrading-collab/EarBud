import SwiftUI

struct MenuBarView: View {
    @ObservedObject var pipeline: ConversationPipeline
    @ObservedObject var sessionStore: SessionStore
    @Environment(\.openWindow) private var openWindow

    @State private var recordingStartedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            controls
            if pipeline.isRecording { micLevelBar }
            if let error = pipeline.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            Divider()
            Button("Open EarBud") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.plain)
            .padding(12)
        }
        .frame(width: 260)
        .onChange(of: pipeline.isRecording) { _, isRecording in
            recordingStartedAt = isRecording ? Date() : nil
        }
    }

    private var controls: some View {
        HStack {
            if pipeline.isPreparing {
                ProgressView().controlSize(.small)
                Text("Preparing…").font(.caption).foregroundStyle(.secondary)
            } else {
                Button(pipeline.isRecording ? "Stop" : "Record") {
                    Task {
                        if pipeline.isRecording {
                            if let session = await pipeline.stop() {
                                sessionStore.save(session)
                            }
                        } else {
                            await pipeline.start()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)

                if pipeline.isRecording, let start = recordingStartedAt {
                    Spacer()
                    TimelineView(.periodic(from: start, by: 1)) { context in
                        Text(formatElapsed(context.date.timeIntervalSince(start)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
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
        .padding(.bottom, 8)
    }

    private func formatElapsed(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

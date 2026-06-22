import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var pipeline: ConversationPipeline
    @ObservedObject var sessionStore: SessionStore
    @ObservedObject var userProfile: UserProfile
    @State private var selectedSession: ConversationSession?
    @State private var selection: Set<ConversationSession.ID> = []
    @State private var isEditingName = false
    @State private var nameDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if pipeline.isRecording {
                liveTranscript
            } else {
                sessionList
            }

            if let error = pipeline.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
            }
        }
        .frame(width: 360, height: 420)
        .sheet(item: $selectedSession) { session in
            SessionDetailView(session: session, sessionStore: sessionStore)
        }
    }

    private var header: some View {
        HStack {
            Text("EarBud").font(.headline)
            Spacer()
            if !selection.isEmpty {
                Button(role: .destructive) {
                    deleteSelected()
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete \(selection.count) conversation\(selection.count == 1 ? "" : "s")")
            }
            if pipeline.isPreparing {
                ProgressView().controlSize(.small)
                Text("Preparing…").font(.caption).foregroundStyle(.secondary)
            } else {
                Button(pipeline.isRecording ? "Stop" : "Record") {
                    Task {
                        if pipeline.isRecording {
                            if let session = await pipeline.stop() {
                                sessionStore.save(session)
                                selectedSession = session
                            }
                        } else {
                            await pipeline.start()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
            Menu {
                Button("Set Your Name…") {
                    nameDraft = userProfile.name
                    isEditingName = true
                }
                Button("Quit EarBud") {
                    NSApplication.shared.terminate(nil)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
        .padding(12)
        .alert("Your Name", isPresented: $isEditingName) {
            TextField("Name", text: $nameDraft)
            Button("Save") {
                let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { userProfile.name = trimmed }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("EarBud labels your speaker turns with this name.")
        }
    }

    private func deleteSelected() {
        sessionStore.delete(ids: selection)
        selection.removeAll()
    }

    private var liveTranscript: some View {
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
                    Text("Listening…").foregroundStyle(.secondary)
                }
                ForEach(pipeline.liveSegments) { segment in
                    VStack(alignment: .leading, spacing: 2) {
                        speakerLabel(for: segment.speakerId)
                        Text(segment.text)
                    }
                }
            }
            .padding(12)
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

    private var sessionList: some View {
        List(selection: $selection) {
            ForEach(sessionStore.sessions) { session in
                VStack(alignment: .leading) {
                    Text(session.title).font(.body)
                    if let summary = session.summary {
                        Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    selectedSession = session
                }
                .tag(session.id)
                .contextMenu {
                    Button("Open") { selectedSession = session }
                    Button("Delete", role: .destructive) { sessionStore.delete(session) }
                }
            }
        }
        .listStyle(.plain)
        .onDeleteCommand { deleteSelected() }
    }
}

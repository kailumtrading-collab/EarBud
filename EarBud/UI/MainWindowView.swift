import SwiftUI

/// The app's primary, openable window: a sidebar of past conversations plus
/// recording controls, with the selected conversation (or the live
/// transcript while recording) shown in the detail pane.
struct MainWindowView: View {
    @ObservedObject var pipeline: ConversationPipeline
    @ObservedObject var sessionStore: SessionStore
    @ObservedObject var userProfile: UserProfile

    @State private var selection: ConversationSession.ID?
    @State private var isEditingName = false
    @State private var nameDraft = ""
    @State private var searchQuery = ""

    private var filteredSessions: [ConversationSession] {
        guard !searchQuery.isEmpty else { return sessionStore.sessions }
        let q = searchQuery.lowercased()
        return sessionStore.sessions.filter {
            $0.title.lowercased().contains(q) ||
            $0.summary?.lowercased().contains(q) == true
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .searchable(text: $searchQuery, placement: .sidebar, prompt: "Search conversations")
        .sheet(isPresented: Binding(
            get: { !userProfile.hasSeenOnboarding },
            set: { if !$0 { userProfile.hasSeenOnboarding = true } }
        )) {
            OnboardingView(userProfile: userProfile)
        }
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

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            RecordingControlBar(pipeline: pipeline) { session in
                sessionStore.save(session)
                selection = session.id
            }
            .padding(12)

            if let error = pipeline.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

            Divider()

            if sessionStore.sessions.isEmpty {
                ContentUnavailableView(
                    "No Conversations Yet",
                    systemImage: "waveform",
                    description: Text("Press Record to capture your first conversation.")
                )
                .frame(maxHeight: .infinity)
            } else if filteredSessions.isEmpty {
                ContentUnavailableView.search(text: searchQuery)
                    .frame(maxHeight: .infinity)
            } else {
                List(selection: $selection) {
                    ForEach(filteredSessions) { session in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(session.title).font(.body)
                                Spacer()
                                if let duration = session.formattedDuration {
                                    Text(duration)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if let summary = session.summary {
                                Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .tag(session.id)
                        .contextMenu {
                            Button("Delete", role: .destructive) { sessionStore.delete(session) }
                        }
                    }
                }
                .listStyle(.sidebar)
                .onDeleteCommand {
                    if let selection {
                        sessionStore.delete(ids: [selection])
                        self.selection = nil
                    }
                }
            }
        }
        .frame(minWidth: 240)
        .toolbar {
            ToolbarItem {
                Image("EarBudLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 26, height: 26)
            }
            ToolbarItem {
                Menu {
                    Button("Set Your Name…") {
                        nameDraft = userProfile.name
                        isEditingName = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if pipeline.isRecording || pipeline.isPreparing {
            LiveTranscriptView(pipeline: pipeline)
        } else if let selection, let session = sessionStore.sessions.first(where: { $0.id == selection }) {
            SessionDetailView(session: session, sessionStore: sessionStore, showsDoneButton: false)
                .id(session.id)
        } else {
            ContentUnavailableView(
                "No Conversation Selected",
                systemImage: "waveform",
                description: Text("Press Record to start listening, or pick a past conversation from the list.")
            )
        }
    }
}

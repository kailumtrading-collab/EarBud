import SwiftUI

struct SessionDetailView: View {
    @State var session: ConversationSession
    @ObservedObject var sessionStore: SessionStore
    var showsDoneButton = true

    @State private var isAnalyzing = false
    @State private var statusMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(session.title).font(.headline)
                Spacer()
                if isAnalyzing {
                    ProgressView().controlSize(.small)
                } else if session.summary == nil {
                    Button("Analyze") { analyze() }
                } else if !session.analyzedWithIntelligence {
                    Button("Re-analyze") { analyze() }
                        .help("This session was summarized with a basic fallback. Re-run now that Apple Intelligence may be available.")
                }
                if showsDoneButton {
                    Button("Done") { dismiss() }
                }
            }
            .padding(12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let summary = session.summary {
                        sectionHeader("Summary")
                        Text(summary)
                    }

                    if !session.rankedSpeakers.isEmpty {
                        sectionHeader("Key speakers")
                        speakerList
                    }

                    if !session.nameDetectionNotices.isEmpty {
                        sectionHeader("Identified speakers")
                        ForEach(session.nameDetectionNotices, id: \.self) { notice in
                            Text("🏷️ \(notice)").font(.callout)
                        }
                    }

                    if !session.detectedEvents.isEmpty {
                        sectionHeader("Detected events")
                        ForEach(session.detectedEvents) { event in
                            eventRow(event)
                        }
                    }

                    if !session.actionItems.isEmpty {
                        sectionHeader("Action items")
                        ForEach(session.actionItems) { item in
                            actionItemRow(item)
                        }
                    }

                    sectionHeader("Transcript")
                    transcriptView

                    HStack {
                        Button(session.savedToNotes ? "Saved to Notes ✓" : "Save to Notes") {
                            saveToNotes()
                        }
                        .disabled(session.savedToNotes)
                    }
                    .padding(.top, 8)

                    if let statusMessage {
                        Text(statusMessage).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(12)
            }
        }
        .frame(minWidth: 420, maxWidth: .infinity, minHeight: 360, maxHeight: .infinity)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(.subheadline.bold()).foregroundStyle(.secondary)
    }

    private var speakerList: some View {
        let totalTalkTime = max(session.rankedSpeakers.reduce(0) { $0 + $1.totalTalkTime }, 1)
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(session.rankedSpeakers) { speaker in
                let percent = Int((speaker.totalTalkTime / totalTalkTime) * 100)
                HStack(spacing: 4) {
                    Circle()
                        .fill(SpeakerColor.color(for: speaker.id))
                        .frame(width: 7, height: 7)
                    Text("\(speaker.displayName) — \(percent)% of talk time")
                        .font(.callout)
                }
            }
        }
    }

    private var transcriptView: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(session.segments) { segment in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(SpeakerColor.color(for: segment.speakerId))
                            .frame(width: 7, height: 7)
                        Text(displayName(for: segment.speakerId))
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                    Text(segment.text)
                        .padding(6)
                        .background(highlightColor(for: segment.category))
                        .cornerRadius(4)
                }
            }
        }
    }

    private func displayName(for speakerId: String) -> String {
        session.speakers.first { $0.id == speakerId }?.displayName
            ?? (speakerId == "Unknown" ? "Unknown speaker" : "Speaker \(speakerId)")
    }

    private func highlightColor(for category: SegmentCategory) -> Color {
        switch category {
        case .businessKey: return Color.yellow.opacity(0.25)
        case .casual: return Color.clear
        case .unclassified: return Color.clear
        }
    }

    private func eventRow(_ event: DetectedEvent) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(event.title)
                if let date = event.date {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(event.addedToCalendar ? "Added ✓" : "Add to Calendar") {
                addToCalendar(event)
            }
            .disabled(event.addedToCalendar)
        }
    }

    private func actionItemRow(_ item: ActionItem) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(item.description)
                if let owner = item.owner {
                    Text("Owner: \(owner)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(item.addedToReminders ? "Added ✓" : "Add to Reminders") {
                addToReminders(item)
            }
            .disabled(item.addedToReminders)
        }
    }

    private func analyze() {
        isAnalyzing = true
        Task {
            let analyzed = await ConversationAnalyzer.analyze(session)
            session = analyzed
            sessionStore.save(analyzed)
            isAnalyzing = false
        }
    }

    private func addToCalendar(_ event: DetectedEvent) {
        Task {
            do {
                guard try await CalendarWriter.addEvent(for: event) else {
                    statusMessage = "Calendar access was denied."
                    return
                }
                if let index = session.detectedEvents.firstIndex(where: { $0.id == event.id }) {
                    session.detectedEvents[index].addedToCalendar = true
                }
                sessionStore.save(session)
                statusMessage = "Added \"\(event.title)\" to Calendar."
            } catch {
                statusMessage = "Couldn't add to Calendar: \(error.localizedDescription)"
            }
        }
    }

    private func addToReminders(_ item: ActionItem) {
        Task {
            do {
                guard try await CalendarWriter.addReminder(for: item) else {
                    statusMessage = "Reminders access was denied."
                    return
                }
                if let index = session.actionItems.firstIndex(where: { $0.id == item.id }) {
                    session.actionItems[index].addedToReminders = true
                }
                sessionStore.save(session)
                statusMessage = "Added \"\(item.description)\" to Reminders."
            } catch {
                statusMessage = "Couldn't add to Reminders: \(error.localizedDescription)"
            }
        }
    }

    private func saveToNotes() {
        do {
            try NotesWriter.saveSession(session)
            session.savedToNotes = true
            sessionStore.save(session)
            statusMessage = "Saved to Notes."
        } catch {
            statusMessage = "Couldn't save to Notes: \(error.localizedDescription)"
        }
    }
}

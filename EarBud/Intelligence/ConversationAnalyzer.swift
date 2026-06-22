import FoundationModels
import Foundation

@Generable
struct ConversationAnalysis: Equatable {
    @Guide(description: "A neutral 1-3 sentence summary of what this conversation was about")
    var summary: String

    @Guide(description: "Every speaker turn from the transcript, in the original order, classified as casual small talk or important business/actionable information")
    var classifiedSegments: [ClassifiedSegmentDraft]

    @Guide(description: "Specific meetings, events, or deadlines mentioned with a date that can be resolved to an absolute date")
    var detectedEvents: [DetectedEventDraft]

    @Guide(description: "Concrete action items or follow-ups someone committed to during the conversation")
    var actionItems: [ActionItemDraft]
}

@Generable
struct ClassifiedSegmentDraft: Equatable {
    var speaker: String
    var isBusinessRelevant: Bool
}

@Generable
struct DetectedEventDraft: Equatable {
    var title: String

    @Guide(description: "Resolved absolute date and time in ISO 8601, e.g. 2026-06-28T15:00:00")
    var isoDateTime: String

    var notes: String?
}

@Generable
struct ActionItemDraft: Equatable {
    var description: String
    var owner: String?
}

/// Classifies casual vs. business-relevant content and extracts a summary,
/// events, and action items. Uses Apple Intelligence on-device via
/// FoundationModels when available; otherwise falls back to a keyword +
/// NSDataDetector heuristic so the app still produces something useful on
/// machines without Apple Intelligence enabled.
enum ConversationAnalyzer {
    static func analyze(_ session: ConversationSession) async -> ConversationSession {
        guard case .available = SystemLanguageModel.default.availability else {
            return heuristicAnalysis(session)
        }
        do {
            let analysis = try await analyzeWithFoundationModels(session)
            return apply(analysis, to: session)
        } catch {
            print("ConversationAnalyzer: FoundationModels analysis failed, falling back: \(error)")
            return heuristicAnalysis(session)
        }
    }

    private static func analyzeWithFoundationModels(_ session: ConversationSession) async throws -> ConversationAnalysis {
        let transcript = session.segments
            .map { "\(displayName(for: $0.speakerId, in: session)): \($0.text)" }
            .joined(separator: "\n")
        let today = DateFormatter.localizedString(from: Date(), dateStyle: .full, timeStyle: .none)

        let instructions = """
        You analyze transcripts of real, in-person conversations. Distinguish casual small talk \
        (weather, food, weekend plans, pleasantries) from business-relevant or actionable content \
        (deadlines, decisions, scheduling, money, contracts, deliverables). Resolve relative dates \
        like "next Tuesday" or "tomorrow" against today's date: \(today). Classify every speaker \
        turn from the transcript, preserving the original order.
        """

        let modelSession = LanguageModelSession(instructions: instructions)
        let prompt = "Analyze this conversation transcript:\n\n\(transcript)"
        let response = try await modelSession.respond(to: prompt, generating: ConversationAnalysis.self)
        return response.content
    }

    private static func apply(_ analysis: ConversationAnalysis, to session: ConversationSession) -> ConversationSession {
        var session = session
        session.analyzedWithIntelligence = true
        session.summary = analysis.summary
        session.segments = applyCategories(to: session.segments, from: analysis.classifiedSegments)
        session.detectedEvents = analysis.detectedEvents.map {
            DetectedEvent(title: $0.title, date: isoDateFormatter.date(from: $0.isoDateTime), notes: $0.notes)
        }
        session.actionItems = analysis.actionItems.map {
            ActionItem(description: $0.description, owner: $0.owner)
        }
        return session
    }

    /// Matches generated classifications back to the original segments positionally.
    /// Skips merging if the model didn't return one classification per segment.
    private static func applyCategories(
        to segments: [TranscriptSegment], from drafts: [ClassifiedSegmentDraft]
    ) -> [TranscriptSegment] {
        guard drafts.count == segments.count else { return segments }
        return zip(segments, drafts).map { segment, draft in
            var segment = segment
            segment.category = draft.isBusinessRelevant ? .businessKey : .casual
            return segment
        }
    }

    private static let businessKeywords = [
        "schedule", "deadline", "invoice", "contract", "budget", "meeting",
        "proposal", "deal", "follow up", "follow-up", "payment", "agreement",
    ]

    private static func heuristicAnalysis(_ session: ConversationSession) -> ConversationSession {
        var session = session
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        var events: [DetectedEvent] = []

        session.segments = session.segments.map { segment in
            var segment = segment
            let lower = segment.text.lowercased()
            segment.category = businessKeywords.contains { lower.contains($0) } ? .businessKey : .casual

            if let detector {
                let range = NSRange(segment.text.startIndex..., in: segment.text)
                for match in detector.matches(in: segment.text, range: range) {
                    if let date = match.date {
                        events.append(
                            DetectedEvent(
                                title: String(segment.text.prefix(60)),
                                date: date,
                                notes: "Detected from \(displayName(for: segment.speakerId, in: session))'s turn"
                            )
                        )
                    }
                }
            }
            return segment
        }

        session.detectedEvents = events
        session.summary = "Apple Intelligence is unavailable on this Mac, so this is a basic summary: "
            + "\(session.segments.count) speaker turns, \(events.count) date mention(s) detected. "
            + "Enable Apple Intelligence in System Settings for a real summary."
        return session
    }

    private static func displayName(for speakerId: String, in session: ConversationSession) -> String {
        session.speakers.first { $0.id == speakerId }?.displayName
            ?? (speakerId == "Unknown" ? "Unknown speaker" : "Speaker \(speakerId)")
    }

    private static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.timeZone = .current
        return formatter
    }()
}

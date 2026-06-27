import Foundation

struct ConversationSession: Identifiable, Codable, Hashable {
    var id = UUID()
    var startedAt: Date
    var endedAt: Date?
    var speakers: [Speaker] = []
    var segments: [TranscriptSegment] = []
    var summary: String?
    var detectedEvents: [DetectedEvent] = []
    var actionItems: [ActionItem] = []
    var nameDetectionNotices: [String] = []
    var customTitle: String?
    var savedToNotes: Bool = false
    var analyzedWithIntelligence: Bool = false

    var title: String {
        if let custom = customTitle, !custom.isEmpty { return custom }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Conversation — \(formatter.string(from: startedAt))"
    }

    var rankedSpeakers: [Speaker] {
        speakers.sorted { $0.totalTalkTime > $1.totalTalkTime }
    }
}

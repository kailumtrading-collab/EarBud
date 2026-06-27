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

    var formattedDuration: String? {
        guard let end = endedAt else { return nil }
        let total = max(0, Int(end.timeIntervalSince(startedAt)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }
}

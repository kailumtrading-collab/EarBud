import Foundation

enum SegmentCategory: String, Codable {
    case casual
    case businessKey
    case unclassified
}

struct TranscriptSegment: Identifiable, Codable, Hashable {
    var id = UUID()
    var speakerId: String
    var text: String
    var startTime: TimeInterval
    var endTime: TimeInterval
    var category: SegmentCategory = .unclassified
}

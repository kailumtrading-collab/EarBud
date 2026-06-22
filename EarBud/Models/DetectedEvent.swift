import Foundation

struct DetectedEvent: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var date: Date?
    var notes: String?
    var addedToCalendar: Bool = false
}

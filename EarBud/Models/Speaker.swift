import Foundation

struct Speaker: Identifiable, Codable, Hashable {
    let id: String
    var displayName: String
    var totalTalkTime: TimeInterval = 0

    init(id: String, displayName: String? = nil) {
        self.id = id
        self.displayName = displayName ?? id
    }
}

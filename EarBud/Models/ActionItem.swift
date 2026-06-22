import Foundation

struct ActionItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var description: String
    var owner: String?
    var addedToReminders: Bool = false
}

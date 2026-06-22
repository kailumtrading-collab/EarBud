import Foundation
import Combine

/// The device owner's own name, used to label their speaker turns instead of
/// a generic "Speaker 1". Defaults to the macOS account's full name so it
/// works out of the box, but is editable from the menu.
final class UserProfile: ObservableObject {
    @Published var name: String {
        didSet { UserDefaults.standard.set(name, forKey: Self.key) }
    }

    private static let key = "EarBud.userName"

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.key)
        name = (stored?.isEmpty == false) ? stored! : NSFullUserName()
    }
}

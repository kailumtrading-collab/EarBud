import Foundation
import Combine

/// The device owner's own name, used to label their speaker turns instead of
/// a generic "Speaker 1". Defaults to the macOS account's full name so it
/// works out of the box, but is editable from the menu.
final class UserProfile: ObservableObject {
    @Published var name: String {
        didSet { UserDefaults.standard.set(name, forKey: Self.nameKey) }
    }
    @Published var hasSeenOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasSeenOnboarding, forKey: Self.onboardingKey) }
    }

    private static let nameKey = "EarBud.userName"
    private static let onboardingKey = "EarBud.hasSeenOnboarding"

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.nameKey)
        name = (stored?.isEmpty == false) ? stored! : NSFullUserName()
        hasSeenOnboarding = UserDefaults.standard.bool(forKey: Self.onboardingKey)
    }
}

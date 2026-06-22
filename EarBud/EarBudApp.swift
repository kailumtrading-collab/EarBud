import SwiftUI

@main
struct EarBudApp: App {
    @StateObject private var userProfile: UserProfile
    @StateObject private var pipeline: ConversationPipeline
    @StateObject private var sessionStore = SessionStore()

    init() {
        let profile = UserProfile()
        _userProfile = StateObject(wrappedValue: profile)
        _pipeline = StateObject(wrappedValue: ConversationPipeline(userProfile: profile))
    }

    var body: some Scene {
        WindowGroup {
            MainWindowView(pipeline: pipeline, sessionStore: sessionStore, userProfile: userProfile)
        }
        .defaultSize(width: 760, height: 560)
    }
}

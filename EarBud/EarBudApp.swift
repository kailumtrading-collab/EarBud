import SwiftUI
import UserNotifications

@main
struct EarBudApp: App {
    @StateObject private var userProfile: UserProfile
    @StateObject private var pipeline: ConversationPipeline
    @StateObject private var sessionStore = SessionStore()

    init() {
        let profile = UserProfile()
        _userProfile = StateObject(wrappedValue: profile)
        _pipeline = StateObject(wrappedValue: ConversationPipeline(userProfile: profile))
        Task {
            try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            MainWindowView(pipeline: pipeline, sessionStore: sessionStore, userProfile: userProfile)
        }
        .defaultSize(width: 760, height: 560)

        MenuBarExtra {
            MenuBarView(pipeline: pipeline, sessionStore: sessionStore)
        } label: {
            Image(systemName: pipeline.isRecording ? "waveform.circle.fill" : "waveform.circle")
        }
        .menuBarExtraStyle(.window)
    }
}

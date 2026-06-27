import SwiftUI

struct OnboardingView: View {
    @ObservedObject var userProfile: UserProfile
    @State private var nameDraft: String

    init(userProfile: UserProfile) {
        self.userProfile = userProfile
        _nameDraft = State(initialValue: userProfile.name)
    }

    var body: some View {
        VStack(spacing: 24) {
            Image("EarBudLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)

            VStack(spacing: 8) {
                Text("Welcome to EarBud")
                    .font(.title2.bold())
                Text("EarBud transcribes conversations in real time and identifies who's speaking. Enter your name so it can label your turns correctly.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            TextField("Your name", text: $nameDraft)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)

            HStack(spacing: 12) {
                Button("Skip") { finish() }
                    .foregroundStyle(.secondary)
                Button("Get Started") {
                    let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { userProfile.name = trimmed }
                    finish()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(32)
        .frame(width: 380)
        .interactiveDismissDisabled()
    }

    private func finish() {
        userProfile.hasSeenOnboarding = true
    }
}

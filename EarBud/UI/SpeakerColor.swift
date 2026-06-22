import SwiftUI

/// Gives each diarized speaker a consistent, distinct color across the live
/// transcript and saved session views, so turns are visually separable at a
/// glance without reading every label.
enum SpeakerColor {
    private static let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .brown]

    static func color(for speakerId: String) -> Color {
        guard speakerId != "Unknown" else { return .gray }
        return palette[Int(stableHash(speakerId) % UInt64(palette.count))]
    }

    /// `String.hashValue` is seeded randomly per process launch, so the same
    /// speaker would get a different color every time the app restarts. Use
    /// a fixed-algorithm hash (FNV-1a) instead so colors stay stable across
    /// relaunches when reopening a saved session.
    private static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}

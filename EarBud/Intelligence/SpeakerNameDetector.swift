import Foundation
import NaturalLanguage

/// Heuristically spots names exchanged mid-conversation in a finalized
/// transcript line, so a speaker can be relabeled with their real name
/// instead of a generic "Speaker 2" once they're introduced.
enum SpeakerNameDetector {
    /// "I'm Sarah", "my name's Sarah Connor", "call me Sarah" — attributed to
    /// whoever is currently speaking.
    private static let selfIntroPattern = try! NSRegularExpression(
        pattern: #"\b(?:my name(?:'s| is)|i am|i'm|call me|this is)\s+([A-Z][a-zA-Z'-]+(?:\s+[A-Z][a-zA-Z'-]+){0,2})"#,
        options: [.caseInsensitive]
    )

    /// "Hi Sarah", "hey Sarah, ..." — attributed to whichever *other* speaker
    /// was most recently active, since you don't greet yourself.
    private static let addressPattern = try! NSRegularExpression(
        pattern: #"\b(?:hi|hey|hello|morning|afternoon|evening)[,]?\s+([A-Z][a-zA-Z'-]+)\b"#,
        options: [.caseInsensitive]
    )

    static func detectSelfIntroduction(in text: String) -> String? {
        firstNameMatch(of: selfIntroPattern, in: text)
    }

    static func detectAddressedName(in text: String) -> String? {
        firstNameMatch(of: addressPattern, in: text)
    }

    private static func firstNameMatch(of pattern: NSRegularExpression, in text: String) -> String? {
        let fullRange = NSRange(text.startIndex..., in: text)
        guard let match = pattern.firstMatch(in: text, range: fullRange),
              let nameRange = Range(match.range(at: 1), in: text) else { return nil }
        guard looksLikeName(text, in: nameRange) else { return nil }
        return String(text[nameRange])
    }

    /// Cross-checks the regex capture against NaturalLanguage's contextual
    /// name tagger to filter out false positives like "I'm good" or "hey there".
    private static func looksLikeName(_ text: String, in range: Range<String.Index>) -> Bool {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var found = false
        tagger.enumerateTags(in: range, unit: .word, scheme: .nameType, options: [.joinNames]) { tag, _ in
            if tag == .personalName { found = true }
            return true
        }
        return found
    }
}

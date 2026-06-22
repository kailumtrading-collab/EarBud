import Foundation

enum NotesWriter {
    enum NotesError: Error {
        case scriptFailed(String)
    }

    private static let folderName = "EarBud Conversations"

    /// Files a note containing the summary, key speakers, and full transcript
    /// into a "EarBud Conversations" folder in Notes.app (created if missing).
    static func saveSession(_ session: ConversationSession) throws {
        let body = noteBody(for: session)
        let script = """
        tell application "Notes"
            if not (exists folder "\(folderName)") then
                make new folder with properties {name:"\(folderName)"}
            end if
            tell folder "\(folderName)"
                make new note with properties {name:"\(escape(session.title))", body:"\(escape(body))"}
            end tell
        end tell
        """

        var errorInfo: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            throw NotesError.scriptFailed("Could not compile AppleScript")
        }
        appleScript.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
            throw NotesError.scriptFailed(message)
        }
    }

    private static func noteBody(for session: ConversationSession) -> String {
        var lines: [String] = []
        if let summary = session.summary {
            lines.append("Summary: \(summary)")
            lines.append("")
        }
        if !session.speakers.isEmpty {
            lines.append("Key speakers:")
            for speaker in session.rankedSpeakers {
                let minutes = Int(speaker.totalTalkTime / 60)
                lines.append("- \(speaker.displayName) (~\(minutes) min)")
            }
            lines.append("")
        }
        if !session.detectedEvents.isEmpty {
            lines.append("Detected events:")
            for event in session.detectedEvents {
                lines.append("- \(event.title)")
            }
            lines.append("")
        }
        if !session.actionItems.isEmpty {
            lines.append("Action items:")
            for item in session.actionItems {
                lines.append("- \(item.description)")
            }
            lines.append("")
        }
        lines.append("Transcript:")
        for segment in session.segments {
            lines.append("\(segment.speakerId): \(segment.text)")
        }
        return lines.joined(separator: "\n")
    }

    /// Escapes characters that would otherwise break the AppleScript string literal.
    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

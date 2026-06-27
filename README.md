# EarBud

A macOS menu-bar app that listens to in-person conversations, transcribes them in real time, identifies who's speaking, and turns what was said into calendar events, reminders, and Notes — entirely on-device.

## What it does

- **Live transcription** — uses Apple's on-device `SpeechAnalyzer`/`SpeechTranscriber` (macOS 26+) to transcribe mic audio as you speak
- **System audio** — captures the other side of video/voice calls via a Core Audio process tap alongside the mic
- **Speaker diarization** — identifies who said what using [FluidAudio](https://github.com/FluidInference/FluidAudio)'s CoreML pipeline; detects names exchanged during the conversation ("I'm Sarah", "Hi Sarah") to label speakers automatically
- **Post-session analysis** — summarizes the conversation, classifies casual vs. business-relevant turns, and extracts detected events and action items using Apple Intelligence (FoundationModels); falls back to a keyword + NSDataDetector heuristic when Apple Intelligence is unavailable
- **Integrations** — add detected events to Calendar, action items to Reminders, and full session transcripts to Notes

All processing is on-device. No audio or transcripts leave your Mac.

## Requirements

- macOS 26 or later
- Apple Intelligence enabled for full analysis (System Settings → Apple Intelligence & Siri)
- Xcode 26+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Getting started

```bash
git clone https://github.com/kailumtrading-collab/EarBud.git
cd EarBud
xcodegen generate
open EarBud.xcodeproj
```

Build and run in Xcode. On first launch you'll be prompted for microphone access, and optionally Screen & System Audio Recording access (for capturing system audio).

## Permissions

| Permission | Purpose |
|---|---|
| Microphone | Transcribe in-person speech |
| Screen & System Audio Recording | Hear the far side of calls |
| Calendars | Add detected meetings |
| Reminders | Add detected action items |
| Apple Events | Save session summaries to Notes |

## Project structure

```
EarBud/
├── Audio/           AudioCaptureEngine, SystemAudioTapEngine, AudioMixer
├── Transcription/   LiveTranscriber (SpeechAnalyzer wrapper)
├── Diarization/     SpeakerDiarizer (FluidAudio wrapper)
├── Pipeline/        ConversationPipeline — fuses transcript + diarization by timestamp
├── Intelligence/    ConversationAnalyzer (FoundationModels), SpeakerNameDetector
├── Integrations/    CalendarWriter (EventKit), NotesWriter (AppleScript)
├── Persistence/     SessionStore, UserProfile
├── Models/          ConversationSession, TranscriptSegment, Speaker, …
└── UI/              MainWindowView, LiveTranscriptView, SessionDetailView, …
```

## Regenerating the Xcode project

The project is managed with XcodeGen. After editing `project.yml` (adding files, changing settings, etc.), run:

```bash
xcodegen generate
```

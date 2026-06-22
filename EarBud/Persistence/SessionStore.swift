import Foundation
import Combine

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [ConversationSession] = []

    private let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = appSupport.appendingPathComponent("EarBud/Sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        load()
    }

    func save(_ session: ConversationSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.insert(session, at: 0)
        }
        persist(session)
    }

    func delete(ids: Set<ConversationSession.ID>) {
        sessions.removeAll { ids.contains($0.id) }
        for id in ids {
            try? FileManager.default.removeItem(at: fileURL(for: id))
        }
    }

    func delete(_ session: ConversationSession) {
        delete(ids: [session.id])
    }

    private func fileURL(for id: ConversationSession.ID) -> URL {
        directory.appendingPathComponent("\(id).json")
    }

    private func persist(_ session: ConversationSession) {
        guard let data = try? encoder.encode(session) else { return }
        try? data.write(to: fileURL(for: session.id), options: .atomic)
    }

    private func load() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        let loaded = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> ConversationSession? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(ConversationSession.self, from: data)
            }
            .sorted { $0.startedAt > $1.startedAt }
        sessions = loaded
    }
}

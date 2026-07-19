import Foundation

actor ConversationStore {
    private let directories: AppDirectories
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(root: URL? = nil) {
        directories = AppDirectories(root: root)
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() throws -> [Conversation] {
        try directories.prepare()
        guard FileManager.default.fileExists(atPath: directories.conversations.path) else {
            return []
        }
        let data = try Data(contentsOf: directories.conversations)
        return try decoder.decode([Conversation].self, from: data)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ conversations: [Conversation]) throws {
        try directories.prepare()
        let data = try encoder.encode(conversations)
        try data.write(to: directories.conversations, options: .atomic)
    }
}

import Foundation

enum ChatRole: String, Codable, Sendable {
    case system
    case user
    case assistant
}

struct ChatMessage: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let role: ChatRole
    var text: String
    let createdAt: Date
    var sources: [WebSource]?
    var reasoning: String?
    var attachments: [MediaAttachment]?

    init(
        id: UUID = UUID(),
        role: ChatRole,
        text: String,
        createdAt: Date = Date(),
        sources: [WebSource]? = nil,
        reasoning: String? = nil,
        attachments: [MediaAttachment]? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.sources = sources
        self.reasoning = reasoning
        self.attachments = attachments
    }
}

enum MediaKind: String, Codable, Hashable, Sendable {
    case image
    case audio

    var label: String {
        switch self {
        case .image: "Image"
        case .audio: "Audio"
        }
    }
}

struct MediaAttachment: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let kind: MediaKind
    let fileName: String
    let displayName: String
    let byteCount: Int64

    init(
        id: UUID = UUID(),
        kind: MediaKind,
        fileName: String,
        displayName: String,
        byteCount: Int64
    ) {
        self.id = id
        self.kind = kind
        self.fileName = fileName
        self.displayName = displayName
        self.byteCount = byteCount
    }
}

struct WebSource: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let title: String
    let url: URL
    let snippet: String

    init(id: UUID = UUID(), title: String, url: URL, snippet: String) {
        self.id = id
        self.title = title
        self.url = url
        self.snippet = snippet
    }

    var host: String {
        url.host?.replacingOccurrences(of: "www.", with: "") ?? url.host ?? "Source"
    }
}

struct Conversation: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    var modelID: UUID?
    let createdAt: Date
    var updatedAt: Date
    var messages: [ChatMessage]

    init(
        id: UUID = UUID(),
        title: String = "New conversation",
        modelID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        messages: [ChatMessage] = []
    ) {
        self.id = id
        self.title = title
        self.modelID = modelID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }

    var preview: String {
        messages.last(where: { !$0.text.isEmpty })?.text ?? "No messages yet"
    }
}

enum ReasoningMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case automatic
    case enabled
    case disabled

    var id: String { rawValue }
}

enum ReasoningEffort: String, CaseIterable, Codable, Identifiable, Sendable {
    case low
    case medium
    case high

    var id: String { rawValue }
}

enum SamplingPreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case precise
    case balanced
    case creative
    case custom

    var id: String { rawValue }
}

struct GenerationSettings: Codable, Equatable, Sendable {
    var contextSize = 4_096
    var maximumNewTokens = 512
    var temperature: Float = 0.7
    var topP: Float = 0.9
    var topK: Int32 = 40
    var minP: Float = 0.05
    var typicalP: Float = 1.0
    var repeatPenalty: Float = 1.1
    var repeatLastTokens: Int32 = 64
    var frequencyPenalty: Float = 0
    var presencePenalty: Float = 0
    var seed: UInt32?
    var batchSize = 512
    var threadCount = 0
    var gpuLayers = -1
    var useMemoryMap = true
    var lockMemory = false
    var flashAttention = true
    var reasoningMode = ReasoningMode.automatic
    var reasoningEffort = ReasoningEffort.medium
    var samplingPreset = SamplingPreset.balanced
    var stopSequences: [String] = []
    var imageMaximumTokens = 1_024
    var systemPrompt = "You are a helpful, concise assistant running privately on the user's device."

    static let `default` = GenerationSettings()

    mutating func apply(_ preset: SamplingPreset) {
        guard preset != .custom else {
            samplingPreset = .custom
            return
        }

        typicalP = 1.0
        repeatPenalty = 1.1
        repeatLastTokens = 64
        frequencyPenalty = 0
        presencePenalty = 0
        switch preset {
        case .precise:
            temperature = 0.2
            topP = 0.8
            topK = 30
            minP = 0.05
        case .balanced:
            temperature = 0.7
            topP = 0.9
            topK = 40
            minP = 0.05
        case .creative:
            temperature = 1.0
            topP = 0.95
            topK = 64
            minP = 0.02
        case .custom:
            break
        }
        samplingPreset = preset
    }

    func matches(_ preset: SamplingPreset) -> Bool {
        guard preset != .custom else { return false }
        var candidate = GenerationSettings.default
        candidate.apply(preset)
        return temperature == candidate.temperature
            && topP == candidate.topP
            && topK == candidate.topK
            && minP == candidate.minP
            && typicalP == candidate.typicalP
            && repeatPenalty == candidate.repeatPenalty
            && repeatLastTokens == candidate.repeatLastTokens
            && frequencyPenalty == candidate.frequencyPenalty
            && presencePenalty == candidate.presencePenalty
    }
}

struct RuntimeInfo: Equatable, Sendable {
    let modelDescription: String
    let parameterCount: UInt64
    let modelBytes: UInt64
    let contextSize: Int
    let trainedContextSize: Int
    let capabilities: ModelCapabilities
    let metadata: [String: String]

    var formattedParameters: String {
        let billions = Double(parameterCount) / 1_000_000_000
        return billions >= 0.1
            ? String(format: "%.1fB", billions)
            : String(format: "%.0fM", Double(parameterCount) / 1_000_000)
    }
}

enum GenerationEvent: Equatable, Sendable {
    case token(String)
    case reasoningToken(String)
    case metrics(tokensPerSecond: Double, generatedTokens: Int)
}

struct InferenceAttachment: Sendable {
    let kind: MediaKind
    let url: URL
}

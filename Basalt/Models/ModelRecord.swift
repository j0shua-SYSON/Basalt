import Foundation

enum ModelOrigin: String, Codable, CaseIterable, Sendable {
    case files
    case huggingFace

    var label: String {
        switch self {
        case .files: "Files"
        case .huggingFace: "Hugging Face"
        }
    }
}

struct ModelRecord: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    let fileName: String
    let byteCount: Int64
    let importedAt: Date
    var lastUsedAt: Date?
    let origin: ModelOrigin
    let sourceURL: URL?
    var projectorFileName: String? = nil

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    var quantization: String? {
        let uppercased = fileName.uppercased()
        let known = [
            "IQ1_S", "IQ1_M", "IQ2_XXS", "IQ2_XS", "IQ2_S", "IQ2_M",
            "IQ3_XXS", "IQ3_XS", "IQ3_S", "IQ3_M", "IQ4_XS", "IQ4_NL",
            "Q2_K", "Q3_K_S", "Q3_K_M", "Q3_K_L", "Q4_0", "Q4_1",
            "Q4_K_S", "Q4_K_M", "Q5_0", "Q5_1", "Q5_K_S", "Q5_K_M",
            "Q6_K", "Q8_0", "F16", "BF16", "F32"
        ]
        return known.first(where: uppercased.contains)
    }
}

enum ModelCapability: String, CaseIterable, Codable, Hashable, Sendable {
    case reasoning
    case vision
    case audio
}

enum ThinkingControl: String, Codable, Hashable, Sendable {
    case none
    case qwenSlashCommand
    case glmSlashCommand
    case closingTag
    case reasoningEffort
}

struct ModelCapabilities: Equatable, Sendable {
    var supportsVision = false
    var supportsAudio = false
    var thinkingControl = ThinkingControl.none

    var supportsThinking: Bool { thinkingControl != .none }
    var all: Set<ModelCapability> {
        var result: Set<ModelCapability> = []
        if supportsThinking { result.insert(.reasoning) }
        if supportsVision { result.insert(.vision) }
        if supportsAudio { result.insert(.audio) }
        return result
    }
}

struct ImportProgress: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case preparing
        case downloading
        case validating
        case copying
        case finished
    }

    var phase: Phase
    var fraction: Double?
    var completedBytes: Int64 = 0
    var totalBytes: Int64?

    var label: String {
        switch phase {
        case .preparing: "Preparing import"
        case .downloading: "Downloading model"
        case .validating: "Checking GGUF"
        case .copying: "Saving model"
        case .finished: "Imported"
        }
    }
}

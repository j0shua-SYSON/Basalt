import Foundation

enum ModelCapabilityDetector {
    static func thinkingControl(
        metadata: [String: String],
        chatTemplate: String
    ) -> ThinkingControl {
        let identity = ([
            metadata["general.name"],
            metadata["general.architecture"],
            metadata["general.basename"],
            chatTemplate
        ].compactMap { $0 }.joined(separator: " ")).lowercased()

        if identity.contains("reasoning_effort") {
            return .reasoningEffort
        }
        if identity.contains("qwen3") || identity.contains("/no_think") {
            return .qwenSlashCommand
        }
        if identity.contains("/nothink") || identity.contains("glm-4") {
            return .glmSlashCommand
        }
        if identity.contains("enable_thinking")
            || identity.contains("thinking_budget")
            || identity.contains("<think>")
            || identity.contains("deepseek-r1")
            || identity.contains("deepseek r1")
            || identity.contains("qwq")
            || identity.contains("magistral") {
            return .closingTag
        }
        return .none
    }
}

import Foundation

protocol InferenceServing: Sendable {
    func loadModel(
        at url: URL,
        projectorAt projectorURL: URL?,
        settings: GenerationSettings
    ) async throws -> RuntimeInfo
    func unloadModel() async
    func generate(
        messages: [ChatMessage],
        attachments: [InferenceAttachment],
        settings: GenerationSettings
    ) async -> AsyncThrowingStream<GenerationEvent, Error>
}

actor DemoInferenceEngine: InferenceServing {
    private var loaded = false

    func loadModel(
        at url: URL,
        projectorAt projectorURL: URL?,
        settings: GenerationSettings
    ) async throws -> RuntimeInfo {
        loaded = true
        try await Task.sleep(nanoseconds: 180_000_000)
        return RuntimeInfo(
            modelDescription: "Basalt Demo 3B Q4_K_M",
            parameterCount: 3_210_000_000,
            modelBytes: 2_040_000_000,
            contextSize: settings.contextSize,
            trainedContextSize: 32_768,
            capabilities: ModelCapabilities(
                supportsVision: true,
                supportsAudio: true,
                thinkingControl: .qwenSlashCommand
            ),
            metadata: [
                "general.architecture": "qwen3",
                "general.name": "Basalt Demo 3B"
            ]
        )
    }

    func unloadModel() {
        loaded = false
    }

    func generate(
        messages: [ChatMessage],
        attachments: [InferenceAttachment],
        settings: GenerationSettings
    ) -> AsyncThrowingStream<GenerationEvent, Error> {
        let response = "Everything here stays on your device. Basalt streams this response directly from the selected GGUF model, with no account and no cloud relay."
        return AsyncThrowingStream { continuation in
            let task = Task {
                let started = DispatchTime.now().uptimeNanoseconds
                var count = 0
                for word in response.split(separator: " ", omittingEmptySubsequences: false) {
                    do {
                        try Task.checkCancellation()
                        try await Task.sleep(nanoseconds: 42_000_000)
                    } catch {
                        continuation.finish(throwing: error)
                        return
                    }
                    count += 1
                    continuation.yield(.token((count == 1 ? "" : " ") + word))
                    if count.isMultiple(of: 4) {
                        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
                        continuation.yield(.metrics(
                            tokensPerSecond: elapsed > 0 ? Double(count) / elapsed : 0,
                            generatedTokens: count
                        ))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

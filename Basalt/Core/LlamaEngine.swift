import Foundation
@preconcurrency import llama

enum LlamaEngineError: LocalizedError {
    case modelLoadFailed
    case contextCreationFailed
    case projectorLoadFailed
    case modelNotLoaded
    case emptyPrompt
    case decodeFailed
    case contextTooSmall
    case visionUnsupported
    case audioUnsupported
    case attachmentDecodeFailed

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed:
            "llama.cpp could not load this model. It may be damaged or too large for this device."
        case .contextCreationFailed:
            "The model loaded, but Basalt could not allocate its context. Try a smaller context or model."
        case .projectorLoadFailed:
            "The multimodal projector does not match this text model or could not fit in memory."
        case .modelNotLoaded:
            "Choose and load a model before sending a message."
        case .emptyPrompt:
            "The conversation did not produce any model tokens."
        case .decodeFailed:
            "The model stopped while evaluating tokens."
        case .contextTooSmall:
            "The prompt and attachments do not fit in the selected context window."
        case .visionUnsupported:
            "This model and projector do not support image input."
        case .audioUnsupported:
            "This model and projector do not support audio input."
        case .attachmentDecodeFailed:
            "llama.cpp could not decode one of the attached files."
        }
    }
}

actor LlamaEngine: InferenceServing {
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var vocabulary: OpaquePointer?
    private var multimodalContext: OpaquePointer?
    private var loadedURL: URL?
    private var loadedProjectorURL: URL?
    private var loadedConfiguration: RuntimeLoadConfiguration?
    private var info: RuntimeInfo?

    init() {
        llama_backend_init()
    }

    deinit {
        if let multimodalContext { mtmd_free(multimodalContext) }
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
        llama_backend_free()
    }

    func loadModel(
        at url: URL,
        projectorAt projectorURL: URL?,
        settings: GenerationSettings
    ) throws -> RuntimeInfo {
        let configuration = RuntimeLoadConfiguration(settings: settings)
        if loadedURL == url,
           loadedProjectorURL == projectorURL,
           loadedConfiguration == configuration,
           let info {
            return info
        }

        unloadPointers()

        var modelParameters = llama_model_default_params()
        modelParameters.use_mmap = settings.useMemoryMap
        modelParameters.use_mlock = settings.lockMemory
#if targetEnvironment(simulator)
        modelParameters.n_gpu_layers = 0
#else
        modelParameters.n_gpu_layers = Int32(clamping: settings.gpuLayers)
#endif

        guard let loadedModel = llama_model_load_from_file(url.path, modelParameters) else {
            throw LlamaEngineError.modelLoadFailed
        }

        let threads = Self.threadCount(from: settings)
        let batchSize = min(max(32, settings.batchSize), max(32, settings.contextSize))
        var contextParameters = llama_context_default_params()
        contextParameters.n_ctx = UInt32(max(512, settings.contextSize))
        contextParameters.n_batch = UInt32(batchSize)
        contextParameters.n_ubatch = UInt32(batchSize)
        contextParameters.n_seq_max = 1
        contextParameters.n_threads = Int32(threads)
        contextParameters.n_threads_batch = Int32(threads)
        contextParameters.flash_attn_type = settings.flashAttention
            ? LLAMA_FLASH_ATTN_TYPE_ENABLED
            : LLAMA_FLASH_ATTN_TYPE_DISABLED

        guard let loadedContext = llama_init_from_model(loadedModel, contextParameters) else {
            llama_model_free(loadedModel)
            throw LlamaEngineError.contextCreationFailed
        }

        var loadedMultimodalContext: OpaquePointer?
        if let projectorURL {
            var parameters = mtmd_context_params_default()
#if targetEnvironment(simulator)
            parameters.use_gpu = false
#else
            parameters.use_gpu = settings.gpuLayers != 0
#endif
            parameters.n_threads = Int32(threads)
            parameters.image_max_tokens = Int32(clamping: settings.imageMaximumTokens)
            parameters.batch_max_tokens = Int32(batchSize)
            parameters.flash_attn_type = contextParameters.flash_attn_type
            loadedMultimodalContext = mtmd_init_from_file(projectorURL.path, loadedModel, parameters)
            guard loadedMultimodalContext != nil else {
                llama_free(loadedContext)
                llama_model_free(loadedModel)
                throw LlamaEngineError.projectorLoadFailed
            }
        }

        let metadata = Self.modelMetadata(loadedModel)
        var capabilities = Self.detectCapabilities(metadata: metadata, model: loadedModel)
        if let loadedMultimodalContext {
            capabilities.supportsVision = mtmd_support_vision(loadedMultimodalContext)
            capabilities.supportsAudio = mtmd_support_audio(loadedMultimodalContext)
        }

        model = loadedModel
        context = loadedContext
        vocabulary = llama_model_get_vocab(loadedModel)
        multimodalContext = loadedMultimodalContext
        loadedURL = url
        loadedProjectorURL = projectorURL
        loadedConfiguration = configuration
        let runtime = runtimeInfo(
            model: loadedModel,
            context: loadedContext,
            capabilities: capabilities,
            metadata: metadata
        )
        info = runtime
        return runtime
    }

    func unloadModel() {
        unloadPointers()
    }

    func generate(
        messages: [ChatMessage],
        attachments: [InferenceAttachment],
        settings: GenerationSettings
    ) -> AsyncThrowingStream<GenerationEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try self.runGeneration(
                        messages: messages,
                        attachments: attachments,
                        settings: settings,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func runGeneration(
        messages: [ChatMessage],
        attachments: [InferenceAttachment],
        settings: GenerationSettings,
        continuation: AsyncThrowingStream<GenerationEvent, Error>.Continuation
    ) throws {
        guard let model, let context, let vocabulary, let info else {
            throw LlamaEngineError.modelNotLoaded
        }
        if attachments.contains(where: { $0.kind == .image }) && !info.capabilities.supportsVision {
            throw LlamaEngineError.visionUnsupported
        }
        if attachments.contains(where: { $0.kind == .audio }) && !info.capabilities.supportsAudio {
            throw LlamaEngineError.audioUnsupported
        }

        llama_memory_clear(llama_get_memory(context), true)

        let preparedMessages = prepareMessages(
            messages,
            attachmentCount: attachments.count,
            capabilities: info.capabilities,
            settings: settings
        )
        var prompt = applyChatTemplate(
            model: model,
            messages: preparedMessages,
            systemPrompt: settings.systemPrompt,
            reasoningEffort: settings.reasoningEffort,
            thinkingControl: info.capabilities.thinkingControl
        )
        if settings.reasoningMode == .disabled && info.capabilities.thinkingControl == .closingTag {
            prompt += "</think>"
        }

        let contextCapacity = Int(llama_n_ctx(context))
        let generationBudget = min(settings.maximumNewTokens, max(1, contextCapacity / 2))
        let batchCapacity = min(max(32, settings.batchSize), contextCapacity)
        var batch = llama_batch_init(Int32(batchCapacity), 0, 1)
        defer { llama_batch_free(batch) }

        let promptEvaluation: (position: llama_pos, tokenCount: Int)
        if attachments.isEmpty {
            promptEvaluation = try evaluateTextPrompt(
                prompt,
                vocabulary: vocabulary,
                context: context,
                batch: &batch,
                contextCapacity: contextCapacity,
                generationBudget: generationBudget,
                batchCapacity: batchCapacity
            )
        } else {
            guard let multimodalContext else { throw LlamaEngineError.attachmentDecodeFailed }
            promptEvaluation = try evaluateMultimodalPrompt(
                prompt,
                attachments: attachments,
                multimodalContext: multimodalContext,
                context: context,
                contextCapacity: contextCapacity,
                generationBudget: generationBudget,
                batchCapacity: batchCapacity
            )
        }

        let sampler = makeSampler(settings: settings)
        defer { llama_sampler_free(sampler) }

        let started = DispatchTime.now().uptimeNanoseconds
        var generated = 0
        var position = promptEvaluation.position
        var pendingUTF8: [CChar] = []
        var stopFilter = StopSequenceFilter(sequences: settings.stopSequences)
        var reasoningParser = ReasoningStreamParser()
        var shouldStop = false

        func emit(_ fragment: String) {
            for part in reasoningParser.consume(fragment) {
                continuation.yield(part.isReasoning ? .reasoningToken(part.text) : .token(part.text))
            }
        }

        while generated < generationBudget,
              promptEvaluation.tokenCount + generated < contextCapacity,
              !shouldStop {
            try Task.checkCancellation()
            let token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocabulary, token) { break }

            pendingUTF8.append(contentsOf: tokenPiece(token, vocabulary: vocabulary))
            if let fragment = String(validatingUTF8: pendingUTF8 + [0]) {
                pendingUTF8.removeAll(keepingCapacity: true)
                let filtered = stopFilter.consume(fragment)
                emit(filtered.text)
                shouldStop = filtered.shouldStop
            }
            if shouldStop { break }

            batch.clear()
            batch.add(token, position: position, logits: true)
            guard llama_decode(context, batch) == 0 else {
                throw LlamaEngineError.decodeFailed
            }

            position += 1
            generated += 1
            if generated.isMultiple(of: 8) {
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
                continuation.yield(.metrics(
                    tokensPerSecond: elapsed > 0 ? Double(generated) / elapsed : 0,
                    generatedTokens: generated
                ))
            }
        }

        if !pendingUTF8.isEmpty && !shouldStop {
            let bytes = pendingUTF8.map { UInt8(bitPattern: $0) }
            emit(stopFilter.consume(String(decoding: bytes, as: UTF8.self)).text)
        }
        if !shouldStop { emit(stopFilter.finish()) }
        for part in reasoningParser.finish() {
            continuation.yield(part.isReasoning ? .reasoningToken(part.text) : .token(part.text))
        }

        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
        continuation.yield(.metrics(
            tokensPerSecond: elapsed > 0 ? Double(generated) / elapsed : 0,
            generatedTokens: generated
        ))
    }

    private func evaluateTextPrompt(
        _ prompt: String,
        vocabulary: OpaquePointer,
        context: OpaquePointer,
        batch: inout llama_batch,
        contextCapacity: Int,
        generationBudget: Int,
        batchCapacity: Int
    ) throws -> (position: llama_pos, tokenCount: Int) {
        var promptTokens = try tokenize(prompt, vocabulary: vocabulary)
        let maximumPromptTokens = contextCapacity - generationBudget - 8
        guard maximumPromptTokens > 16 else { throw LlamaEngineError.contextTooSmall }
        if promptTokens.count > maximumPromptTokens {
            let firstToken = promptTokens[0]
            promptTokens = [firstToken] + promptTokens.suffix(maximumPromptTokens - 1)
        }

        var offset = 0
        while offset < promptTokens.count {
            try Task.checkCancellation()
            batch.clear()
            let end = min(offset + batchCapacity, promptTokens.count)
            for index in offset..<end {
                batch.add(
                    promptTokens[index],
                    position: Int32(index),
                    logits: index == promptTokens.count - 1
                )
            }
            guard llama_decode(context, batch) == 0 else { throw LlamaEngineError.decodeFailed }
            offset = end
        }
        return (Int32(promptTokens.count), promptTokens.count)
    }

    private func evaluateMultimodalPrompt(
        _ prompt: String,
        attachments: [InferenceAttachment],
        multimodalContext: OpaquePointer,
        context: OpaquePointer,
        contextCapacity: Int,
        generationBudget: Int,
        batchCapacity: Int
    ) throws -> (position: llama_pos, tokenCount: Int) {
        var wrappers: [mtmd_helper_bitmap_wrapper] = []
        wrappers.reserveCapacity(attachments.count)
        defer {
            for wrapper in wrappers {
                if let bitmap = wrapper.bitmap { mtmd_bitmap_free(bitmap) }
            }
        }

        for attachment in attachments {
            let wrapper = mtmd_helper_bitmap_init_from_file(multimodalContext, attachment.url.path, false)
            guard wrapper.bitmap != nil else { throw LlamaEngineError.attachmentDecodeFailed }
            wrappers.append(wrapper)
        }

        guard let chunks = mtmd_input_chunks_init() else {
            throw LlamaEngineError.attachmentDecodeFailed
        }
        defer { mtmd_input_chunks_free(chunks) }

        var bitmapPointers: [OpaquePointer?] = wrappers.map(\.bitmap)
        let tokenizationResult = prompt.withCString { textPointer in
            var input = mtmd_input_text(
                text: textPointer,
                text_len: prompt.utf8.count,
                add_special: true,
                parse_special: true
            )
            return bitmapPointers.withUnsafeMutableBufferPointer { bitmaps in
                mtmd_tokenize(
                    multimodalContext,
                    chunks,
                    &input,
                    bitmaps.baseAddress,
                    bitmaps.count
                )
            }
        }
        guard tokenizationResult == 0 else { throw LlamaEngineError.attachmentDecodeFailed }

        let tokenCount = Int(mtmd_helper_get_n_tokens(chunks))
        guard tokenCount + generationBudget + 8 <= contextCapacity else {
            throw LlamaEngineError.contextTooSmall
        }
        var newPosition: llama_pos = 0
        let result = mtmd_helper_eval_chunks(
            multimodalContext,
            context,
            chunks,
            0,
            0,
            Int32(batchCapacity),
            true,
            &newPosition
        )
        guard result == 0 else { throw LlamaEngineError.decodeFailed }
        return (newPosition, tokenCount)
    }

    private func makeSampler(settings: GenerationSettings) -> UnsafeMutablePointer<llama_sampler> {
        let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params())!
        if settings.repeatPenalty != 1 || settings.frequencyPenalty != 0 || settings.presencePenalty != 0 {
            llama_sampler_chain_add(sampler, llama_sampler_init_penalties(
                settings.repeatLastTokens,
                settings.repeatPenalty,
                settings.frequencyPenalty,
                settings.presencePenalty
            ))
        }
        llama_sampler_chain_add(sampler, llama_sampler_init_top_k(settings.topK))
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(settings.topP, 1))
        if settings.minP > 0 {
            llama_sampler_chain_add(sampler, llama_sampler_init_min_p(settings.minP, 1))
        }
        if settings.typicalP < 1 {
            llama_sampler_chain_add(sampler, llama_sampler_init_typical(settings.typicalP, 1))
        }
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(settings.temperature))
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(settings.seed ?? LLAMA_DEFAULT_SEED))
        return sampler
    }

    private func prepareMessages(
        _ messages: [ChatMessage],
        attachmentCount: Int,
        capabilities: ModelCapabilities,
        settings: GenerationSettings
    ) -> [ChatMessage] {
        var prepared = messages
        if attachmentCount > 0,
           let index = prepared.lastIndex(where: { $0.role == .user }) {
            let marker = String(cString: mtmd_default_marker())
            let markers = Array(repeating: marker, count: attachmentCount).joined(separator: "\n")
            prepared[index].text = markers + "\n" + prepared[index].text
        }

        guard settings.reasoningMode != .automatic,
              let index = prepared.lastIndex(where: { $0.role == .user })
        else { return prepared }

        let enabled = settings.reasoningMode == .enabled
        switch capabilities.thinkingControl {
        case .qwenSlashCommand:
            prepared[index].text += enabled ? "\n/think" : "\n/no_think"
        case .glmSlashCommand:
            prepared[index].text += enabled ? "\n/think" : "\n/nothink"
        case .none, .closingTag, .reasoningEffort:
            break
        }
        return prepared
    }

    private func applyChatTemplate(
        model: OpaquePointer,
        messages: [ChatMessage],
        systemPrompt: String,
        reasoningEffort: ReasoningEffort,
        thinkingControl: ThinkingControl
    ) -> String {
        var effectiveSystemPrompt = systemPrompt
        if thinkingControl == .reasoningEffort {
            effectiveSystemPrompt += "\nReasoning effort: \(reasoningEffort.rawValue)."
        }

        var sourceMessages = messages.filter { $0.role != .system && !$0.text.isEmpty }
        sourceMessages.insert(ChatMessage(role: .system, text: effectiveSystemPrompt), at: 0)
        guard let template = llama_model_chat_template(model, nil) else {
            return fallbackPrompt(sourceMessages)
        }

        let roles = sourceMessages.map { strdup($0.role.rawValue) }
        let contents = sourceMessages.map { strdup($0.text) }
        defer {
            roles.forEach { free($0) }
            contents.forEach { free($0) }
        }

        let cMessages = zip(roles, contents).map { role, content in
            llama_chat_message(role: role, content: content)
        }
        var buffer = [CChar](
            repeating: 0,
            count: max(2_048, sourceMessages.reduce(0) { $0 + $1.text.utf8.count * 2 })
        )
        var renderedLength = cMessages.withUnsafeBufferPointer { messagesBuffer in
            buffer.withUnsafeMutableBufferPointer { outputBuffer in
                llama_chat_apply_template(
                    template,
                    messagesBuffer.baseAddress,
                    messagesBuffer.count,
                    true,
                    outputBuffer.baseAddress,
                    Int32(outputBuffer.count)
                )
            }
        }
        guard renderedLength >= 0 else { return fallbackPrompt(sourceMessages) }

        if renderedLength >= buffer.count {
            buffer = [CChar](repeating: 0, count: Int(renderedLength) + 1)
            renderedLength = cMessages.withUnsafeBufferPointer { messagesBuffer in
                buffer.withUnsafeMutableBufferPointer { outputBuffer in
                    llama_chat_apply_template(
                        template,
                        messagesBuffer.baseAddress,
                        messagesBuffer.count,
                        true,
                        outputBuffer.baseAddress,
                        Int32(outputBuffer.count)
                    )
                }
            }
        }
        guard renderedLength > 0 else { return fallbackPrompt(sourceMessages) }
        return String(
            decoding: buffer.prefix(Int(renderedLength)).map { UInt8(bitPattern: $0) },
            as: UTF8.self
        )
    }

    private func fallbackPrompt(_ messages: [ChatMessage]) -> String {
        messages.map { "\($0.role.rawValue.capitalized): \($0.text)" }
            .joined(separator: "\n\n") + "\n\nAssistant:"
    }

    private func tokenize(_ text: String, vocabulary: OpaquePointer) throws -> [llama_token] {
        var tokens = [llama_token](repeating: 0, count: text.utf8.count + 8)
        var count = text.withCString { cString in
            tokens.withUnsafeMutableBufferPointer { buffer in
                llama_tokenize(
                    vocabulary,
                    cString,
                    Int32(text.utf8.count),
                    buffer.baseAddress,
                    Int32(buffer.count),
                    true,
                    true
                )
            }
        }
        if count < 0 {
            tokens = [llama_token](repeating: 0, count: Int(-count))
            count = text.withCString { cString in
                tokens.withUnsafeMutableBufferPointer { buffer in
                    llama_tokenize(
                        vocabulary,
                        cString,
                        Int32(text.utf8.count),
                        buffer.baseAddress,
                        Int32(buffer.count),
                        true,
                        true
                    )
                }
            }
        }
        guard count > 0 else { throw LlamaEngineError.emptyPrompt }
        return Array(tokens.prefix(Int(count)))
    }

    private func tokenPiece(_ token: llama_token, vocabulary: OpaquePointer) -> [CChar] {
        var buffer = [CChar](repeating: 0, count: 16)
        var count = buffer.withUnsafeMutableBufferPointer { pointer in
            llama_token_to_piece(vocabulary, token, pointer.baseAddress, Int32(pointer.count), 0, false)
        }
        if count < 0 {
            buffer = [CChar](repeating: 0, count: Int(-count))
            count = buffer.withUnsafeMutableBufferPointer { pointer in
                llama_token_to_piece(vocabulary, token, pointer.baseAddress, Int32(pointer.count), 0, false)
            }
        }
        guard count > 0 else { return [] }
        return Array(buffer.prefix(Int(count)))
    }

    private func runtimeInfo(
        model: OpaquePointer,
        context: OpaquePointer,
        capabilities: ModelCapabilities,
        metadata: [String: String]
    ) -> RuntimeInfo {
        var buffer = [CChar](repeating: 0, count: 512)
        let count = buffer.withUnsafeMutableBufferPointer { pointer in
            llama_model_desc(model, pointer.baseAddress, pointer.count)
        }
        let safeCount = max(0, min(Int(count), buffer.count))
        let description = safeCount > 0
            ? String(decoding: buffer.prefix(safeCount).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            : "GGUF model"
        return RuntimeInfo(
            modelDescription: description.trimmingCharacters(in: .controlCharacters),
            parameterCount: llama_model_n_params(model),
            modelBytes: llama_model_size(model),
            contextSize: Int(llama_n_ctx(context)),
            trainedContextSize: Int(llama_model_n_ctx_train(model)),
            capabilities: capabilities,
            metadata: metadata
        )
    }

    private static func modelMetadata(_ model: OpaquePointer) -> [String: String] {
        var result: [String: String] = [:]
        let count = llama_model_meta_count(model)
        guard count > 0 else { return result }
        for index in 0..<count {
            var keyBuffer = [CChar](repeating: 0, count: 1_024)
            var valueBuffer = [CChar](repeating: 0, count: 65_536)
            let keyCount = keyBuffer.withUnsafeMutableBufferPointer {
                llama_model_meta_key_by_index(model, index, $0.baseAddress, $0.count)
            }
            let valueCount = valueBuffer.withUnsafeMutableBufferPointer {
                llama_model_meta_val_str_by_index(model, index, $0.baseAddress, $0.count)
            }
            guard keyCount > 0, valueCount >= 0 else { continue }
            let key = String(
                decoding: keyBuffer.prefix(min(Int(keyCount), keyBuffer.count)).map { UInt8(bitPattern: $0) },
                as: UTF8.self
            ).trimmingCharacters(in: .controlCharacters)
            let value = String(
                decoding: valueBuffer.prefix(min(Int(valueCount), valueBuffer.count)).map { UInt8(bitPattern: $0) },
                as: UTF8.self
            ).trimmingCharacters(in: .controlCharacters)
            result[key] = value
        }
        return result
    }

    private static func detectCapabilities(
        metadata: [String: String],
        model: OpaquePointer
    ) -> ModelCapabilities {
        let template = metadata["tokenizer.chat_template"]
            ?? llama_model_chat_template(model, nil).map(String.init(cString:))
            ?? ""
        let identity = ([
            metadata["general.name"],
            metadata["general.architecture"],
            metadata["general.basename"],
            template
        ].compactMap { $0 }.joined(separator: " ")).lowercased()

        let control: ThinkingControl
        if identity.contains("reasoning_effort") {
            control = .reasoningEffort
        } else if identity.contains("qwen3") || identity.contains("/no_think") {
            control = .qwenSlashCommand
        } else if identity.contains("/nothink") || identity.contains("glm-4") {
            control = .glmSlashCommand
        } else if identity.contains("enable_thinking")
                    || identity.contains("thinking_budget")
                    || identity.contains("<think>") {
            control = .closingTag
        } else {
            control = .none
        }
        return ModelCapabilities(thinkingControl: control)
    }

    private static func threadCount(from settings: GenerationSettings) -> Int {
        if settings.threadCount > 0 { return min(16, settings.threadCount) }
        return max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
    }

    private func unloadPointers() {
        if let multimodalContext { mtmd_free(multimodalContext) }
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
        multimodalContext = nil
        context = nil
        model = nil
        vocabulary = nil
        loadedURL = nil
        loadedProjectorURL = nil
        loadedConfiguration = nil
        info = nil
    }
}

private struct RuntimeLoadConfiguration: Equatable {
    let contextSize: Int
    let batchSize: Int
    let threadCount: Int
    let gpuLayers: Int
    let useMemoryMap: Bool
    let lockMemory: Bool
    let flashAttention: Bool
    let imageMaximumTokens: Int

    init(settings: GenerationSettings) {
        contextSize = settings.contextSize
        batchSize = settings.batchSize
        threadCount = settings.threadCount
        gpuLayers = settings.gpuLayers
        useMemoryMap = settings.useMemoryMap
        lockMemory = settings.lockMemory
        flashAttention = settings.flashAttention
        imageMaximumTokens = settings.imageMaximumTokens
    }
}

private struct StopSequenceFilter {
    let sequences: [String]
    private var buffer = ""

    init(sequences: [String]) {
        self.sequences = sequences.filter { !$0.isEmpty }
    }

    mutating func consume(_ fragment: String) -> (text: String, shouldStop: Bool) {
        guard !sequences.isEmpty else { return (fragment, false) }
        buffer += fragment

        let firstStop = sequences.compactMap { buffer.range(of: $0) }
            .min { $0.lowerBound < $1.lowerBound }
        if let firstStop {
            let visible = String(buffer[..<firstStop.lowerBound])
            buffer = ""
            return (visible, true)
        }

        let keepCount = max(0, (sequences.map(\.count).max() ?? 1) - 1)
        guard buffer.count > keepCount else { return ("", false) }
        let split = buffer.index(buffer.endIndex, offsetBy: -keepCount)
        let visible = String(buffer[..<split])
        buffer = String(buffer[split...])
        return (visible, false)
    }

    mutating func finish() -> String {
        defer { buffer = "" }
        return buffer
    }
}

private struct ReasoningStreamParser {
    struct Part {
        let isReasoning: Bool
        let text: String
    }

    private var buffer = ""
    private var insideReasoning = false

    mutating func consume(_ fragment: String) -> [Part] {
        process(fragment, final: false)
    }

    mutating func finish() -> [Part] {
        process("", final: true)
    }

    private mutating func process(_ fragment: String, final: Bool) -> [Part] {
        buffer += fragment
        var output: [Part] = []
        while !buffer.isEmpty {
            let tag = insideReasoning ? "</think>" : "<think>"
            if let range = buffer.range(of: tag) {
                let prefix = String(buffer[..<range.lowerBound])
                if !prefix.isEmpty { output.append(Part(isReasoning: insideReasoning, text: prefix)) }
                buffer = String(buffer[range.upperBound...])
                insideReasoning.toggle()
                continue
            }

            if final {
                output.append(Part(isReasoning: insideReasoning, text: buffer))
                buffer = ""
            } else {
                let keepCount = min(buffer.count, tag.count - 1)
                if buffer.count > keepCount {
                    let split = buffer.index(buffer.endIndex, offsetBy: -keepCount)
                    output.append(Part(isReasoning: insideReasoning, text: String(buffer[..<split])))
                    buffer = String(buffer[split...])
                }
            }
            break
        }
        return output.filter { !$0.text.isEmpty }
    }
}

private extension llama_batch {
    mutating func clear() {
        n_tokens = 0
    }

    mutating func add(_ tokenID: llama_token, position: llama_pos, logits shouldOutputLogits: Bool) {
        let index = Int(n_tokens)
        token[index] = tokenID
        pos[index] = position
        n_seq_id[index] = 1
        seq_id[index]![0] = 0
        logits[index] = shouldOutputLogits ? 1 : 0
        n_tokens += 1
    }
}

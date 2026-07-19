import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var webSettings: WebSearchSettings

    var body: some View {
        Form {
            Section {
                Picker("Provider", selection: $webSettings.provider) {
                    ForEach(WebSearchProvider.allCases) { provider in
                        Text(provider.label).tag(provider)
                    }
                }

                if webSettings.provider == .brave {
                    SecureField("Brave Search API key", text: $webSettings.braveAPIKey)
                        .textContentType(.password)
                    Button("Save API key") { webSettings.saveCredential() }
                    if let message = webSettings.credentialMessage {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    TextField("https://search.example.org", text: $webSettings.searxngEndpoint)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            } header: {
                Text("Web search")
            } footer: {
                Text("Web search is opt-in per message. Basalt sends the query to this provider, then gives result snippets to the local model. Prompts and generated text are not sent.")
            }

            GenerationSettingsSections()

            Section("Privacy") {
                Label("No analytics", systemImage: "chart.bar.xaxis")
                Label("No Basalt account", systemImage: "person.crop.circle.badge.xmark")
                Label("Models excluded from backup", systemImage: "externaldrive.badge.xmark")
            }

            Section("About") {
                LabeledContent("Version", value: "0.1.0")
                Link("Source code", destination: URL(string: "https://github.com/j0shua-SYSON/Basalt")!)
                Link("llama.cpp", destination: URL(string: "https://github.com/ggml-org/llama.cpp")!)
            }

            Section {
                Button("Reset generation settings", role: .destructive) {
                    appModel.generationSettings = .default
                }
            }
        }
        .navigationTitle("Settings")
        .accessibilityIdentifier("settings-view")
    }
}

struct GenerationSettingsEditor: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            GenerationSettingsSections()
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

private struct GenerationSettingsSections: View {
    @EnvironmentObject private var appModel: AppModel

    private var settings: Binding<GenerationSettings> { $appModel.generationSettings }

    var body: some View {
        Section("Behavior") {
            Picker("Sampling profile", selection: settings.samplingPreset) {
                ForEach(SamplingPreset.allCases) { preset in
                    Text(preset.rawValue.capitalized).tag(preset)
                }
            }
            .onChange(of: appModel.generationSettings.samplingPreset) { _, preset in
                appModel.generationSettings.apply(preset)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Temperature")
                    Spacer()
                    Text(appModel.generationSettings.temperature, format: .number.precision(.fractionLength(2)))
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: settings.temperature, in: 0...2, step: 0.05)
                    .onChange(of: appModel.generationSettings.temperature) { _, _ in synchronizeSamplingPreset() }
            }

            Stepper(
                "Context · \(appModel.generationSettings.contextSize.formatted())",
                value: settings.contextSize,
                in: 512...131_072,
                step: 512
            )
            Stepper(
                "Maximum response · \(appModel.generationSettings.maximumNewTokens.formatted()) tokens",
                value: settings.maximumNewTokens,
                in: 16...16_384,
                step: 16
            )

            VStack(alignment: .leading, spacing: 7) {
                Text("System prompt")
                TextEditor(text: settings.systemPrompt)
                    .frame(minHeight: 92)
                    .font(.body)
            }
        }

        Section("Reasoning") {
            Picker("Thinking", selection: settings.reasoningMode) {
                ForEach(ReasoningMode.allCases) { mode in
                    Text(mode.rawValue.capitalized).tag(mode)
                }
            }
            Picker("Effort", selection: settings.reasoningEffort) {
                ForEach(ReasoningEffort.allCases) { effort in
                    Text(effort.rawValue.capitalized).tag(effort)
                }
            }
            Text("Basalt exposes this only when the GGUF template advertises a compatible thinking control. Automatic preserves the model’s default.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("Advanced sampling") {
            valueSlider("Top P", value: settings.topP, range: 0...1, step: 0.01)
            Stepper("Top K · \(appModel.generationSettings.topK)", value: settings.topK, in: 0...200)
                .onChange(of: appModel.generationSettings.topK) { _, _ in synchronizeSamplingPreset() }
            valueSlider("Min P", value: settings.minP, range: 0...1, step: 0.01)
            valueSlider("Typical P", value: settings.typicalP, range: 0...1, step: 0.01)
            valueSlider("Repeat penalty", value: settings.repeatPenalty, range: 0.8...1.5, step: 0.01)
            Stepper(
                "Repeat window · \(appModel.generationSettings.repeatLastTokens)",
                value: settings.repeatLastTokens,
                in: 0...4_096,
                step: 16
            )
            .onChange(of: appModel.generationSettings.repeatLastTokens) { _, _ in
                synchronizeSamplingPreset()
            }
            valueSlider("Frequency penalty", value: settings.frequencyPenalty, range: -2...2, step: 0.05)
            valueSlider("Presence penalty", value: settings.presencePenalty, range: -2...2, step: 0.05)
            TextField("Seed · blank is random", text: seedBinding)
                .keyboardType(.numberPad)
            TextField("Stop sequences · one per line", text: stopSequencesBinding, axis: .vertical)
                .lineLimit(2...6)
                .font(.body.monospaced())
        }

        Section("Runtime") {
            Stepper(
                appModel.generationSettings.gpuLayers < 0
                    ? "GPU layers · Automatic"
                    : "GPU layers · \(appModel.generationSettings.gpuLayers)",
                value: settings.gpuLayers,
                in: -1...200
            )
            Stepper(
                appModel.generationSettings.threadCount == 0
                    ? "CPU threads · Automatic"
                    : "CPU threads · \(appModel.generationSettings.threadCount)",
                value: settings.threadCount,
                in: 0...16
            )
            Picker("Batch size", selection: settings.batchSize) {
                ForEach([64, 128, 256, 512, 1_024, 2_048], id: \.self) { Text($0.formatted()).tag($0) }
            }
            Toggle("Flash Attention", isOn: settings.flashAttention)
            Toggle("Memory-map model", isOn: settings.useMemoryMap)
            Toggle("Lock model in memory", isOn: settings.lockMemory)
            Stepper(
                "Maximum image tokens · \(appModel.generationSettings.imageMaximumTokens)",
                value: settings.imageMaximumTokens,
                in: 256...4_096,
                step: 128
            )
            Text("Runtime changes reload the model. Aggressive values can exceed device memory; Automatic is the recommended baseline.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func valueSlider(
        _ title: String,
        value: Binding<Float>,
        range: ClosedRange<Float>,
        step: Float
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                Spacer()
                Text(value.wrappedValue, format: .number.precision(.fractionLength(2)))
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
                .onChange(of: value.wrappedValue) { _, _ in synchronizeSamplingPreset() }
        }
    }

    private var seedBinding: Binding<String> {
        Binding(
            get: { appModel.generationSettings.seed.map(String.init) ?? "" },
            set: { appModel.generationSettings.seed = UInt32($0) }
        )
    }

    private var stopSequencesBinding: Binding<String> {
        Binding(
            get: { appModel.generationSettings.stopSequences.joined(separator: "\n") },
            set: {
                appModel.generationSettings.stopSequences = $0
                    .split(separator: "\n", omittingEmptySubsequences: true)
                    .map(String.init)
            }
        )
    }

    private func synchronizeSamplingPreset() {
        let settings = appModel.generationSettings
        let detected = [SamplingPreset.precise, .balanced, .creative]
            .first(where: settings.matches) ?? .custom
        if settings.samplingPreset != detected {
            appModel.generationSettings.samplingPreset = detected
        }
    }
}

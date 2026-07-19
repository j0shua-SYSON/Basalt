import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var draft = ""
    @State private var searchWeb = false
    @State private var isGenerationSheetPresented = false

    var body: some View {
        VStack(spacing: 0) {
            ModelStatusBar()
            Divider().opacity(0.55)

            if appModel.selectedModel == nil {
                noModel
            } else if let conversation = appModel.selectedConversation {
                transcript(conversation)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if appModel.selectedModel != nil {
                ComposerView(
                    draft: $draft,
                    searchWeb: $searchWeb,
                    showGenerationSettings: { isGenerationSheetPresented = true }
                )
            }
        }
        .sheet(isPresented: $isGenerationSheetPresented) {
            NavigationStack {
                GenerationSettingsEditor()
                    .navigationTitle("Generation")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.large])
        }
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("chat-view")
    }

    private var noModel: some View {
        ContentUnavailableView {
            Label("Bring a model", systemImage: "cube.transparent")
        } description: {
            Text("Basalt needs a local GGUF before it can start a private conversation.")
        } actions: {
            Button("Open model library") { appModel.destination = .models }
                .buttonStyle(.borderedProminent)
            Button("Add a GGUF") { appModel.isImportSheetPresented = true }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func transcript(_ conversation: Conversation) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                if conversation.messages.isEmpty {
                    EmptyConversationView(model: appModel.selectedModel)
                        .frame(minHeight: 470)
                } else {
                    LazyVStack(spacing: 24) {
                        ForEach(conversation.messages) { message in
                            MessageRow(
                                message: message,
                                isStreaming: appModel.isGenerating
                                    && message.id == conversation.messages.last?.id
                                    && message.role == .assistant,
                                retry: message.id == conversation.messages.last?.id
                                    && message.role == .assistant
                                    ? appModel.retryLastResponse
                                    : nil
                            )
                            .id(message.id)
                        }

                        if appModel.isSearching {
                            Label("Searching the web…", systemImage: "network")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("web-search-progress")
                        }

                        Color.clear.frame(height: 10).id("conversation-bottom")
                    }
                    .frame(maxWidth: 820)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: conversation.messages) {
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo("conversation-bottom", anchor: .bottom)
                }
            }
        }
    }
}

private struct EmptyConversationView: View {
    let model: ModelRecord?

    var body: some View {
        VStack(spacing: 20) {
            TokenStrataView()
                .frame(width: 190, height: 116)
            VStack(spacing: 7) {
                Text("A quiet place to think")
                    .font(.title2.weight(.semibold))
                Text("\(model?.name ?? "Your model") runs here, on this device.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Label("Private", systemImage: "lock")
                Label("Offline", systemImage: "airplane")
                Label("Streaming", systemImage: "text.line.last.and.arrowtriangle.forward")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(30)
    }
}

private struct ModelStatusBar: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(appModel.models) { model in
                    Button {
                        appModel.selectModel(model)
                    } label: {
                        if model.id == appModel.selectedModel?.id {
                            Label(model.name, systemImage: "checkmark")
                        } else {
                            Text(model.name)
                        }
                    }
                }
                Divider()
                Button {
                    appModel.destination = .models
                } label: {
                    Label("Model library", systemImage: "shippingbox")
                }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "cube.transparent")
                        .foregroundStyle(BasaltTheme.lichen)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(appModel.selectedModel?.name ?? "Choose model")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        statusText
                    }
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("model-selector")

            Spacer(minLength: 8)

            if let runtime = appModel.runtimeInfo,
               appModel.loadedModelID == appModel.selectedModel?.id {
                HStack(spacing: 5) {
                    ForEach(Array(runtime.capabilities.all).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { capability in
                        Image(systemName: icon(for: capability))
                            .foregroundStyle(color(for: capability))
                            .accessibilityLabel(capability.rawValue.capitalized)
                    }
                }
                .font(.caption.weight(.semibold))
            }

            if let speed = appModel.tokensPerSecond, speed > 0 {
                Text("\(speed, format: .number.precision(.fractionLength(1))) t/s")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(speed, specifier: "%.1f") tokens per second")
            }

            if appModel.loadedModelID != appModel.selectedModel?.id {
                Button("Load") { appModel.loadSelectedModel() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(appModel.isModelLoading)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(.bar)
    }

    @ViewBuilder
    private var statusText: some View {
        if appModel.isModelLoading {
            Text("Loading into memory…")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if appModel.loadedModelID == appModel.selectedModel?.id, let runtime = appModel.runtimeInfo {
            Text("\(runtime.formattedParameters) · \(runtime.contextSize.formatted()) ctx")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        } else {
            Text("Not loaded")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func icon(for capability: ModelCapability) -> String {
        switch capability {
        case .reasoning: "brain.head.profile"
        case .vision: "eye"
        case .audio: "waveform"
        }
    }

    private func color(for capability: ModelCapability) -> Color {
        switch capability {
        case .reasoning: BasaltTheme.mineral
        case .vision: BasaltTheme.slate
        case .audio: BasaltTheme.copper
        }
    }
}


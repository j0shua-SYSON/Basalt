import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ComposerView: View {
    @EnvironmentObject private var appModel: AppModel
    @Binding var draft: String
    @Binding var searchWeb: Bool
    let showGenerationSettings: () -> Void

    @StateObject private var audioRecorder = AudioRecorder()
    @State private var photoItem: PhotosPickerItem?
    @State private var isFileImporterPresented = false
    @State private var requestedKind = MediaKind.image

    private var capabilities: ModelCapabilities? {
        guard appModel.loadedModelID == appModel.selectedModel?.id else { return nil }
        return appModel.runtimeInfo?.capabilities
    }

    private var hasProjector: Bool { appModel.selectedModel?.projectorFileName != nil }

    var body: some View {
        VStack(spacing: 9) {
            if !appModel.pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(appModel.pendingAttachments) { attachment in
                            HStack(spacing: 6) {
                                Image(systemName: attachment.kind == .image ? "photo" : "waveform")
                                Text(attachment.displayName).lineLimit(1)
                                Button {
                                    appModel.removePendingAttachment(attachment)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .accessibilityLabel("Remove \(attachment.displayName)")
                            }
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(.quaternary.opacity(0.55), in: Capsule())
                        }
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 9) {
                attachmentMenu

                TextField("Message \(appModel.selectedModel?.name ?? "model")", text: $draft, axis: .vertical)
                    .lineLimit(1...7)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
                    .onSubmit(send)
                    .accessibilityIdentifier("message-composer")

                Button {
                    searchWeb.toggle()
                } label: {
                    Image(systemName: searchWeb ? "network.badge.shield.half.filled" : "network")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(searchWeb ? BasaltTheme.slate : .secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 34, height: 34)
                .accessibilityLabel(searchWeb ? "Disable web search" : "Enable web search")
                .accessibilityIdentifier("web-search-toggle")

                if capabilities?.supportsThinking == true {
                    Button {
                        let isEnabled = appModel.generationSettings.reasoningMode != .disabled
                        appModel.generationSettings.reasoningMode = isEnabled ? .disabled : .enabled
                    } label: {
                        Image(systemName: appModel.generationSettings.reasoningMode == .disabled
                            ? "brain.head.profile"
                            : "brain.head.profile.fill")
                            .foregroundStyle(appModel.generationSettings.reasoningMode == .disabled
                                ? .secondary
                                : BasaltTheme.mineral)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 34, height: 34)
                    .accessibilityLabel("Thinking mode")
                    .accessibilityValue(appModel.generationSettings.reasoningMode == .disabled ? "Off" : "On")
                    .accessibilityIdentifier("thinking-toggle")
                }

                Button(action: showGenerationSettings) {
                    Image(systemName: "dial.medium")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 34, height: 34)
                .accessibilityLabel("Generation settings")

                Button(action: appModel.isGenerating ? appModel.stopGenerating : send) {
                    Image(systemName: appModel.isGenerating ? "stop.fill" : "arrow.up")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(
                            appModel.isGenerating ? BasaltTheme.copper : Color.accentColor,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(!appModel.isGenerating && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && appModel.pendingAttachments.isEmpty)
                .keyboardShortcut(.return, modifiers: [.command])
                .accessibilityLabel(appModel.isGenerating ? "Stop generation" : "Send message")
                .accessibilityIdentifier(appModel.isGenerating ? "stop-generation" : "send-message")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.primary.opacity(0.09), lineWidth: 0.5)
            }

            HStack(spacing: 10) {
                if searchWeb {
                    Label("Web on", systemImage: "network")
                        .foregroundStyle(BasaltTheme.slate)
                }
                if appModel.generationSettings.reasoningMode != .disabled,
                   capabilities?.supportsThinking == true {
                    Label("Thinking", systemImage: "brain.head.profile")
                        .foregroundStyle(BasaltTheme.mineral)
                }
                Spacer()
                Text("\(appModel.generationSettings.contextSize.formatted()) context")
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
        }
        .frame(maxWidth: 820)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: requestedKind == .image ? [.image] : [.audio],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first {
                appModel.addAttachmentFile(url, kind: requestedKind)
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data),
                   let jpeg = image.jpegData(compressionQuality: 0.9) {
                    appModel.addImageData(jpeg)
                } else {
                    appModel.notice = AppNotice(title: "Couldn’t attach image", message: "Basalt could not convert this photo to a supported format.")
                }
                photoItem = nil
            }
        }
        .onDisappear { audioRecorder.cancel() }
    }

    private var attachmentMenu: some View {
        Menu {
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Photo library", systemImage: "photo.on.rectangle")
            }
            Button {
                requestedKind = .image
                isFileImporterPresented = true
            } label: {
                Label("Image from Files", systemImage: "photo")
            }
            Button {
                requestedKind = .audio
                isFileImporterPresented = true
            } label: {
                Label("Audio from Files", systemImage: "waveform")
            }
            Divider()
            Button {
                audioRecorder.toggle { url in
                    appModel.addAttachmentFile(url, kind: .audio)
                } onError: { error in
                    appModel.notice = AppNotice(title: "Audio recording unavailable", message: error.localizedDescription)
                }
            } label: {
                Label(
                    audioRecorder.isRecording ? "Finish recording" : "Record audio",
                    systemImage: audioRecorder.isRecording ? "stop.circle" : "mic"
                )
            }
        } label: {
            Image(systemName: audioRecorder.isRecording ? "waveform.circle.fill" : "plus.circle")
                .font(.title3)
                .foregroundStyle(audioRecorder.isRecording ? BasaltTheme.copper : .secondary)
                .frame(width: 34, height: 34)
        }
        .disabled(!hasProjector || appModel.isGenerating)
        .accessibilityLabel(hasProjector ? "Add image or audio" : "Attach a multimodal projector to add media")
        .accessibilityIdentifier("attachment-menu")
    }

    private func send() {
        var text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty && !appModel.pendingAttachments.isEmpty {
            text = "Describe and analyze the attached media."
        }
        guard !text.isEmpty else { return }
        appModel.send(text, searchWeb: searchWeb)
        draft = ""
    }
}


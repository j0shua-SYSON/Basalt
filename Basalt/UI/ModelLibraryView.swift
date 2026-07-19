import SwiftUI
import UniformTypeIdentifiers

struct ModelLibraryView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var inspectedModel: ModelRecord?

    private let columns = [GridItem(.adaptive(minimum: 270, maximum: 390), spacing: 16)]

    var body: some View {
        ScrollView {
            if appModel.models.isEmpty {
                ContentUnavailableView {
                    Label("No local models", systemImage: "shippingbox")
                } description: {
                    Text("Import a single-file GGUF to begin.")
                } actions: {
                    Button("Add model") { appModel.isImportSheetPresented = true }
                        .buttonStyle(.borderedProminent)
                }
                .frame(minHeight: 460)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(appModel.models) { model in
                        ModelCard(model: model) {
                            inspectedModel = model
                        }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Models")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appModel.isImportSheetPresented = true
                } label: {
                    Label("Add model", systemImage: "plus")
                }
                .accessibilityIdentifier("library-add-model")
            }
        }
        .sheet(item: $inspectedModel) { model in
            ModelInspectorSheet(modelID: model.id)
                .environmentObject(appModel)
        }
        .accessibilityIdentifier("model-library")
    }
}

private struct ModelCard: View {
    @EnvironmentObject private var appModel: AppModel
    let model: ModelRecord
    let inspect: () -> Void

    private var isLoaded: Bool { appModel.loadedModelID == model.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Image(systemName: model.projectorFileName == nil ? "cube.transparent" : "viewfinder.circle")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(isLoaded ? BasaltTheme.lichen : BasaltTheme.slate)
                    .frame(width: 44, height: 44)
                    .background((isLoaded ? BasaltTheme.lichen : BasaltTheme.slate).opacity(0.12), in: RoundedRectangle(cornerRadius: 13))

                Spacer()
                if isLoaded {
                    Label("Loaded", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BasaltTheme.lichen)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(model.name)
                    .font(.headline)
                    .lineLimit(2)
                Text([model.quantization, model.formattedSize].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 7) {
                Label(model.origin.label, systemImage: model.origin == .files ? "folder" : "network")
                if model.projectorFileName != nil {
                    Label("Multimodal", systemImage: "camera.macro")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if isLoaded, let runtime = appModel.runtimeInfo {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(runtime.capabilities.all), id: \.self) {
                            CapabilityLabel(capability: $0)
                        }
                    }
                }
            }

            HStack {
                Button("Details", action: inspect)
                    .buttonStyle(.bordered)
                Spacer()
                Button {
                    appModel.selectModel(model)
                    appModel.loadSelectedModel()
                    if let conversation = appModel.selectedConversation {
                        appModel.destination = .conversation(conversation.id)
                    }
                } label: {
                    Text(isLoaded ? "Open" : "Use model")
                }
                .buttonStyle(.borderedProminent)
                .tint(BasaltTheme.lichen)
            }
        }
        .padding(18)
        .basaltCard()
        .contentShape(RoundedRectangle(cornerRadius: BasaltTheme.cornerRadius))
        .onTapGesture(perform: inspect)
    }
}

private struct ModelInspectorSheet: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    let modelID: UUID

    @State private var isProjectorSheetPresented = false
    @State private var isRenamePresented = false
    @State private var isDeletePresented = false
    @State private var renameText = ""

    private var model: ModelRecord? { appModel.models.first(where: { $0.id == modelID }) }

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    List {
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(model.name)
                                    .font(.title2.weight(.semibold))
                                Text(model.fileName)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            .padding(.vertical, 6)

                            LabeledContent("Size", value: model.formattedSize)
                            LabeledContent("Quantization", value: model.quantization ?? "Unknown")
                            LabeledContent("Imported from", value: model.origin.label)
                        }

                        Section("Multimodal adapter") {
                            if let projector = model.projectorFileName {
                                Label(projector, systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(BasaltTheme.lichen)
                            } else {
                                Text("Attach the matching mmproj GGUF to enable the vision or audio capabilities embedded in that projector.")
                                    .foregroundStyle(.secondary)
                            }
                            Button(model.projectorFileName == nil ? "Attach projector" : "Replace projector") {
                                isProjectorSheetPresented = true
                            }
                        }

                        if appModel.loadedModelID == model.id, let runtime = appModel.runtimeInfo {
                            Section("Runtime") {
                                LabeledContent("Parameters", value: runtime.formattedParameters)
                                LabeledContent("Active context", value: runtime.contextSize.formatted())
                                LabeledContent("Trained context", value: runtime.trainedContextSize.formatted())
                                ForEach(Array(runtime.capabilities.all), id: \.self) {
                                    CapabilityLabel(capability: $0)
                                }
                            }

                            Section("GGUF metadata") {
                                DisclosureGroup("Show \(runtime.metadata.count) entries") {
                                    ForEach(runtime.metadata.keys.sorted(), id: \.self) { key in
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(key)
                                                .font(.caption.monospaced().weight(.semibold))
                                            Text(runtime.metadata[key] ?? "")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(8)
                                                .textSelection(.enabled)
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                        }

                        Section {
                            Button("Rename") {
                                renameText = model.name
                                isRenamePresented = true
                            }
                            Button("Delete model", role: .destructive) {
                                isDeletePresented = true
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("Model not found", systemImage: "questionmark.folder")
                }
            }
            .navigationTitle("Model details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $isProjectorSheetPresented) {
            if let model {
                ProjectorImportSheet(model: model)
                    .environmentObject(appModel)
            }
        }
        .alert("Rename model", isPresented: $isRenamePresented) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                if let model { appModel.renameModel(model, to: renameText) }
            }
        }
        .confirmationDialog("Delete this model?", isPresented: $isDeletePresented, titleVisibility: .visible) {
            Button("Delete model", role: .destructive) {
                if let model {
                    appModel.deleteModel(model)
                    dismiss()
                }
            }
        } message: {
            Text("The GGUF and its projector will be removed from this device. Conversations are kept.")
        }
    }
}

private struct ProjectorImportSheet: View {
    private enum Source: String, CaseIterable, Identifiable {
        case files = "Files"
        case huggingFace = "Hugging Face"
        var id: String { rawValue }
    }

    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    let model: ModelRecord
    @State private var source = Source.files
    @State private var isFileImporterPresented = false
    @State private var url = ""
    @State private var token = ""
    @State private var started = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Source", selection: $source) {
                        ForEach(Source.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                if source == .files {
                    Section {
                        Button {
                            started = true
                            isFileImporterPresented = true
                        } label: {
                            Label("Choose mmproj GGUF", systemImage: "folder")
                        }
                    } footer: {
                        Text("Use the projector shipped for exactly this text model.")
                    }
                } else {
                    Section("Projector GGUF URL") {
                        TextField("https://huggingface.co/…/mmproj.gguf", text: $url, axis: .vertical)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Access token · optional", text: $token)
                        Button("Download and attach") {
                            started = true
                            appModel.attachProjectorFromHuggingFace(url: url, accessToken: token, to: model)
                        }
                        .disabled(url.isEmpty || appModel.isImporting)
                    }
                }

                if let progress = appModel.importProgress {
                    Section { ImportProgressView(progress: progress) }
                }
            }
            .navigationTitle("Multimodal projector")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.disabled(appModel.isImporting)
                }
            }
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: [UTType(filenameExtension: "gguf") ?? .data],
                allowsMultipleSelection: false
            ) { result in
                if case let .success(urls) = result, let selected = urls.first {
                    appModel.attachProjectorFile(selected, to: model)
                }
            }
            .onChange(of: appModel.isImporting) { wasImporting, isImporting in
                if started && wasImporting && !isImporting { dismiss() }
            }
        }
        .interactiveDismissDisabled(appModel.isImporting)
    }
}

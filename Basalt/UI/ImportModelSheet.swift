import SwiftUI
import UniformTypeIdentifiers

struct ImportModelSheet: View {
    private enum Source: String, CaseIterable, Identifiable {
        case files = "Files"
        case huggingFace = "Hugging Face"
        var id: String { rawValue }
    }

    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var source = Source.files
    @State private var isFileImporterPresented = false
    @State private var huggingFaceURL = ""
    @State private var accessToken = ""

    private var ggufType: UTType { UTType(filenameExtension: "gguf") ?? .data }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Picker("Import source", selection: $source) {
                    ForEach(Source.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(appModel.isImporting)

                Group {
                    switch source {
                    case .files:
                        filesPanel
                    case .huggingFace:
                        huggingFacePanel
                    }
                }

                if let progress = appModel.importProgress {
                    ImportProgressView(progress: progress)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Spacer(minLength: 0)

                Label(
                    "Models stay in Basalt’s private local library and are excluded from device backup.",
                    systemImage: "lock.shield"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .padding(24)
            .navigationTitle("Add model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .disabled(appModel.isImporting)
                }
            }
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: [ggufType],
                allowsMultipleSelection: false
            ) { result in
                if case let .success(urls) = result, let url = urls.first {
                    appModel.importLocalFile(url)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(appModel.isImporting)
    }

    private var filesPanel: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(BasaltTheme.slate)
                .frame(width: 68, height: 68)
                .background(BasaltTheme.slate.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(spacing: 6) {
                Text("Choose a GGUF")
                    .font(.title3.weight(.semibold))
                Text("Single-file quantized models work best on iPhone and iPad.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                isFileImporterPresented = true
            } label: {
                Label("Choose from Files", systemImage: "folder")
                    .frame(maxWidth: 260)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(appModel.isImporting)
            .accessibilityIdentifier("choose-gguf-file")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private var huggingFacePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("GGUF file URL")
                    .font(.subheadline.weight(.semibold))
                TextField(
                    "https://huggingface.co/…/model.gguf",
                    text: $huggingFaceURL,
                    axis: .vertical
                )
                .textContentType(.URL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(2...4)
                .padding(12)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityIdentifier("huggingface-url")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Access token · optional")
                    .font(.subheadline.weight(.semibold))
                SecureField("Only needed for gated models", text: $accessToken)
                    .textContentType(.password)
                    .padding(12)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text("Used for this download only. Basalt does not save it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                appModel.importHuggingFace(url: huggingFaceURL, accessToken: accessToken)
            } label: {
                Label("Download model", systemImage: "arrow.down.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(huggingFaceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appModel.isImporting)
            .accessibilityIdentifier("download-huggingface-model")
        }
    }
}

struct ImportProgressView: View {
    let progress: ImportProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(progress.label)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let fraction = progress.fraction {
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if let fraction = progress.fraction {
                ProgressView(value: fraction)
                    .tint(BasaltTheme.lichen)
            } else {
                ProgressView()
            }
            if progress.completedBytes > 0 {
                Text(ByteCountFormatter.string(fromByteCount: progress.completedBytes, countStyle: .file))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .basaltCard()
        .accessibilityElement(children: .combine)
    }
}


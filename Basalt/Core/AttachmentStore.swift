import Foundation

enum AttachmentStoreError: LocalizedError {
    case unsupportedType
    case fileTooLarge
    case unsafePath

    var errorDescription: String? {
        switch self {
        case .unsupportedType:
            "Use JPG, PNG, BMP, GIF, WAV, MP3, or FLAC attachments."
        case .fileTooLarge:
            "This attachment is too large for an on-device conversation."
        case .unsafePath:
            "The attachment path is not safe to open."
        }
    }
}

actor AttachmentStore {
    private let directories: AppDirectories
    private let fileManager: FileManager

    init(root: URL? = nil, fileManager: FileManager = .default) {
        directories = AppDirectories(root: root)
        self.fileManager = fileManager
    }

    func importFile(from source: URL, kind: MediaKind) throws -> MediaAttachment {
        try directories.prepare()
        let hasAccess = source.startAccessingSecurityScopedResource()
        defer { if hasAccess { source.stopAccessingSecurityScopedResource() } }

        let fileExtension = source.pathExtension.lowercased()
        guard Self.supportedExtensions(for: kind).contains(fileExtension) else {
            throw AttachmentStoreError.unsupportedType
        }
        let values = try source.resourceValues(forKeys: [.fileSizeKey])
        let byteCount = Int64(values.fileSize ?? 0)
        guard byteCount <= Self.maximumBytes(for: kind) else {
            throw AttachmentStoreError.fileTooLarge
        }

        let fileName = "\(UUID().uuidString).\(fileExtension)"
        let destination = directories.attachments.appendingPathComponent(fileName)
        try fileManager.copyItem(at: source, to: destination)
        return MediaAttachment(
            kind: kind,
            fileName: fileName,
            displayName: source.deletingPathExtension().lastPathComponent,
            byteCount: byteCount
        )
    }

    func importData(
        _ data: Data,
        kind: MediaKind,
        fileExtension: String,
        displayName: String
    ) throws -> MediaAttachment {
        try directories.prepare()
        let normalizedExtension = fileExtension.lowercased()
        guard Self.supportedExtensions(for: kind).contains(normalizedExtension) else {
            throw AttachmentStoreError.unsupportedType
        }
        guard Int64(data.count) <= Self.maximumBytes(for: kind) else {
            throw AttachmentStoreError.fileTooLarge
        }
        let fileName = "\(UUID().uuidString).\(normalizedExtension)"
        try data.write(to: directories.attachments.appendingPathComponent(fileName), options: .atomic)
        return MediaAttachment(
            kind: kind,
            fileName: fileName,
            displayName: displayName,
            byteCount: Int64(data.count)
        )
    }

    func url(for attachment: MediaAttachment) throws -> URL {
        let candidate = directories.attachments.appendingPathComponent(attachment.fileName).standardizedFileURL
        guard candidate.deletingLastPathComponent() == directories.attachments.standardizedFileURL else {
            throw AttachmentStoreError.unsafePath
        }
        return candidate
    }

    func delete(_ attachment: MediaAttachment) throws {
        let candidate = try url(for: attachment)
        if fileManager.fileExists(atPath: candidate.path) {
            try fileManager.removeItem(at: candidate)
        }
    }

    private static func supportedExtensions(for kind: MediaKind) -> Set<String> {
        switch kind {
        case .image: ["jpg", "jpeg", "png", "bmp", "gif"]
        case .audio: ["wav", "mp3", "flac"]
        }
    }

    private static func maximumBytes(for kind: MediaKind) -> Int64 {
        switch kind {
        case .image: 40 * 1_024 * 1_024
        case .audio: 200 * 1_024 * 1_024
        }
    }
}

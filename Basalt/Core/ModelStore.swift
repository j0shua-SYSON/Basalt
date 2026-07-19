import Foundation

enum ModelStoreError: LocalizedError, Equatable {
    case notGGUF
    case splitModelUnsupported
    case projectorNeedsModel
    case insufficientStorage(required: Int64, available: Int64)
    case invalidCatalogEntry
    case copyFailed

    var errorDescription: String? {
        switch self {
        case .notGGUF:
            "This file is not a valid GGUF model."
        case .splitModelUnsupported:
            "Split GGUF sets are not supported yet. Choose a single-file model."
        case .projectorNeedsModel:
            "This looks like a multimodal projector. Attach it to a text model from that model’s detail screen."
        case let .insufficientStorage(required, available):
            "The model needs \(Self.bytes(required)), but only \(Self.bytes(available)) is available."
        case .invalidCatalogEntry:
            "The model catalog contains an unsafe file path."
        case .copyFailed:
            "Basalt could not copy the model into its library."
        }
    }

    private static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}

actor ModelStore {
    typealias ProgressHandler = @Sendable (ImportProgress) -> Void

    private let directories: AppDirectories
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(root: URL? = nil, fileManager: FileManager = .default) {
        directories = AppDirectories(root: root)
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func models() throws -> [ModelRecord] {
        try directories.prepare()
        guard fileManager.fileExists(atPath: directories.modelCatalog.path) else {
            return []
        }
        let data = try Data(contentsOf: directories.modelCatalog)
        return try decoder.decode([ModelRecord].self, from: data)
            .filter { fileManager.fileExists(atPath: modelURL(for: $0).path) }
            .sorted { $0.importedAt > $1.importedAt }
    }

    func modelURL(for record: ModelRecord) -> URL {
        directories.models.appendingPathComponent(record.fileName, isDirectory: false)
    }

    func importModel(
        from source: URL,
        origin: ModelOrigin,
        sourceURL: URL? = nil,
        suggestedName: String? = nil,
        progress: @escaping ProgressHandler = { _ in }
    ) async throws -> ModelRecord {
        try directories.prepare()
        progress(ImportProgress(phase: .validating, fraction: nil))

        let hasSecurityAccess = source.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityAccess {
                source.stopAccessingSecurityScopedResource()
            }
        }

        guard try Self.hasGGUFHeader(at: source) else {
            throw ModelStoreError.notGGUF
        }
        if source.lastPathComponent.lowercased().contains("mmproj") {
            throw ModelStoreError.projectorNeedsModel
        }
        if Self.looksLikeSplitModel(source.lastPathComponent) {
            throw ModelStoreError.splitModelUnsupported
        }

        let values = try source.resourceValues(forKeys: [.fileSizeKey])
        let byteCount = Int64(values.fileSize ?? 0)
        try ensureCapacity(for: byteCount)

        let preferredName = suggestedName ?? source.deletingPathExtension().lastPathComponent
        let displayName = Self.cleanedDisplayName(preferredName)
        let destinationName = uniqueFileName(for: source.lastPathComponent, displayName: displayName)
        let destination = directories.models.appendingPathComponent(destinationName)

        progress(ImportProgress(
            phase: .copying,
            fraction: byteCount > 0 ? 0 : nil,
            completedBytes: 0,
            totalBytes: byteCount > 0 ? byteCount : nil
        ))

        do {
            try copyFile(from: source, to: destination, totalBytes: byteCount, progress: progress)
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }

        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableDestination = destination
        try? mutableDestination.setResourceValues(resourceValues)

        let record = ModelRecord(
            id: UUID(),
            name: displayName,
            fileName: destinationName,
            byteCount: byteCount,
            importedAt: Date(),
            lastUsedAt: nil,
            origin: origin,
            sourceURL: sourceURL
        )
        var catalog = try models()
        catalog.insert(record, at: 0)
        try save(catalog)
        progress(ImportProgress(phase: .finished, fraction: 1, completedBytes: byteCount, totalBytes: byteCount))
        return record
    }

    func rename(_ record: ModelRecord, to name: String) throws -> ModelRecord {
        var catalog = try models()
        guard let index = catalog.firstIndex(where: { $0.id == record.id }) else {
            return record
        }
        catalog[index].name = Self.cleanedDisplayName(name)
        try save(catalog)
        return catalog[index]
    }

    func markUsed(_ record: ModelRecord) throws -> ModelRecord {
        var catalog = try models()
        guard let index = catalog.firstIndex(where: { $0.id == record.id }) else {
            return record
        }
        catalog[index].lastUsedAt = Date()
        try save(catalog)
        return catalog[index]
    }

    func delete(_ record: ModelRecord) throws {
        let candidate = modelURL(for: record).standardizedFileURL
        let parent = candidate.deletingLastPathComponent().standardizedFileURL
        guard parent == directories.models.standardizedFileURL else {
            throw ModelStoreError.invalidCatalogEntry
        }
        if fileManager.fileExists(atPath: candidate.path) {
            try fileManager.removeItem(at: candidate)
        }
        if let projector = projectorURL(for: record), fileManager.fileExists(atPath: projector.path) {
            try fileManager.removeItem(at: projector)
        }
        let remaining = try models().filter { $0.id != record.id }
        try save(remaining)
    }

    func projectorURL(for record: ModelRecord) -> URL? {
        guard let fileName = record.projectorFileName else { return nil }
        let candidate = directories.models.appendingPathComponent(fileName).standardizedFileURL
        guard candidate.deletingLastPathComponent() == directories.models.standardizedFileURL else { return nil }
        return candidate
    }

    func attachProjector(
        from source: URL,
        to record: ModelRecord,
        progress: @escaping ProgressHandler = { _ in }
    ) throws -> ModelRecord {
        try directories.prepare()
        progress(ImportProgress(phase: .validating, fraction: nil))
        let hasSecurityAccess = source.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityAccess { source.stopAccessingSecurityScopedResource() }
        }
        guard try Self.hasGGUFHeader(at: source) else { throw ModelStoreError.notGGUF }

        let values = try source.resourceValues(forKeys: [.fileSizeKey])
        let byteCount = Int64(values.fileSize ?? 0)
        try ensureCapacity(for: byteCount)
        let base = Self.safeFileComponent(source.deletingPathExtension().lastPathComponent)
        var name = "\(base).gguf"
        var suffix = 2
        while fileManager.fileExists(atPath: directories.models.appendingPathComponent(name).path) {
            name = "\(base)-\(suffix).gguf"
            suffix += 1
        }
        let destination = directories.models.appendingPathComponent(name)
        do {
            try copyFile(from: source, to: destination, totalBytes: byteCount, progress: progress)
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }

        var catalog = try models()
        guard let index = catalog.firstIndex(where: { $0.id == record.id }) else {
            try? fileManager.removeItem(at: destination)
            throw ModelStoreError.invalidCatalogEntry
        }
        let previous = projectorURL(for: catalog[index])
        catalog[index].projectorFileName = name
        try save(catalog)
        if let previous, previous != destination {
            try? fileManager.removeItem(at: previous)
        }
        progress(ImportProgress(phase: .finished, fraction: 1, completedBytes: byteCount, totalBytes: byteCount))
        return catalog[index]
    }

    private func save(_ records: [ModelRecord]) throws {
        let data = try encoder.encode(records)
        try data.write(to: directories.modelCatalog, options: .atomic)
    }

    private func ensureCapacity(for byteCount: Int64) throws {
        guard byteCount > 0 else { return }
        let values = try directories.root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let available = values.volumeAvailableCapacityForImportantUsage else { return }
        let headroom = Int64(256 * 1_024 * 1_024)
        if available < byteCount + headroom {
            throw ModelStoreError.insufficientStorage(required: byteCount + headroom, available: available)
        }
    }

    private func copyFile(
        from source: URL,
        to destination: URL,
        totalBytes: Int64,
        progress: ProgressHandler
    ) throws {
        guard fileManager.createFile(atPath: destination.path, contents: nil) else {
            throw ModelStoreError.copyFailed
        }

        let input = try FileHandle(forReadingFrom: source)
        let output = try FileHandle(forWritingTo: destination)
        defer {
            try? input.close()
            try? output.close()
        }

        let chunkSize = 4 * 1_024 * 1_024
        var completed: Int64 = 0
        while let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty {
            try Task.checkCancellation()
            try output.write(contentsOf: chunk)
            completed += Int64(chunk.count)
            progress(ImportProgress(
                phase: .copying,
                fraction: totalBytes > 0 ? min(1, Double(completed) / Double(totalBytes)) : nil,
                completedBytes: completed,
                totalBytes: totalBytes > 0 ? totalBytes : nil
            ))
        }
        try output.synchronize()
    }

    private func uniqueFileName(for original: String, displayName: String) -> String {
        let rawExtension = URL(fileURLWithPath: original).pathExtension.lowercased()
        let fileExtension = rawExtension == "gguf" ? rawExtension : "gguf"
        let base = Self.safeFileComponent(displayName)
        var candidate = "\(base).\(fileExtension)"
        var suffix = 2
        while fileManager.fileExists(atPath: directories.models.appendingPathComponent(candidate).path) {
            candidate = "\(base)-\(suffix).\(fileExtension)"
            suffix += 1
        }
        return candidate
    }

    private static func hasGGUFHeader(at url: URL) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: 4) == Data([0x47, 0x47, 0x55, 0x46])
    }

    private static func looksLikeSplitModel(_ fileName: String) -> Bool {
        let lowercased = fileName.lowercased()
        return lowercased.range(of: #"-\d{5}-of-\d{5}\.gguf$"#, options: .regularExpression) != nil
    }

    private static func cleanedDisplayName(_ value: String) -> String {
        let withoutExtension = value.hasSuffix(".gguf")
            ? String(value.dropLast(5))
            : value
        let spaced = withoutExtension.replacingOccurrences(of: "_", with: " ")
        let trimmed = spaced.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Local model" : trimmed
    }

    private static func safeFileComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        let collapsed = String(scalars)
            .replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return collapsed.isEmpty ? "model" : String(collapsed.prefix(96))
    }
}

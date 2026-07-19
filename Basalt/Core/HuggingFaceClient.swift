import Foundation

enum HuggingFaceError: LocalizedError {
    case invalidURL
    case unsupportedHost
    case modelFileRequired
    case httpStatus(Int)
    case missingDownload

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Enter a complete HTTPS Hugging Face URL."
        case .unsupportedHost:
            "Basalt only downloads pasted URLs from huggingface.co."
        case .modelFileRequired:
            "Paste a link to one .gguf file, not a repository or folder."
        case let .httpStatus(status):
            status == 401 || status == 403
                ? "Hugging Face denied the download. This model may need access approval or a token."
                : "Hugging Face returned HTTP \(status)."
        case .missingDownload:
            "The model download did not produce a file."
        }
    }
}

struct DownloadedModel: Sendable {
    let temporaryURL: URL
    let suggestedName: String
    let sourceURL: URL
}

struct HuggingFaceClient: Sendable {
    typealias ProgressHandler = @Sendable (ImportProgress) -> Void

    static func normalizedModelURL(from input: String) throws -> URL {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased()
        else {
            throw HuggingFaceError.invalidURL
        }

        guard host == "huggingface.co" || host == "www.huggingface.co" else {
            throw HuggingFaceError.unsupportedHost
        }
        components.host = "huggingface.co"

        var segments = components.percentEncodedPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        guard segments.count >= 5,
              segments.last?.removingPercentEncoding?.lowercased().hasSuffix(".gguf") == true
        else {
            throw HuggingFaceError.modelFileRequired
        }

        if let blobIndex = segments.firstIndex(of: "blob") {
            segments[blobIndex] = "resolve"
        }
        guard segments.contains("resolve") else {
            throw HuggingFaceError.modelFileRequired
        }

        components.percentEncodedPath = "/" + segments.joined(separator: "/")
        guard let url = components.url else { throw HuggingFaceError.invalidURL }
        return url
    }

    func download(
        from input: String,
        accessToken: String?,
        progress: @escaping ProgressHandler
    ) async throws -> DownloadedModel {
        let sourceURL = try Self.normalizedModelURL(from: input)
        var request = URLRequest(url: sourceURL)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("Basalt/0.1", forHTTPHeaderField: "User-Agent")
        if let token = accessToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let downloadDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BasaltDownloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
        let destination = downloadDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("gguf")

        progress(ImportProgress(phase: .preparing, fraction: nil))
        let operation = DownloadOperation(
            request: request,
            destination: destination,
            sourceURL: sourceURL,
            progress: progress
        )
        return try await operation.start()
    }
}

private final class DownloadOperation: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let request: URLRequest
    private let destination: URL
    private let sourceURL: URL
    private let progress: HuggingFaceClient.ProgressHandler
    private let lock = NSLock()

    private var continuation: CheckedContinuation<DownloadedModel, Error>?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var completed = false

    init(
        request: URLRequest,
        destination: URL,
        sourceURL: URL,
        progress: @escaping HuggingFaceClient.ProgressHandler
    ) {
        self.request = request
        self.destination = destination
        self.sourceURL = sourceURL
        self.progress = progress
    }

    func start() async throws -> DownloadedModel {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock {
                    self.continuation = continuation
                    let configuration = URLSessionConfiguration.ephemeral
                    configuration.waitsForConnectivity = true
                    configuration.timeoutIntervalForRequest = 120
                    configuration.timeoutIntervalForResource = 60 * 60 * 8
                    let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                    self.session = session
                    let task = session.downloadTask(with: request)
                    self.task = task
                    task.resume()
                }
            }
        } onCancel: {
            self.cancel()
        }
    }

    func cancel() {
        lock.withLock { task?.cancel() }
        finish(with: .failure(CancellationError()))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let hasTotal = totalBytesExpectedToWrite > 0
        progress(ImportProgress(
            phase: .downloading,
            fraction: hasTotal ? min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) : nil,
            completedBytes: totalBytesWritten,
            totalBytes: hasTotal ? totalBytesExpectedToWrite : nil
        ))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let response = downloadTask.response as? HTTPURLResponse else {
            finish(with: .failure(HuggingFaceError.missingDownload))
            return
        }
        guard 200..<300 ~= response.statusCode else {
            finish(with: .failure(HuggingFaceError.httpStatus(response.statusCode)))
            return
        }

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            let suggested = response.suggestedFilename
                ?? sourceURL.deletingPathExtension().lastPathComponent
            finish(with: .success(DownloadedModel(
                temporaryURL: destination,
                suggestedName: suggested,
                sourceURL: sourceURL
            )))
        } catch {
            finish(with: .failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            finish(with: .failure(error))
        }
    }

    private func finish(with result: Result<DownloadedModel, Error>) {
        let callback: CheckedContinuation<DownloadedModel, Error>? = lock.withLock {
            guard !completed else { return nil }
            completed = true
            let callback = continuation
            continuation = nil
            task = nil
            return callback
        }
        session?.finishTasksAndInvalidate()
        session = nil
        callback?.resume(with: result)
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}

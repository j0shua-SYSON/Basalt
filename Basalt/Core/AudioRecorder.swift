import AVFoundation
import Foundation

@MainActor
final class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published private(set) var isRecording = false

    private var recorder: AVAudioRecorder?
    private var outputURL: URL?

    func toggle(
        onFinished: @escaping (URL) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        if isRecording {
            stop(onFinished: onFinished)
        } else {
            requestPermissionAndStart(onError: onError)
        }
    }

    func cancel() {
        recorder?.stop()
        recorder = nil
        isRecording = false
        if let outputURL { try? FileManager.default.removeItem(at: outputURL) }
        outputURL = nil
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private func requestPermissionAndStart(onError: @escaping (Error) -> Void) {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                guard granted else {
                    onError(AudioRecorderError.permissionDenied)
                    return
                }
                do {
                    try self.start()
                } catch {
                    onError(error)
                }
            }
        }
    }

    private func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BasaltRecordings", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        recorder.prepareToRecord()
        guard recorder.record() else { throw AudioRecorderError.couldNotStart }
        self.recorder = recorder
        outputURL = url
        isRecording = true
    }

    private func stop(onFinished: @escaping (URL) -> Void) {
        recorder?.stop()
        recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false)
        if let outputURL {
            self.outputURL = nil
            onFinished(outputURL)
        }
    }
}

private enum AudioRecorderError: LocalizedError {
    case permissionDenied
    case couldNotStart

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Microphone access is off. Enable it for Basalt in Settings to record an audio attachment."
        case .couldNotStart:
            "Basalt could not start an audio recording."
        }
    }
}

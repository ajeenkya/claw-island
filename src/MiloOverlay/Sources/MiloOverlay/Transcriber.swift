import Foundation
import Speech

/// Transcribes audio using whisper-cpp CLI with SFSpeechRecognizer fallback
class Transcriber {
    private let config: MiloConfig

    init(config: MiloConfig) {
        self.config = config
    }

    /// Transcribe the audio file at the given path
    func transcribe(audioPath: String) async throws -> String {
        // Try whisper-cpp first
        if let result = try? await transcribeWithWhisper(audioPath: audioPath) {
            return result
        }
        // Fall back to macOS speech recognition
        return try await transcribeWithSpeechFramework(audioPath: audioPath)
    }

    // MARK: - Whisper CLI

    private func transcribeWithWhisper(audioPath: String) async throws -> String {
        let modelPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".openclaw/models/ggml-\(config.whisperModel).bin").path

        guard let whisperBin = ExecutableResolver.resolve(
            executable: "whisper-cli",
            preferredPaths: ["/opt/homebrew/bin/whisper-cli", "/usr/local/bin/whisper-cli"]
        ) else {
            throw TranscriberError.whisperNotFound
        }
        miloLog("🧠 Using whisper-cli at \(whisperBin)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: whisperBin)
        process.arguments = [
            "-m", modelPath,
            "-f", audioPath,
            "--no-timestamps",
            "-otxt"
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        // whisper-cpp with -otxt writes to <inputfile>.txt
        let txtPath = audioPath + ".txt"
        if let text = try? String(contentsOfFile: txtPath, encoding: .utf8) {
            try? FileManager.default.removeItem(atPath: txtPath)
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Fallback: read stdout
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: - macOS Speech Framework fallback

    private func transcribeWithSpeechFramework(audioPath: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
            guard let recognizer = recognizer, recognizer.isAvailable else {
                continuation.resume(throwing: TranscriberError.speechRecognizerUnavailable)
                return
            }

            let request = SFSpeechURLRecognitionRequest(url: URL(fileURLWithPath: audioPath))
            request.shouldReportPartialResults = false

            recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                if let result = result, result.isFinal {
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }
}

enum TranscriberError: Error, LocalizedError {
    case whisperNotFound
    case speechRecognizerUnavailable

    var errorDescription: String? {
        switch self {
        case .whisperNotFound: return "whisper-cpp not found in PATH"
        case .speechRecognizerUnavailable: return "Speech recognizer unavailable"
        }
    }
}

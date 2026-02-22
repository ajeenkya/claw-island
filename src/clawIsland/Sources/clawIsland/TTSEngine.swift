import Foundation
import Cocoa

/// Text-to-speech engine with multiple voice backends and sentence-by-sentence playback.
///
/// Supports two TTS backends:
/// 1. **Kokoro**: Local, open-source speech synthesis (requires Python venv + Kokoro library)
/// 2. **System**: macOS native voices via `/usr/bin/say` (always available)
///
/// Voice selection and engine preference are configured via ClawConfig.
/// Automatically falls back to system voices if Kokoro is unavailable.
/// Supports cancellation mid-speech via the `stop()` method.
///
/// - Note: Each call to `speakSentence()` blocks until speech completes (async via process termination)
/// - Audio output goes to the system's default audio output
class TTSEngine {
    /// Currently running text-to-speech process (system or Kokoro)
    private var currentProcess: Process?
    /// Whether speech has been cancelled; checked before starting speech
    private var cancelled = false
    /// Configuration with TTS engine and voice preferences
    private let config: ClawConfig

    /// Whether speech playback has been cancelled
    var isCancelled: Bool { cancelled }

    /// Initializes TTS engine with voice and engine configuration.
    ///
    /// - Parameter config: ClawConfig instance with ttsEngine and voice settings
    init(config: ClawConfig) {
        self.config = config
    }

    /// Speaks a single sentence using the configured TTS engine and voice.
    ///
    /// Attempts the preferred engine (Kokoro or system), falls back automatically if unavailable.
    /// Blocks until speech completes (async via process termination handling).
    /// Respects cancellation flag—returns immediately if `stop()` was called.
    ///
    /// - Parameter text: Sentence text to speak (usually < 500 chars)
    /// - Note: Text is automatically trimmed; empty text is a no-op
    /// - SeeAlso: `stop()` to cancel ongoing speech
    func speakSentence(_ text: String) async {
        guard !cancelled else { return }
        
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        if config.ttsEngine.lowercased() == "kokoro" {
            clawLog("🗣️ TTS engine: kokoro (\(config.kokoroVoice))")
            let ok = await speakWithKokoro(cleaned)
            if ok || cancelled {
                return
            }
            clawLog("⚠️ Kokoro TTS unavailable; falling back to system voice")
        }

        clawLog("🗣️ TTS engine: system (\(config.ttsVoice ?? "default"))")
        await speakWithSystem(cleaned)
    }
    
    private func speakWithSystem(_ cleaned: String) async {
        guard !cancelled else { return }
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            
            var arguments = [String]()
            if let voice = config.ttsVoice, !voice.isEmpty {
                arguments.append(contentsOf: ["-v", voice])
            }
            arguments.append(cleaned)
            
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            
            self.currentProcess = process
            
            process.terminationHandler = { _ in
                continuation.resume()
            }
            
            do {
                try process.run()
            } catch {
                clawLog("⚠️ TTS error: \(error)")
                continuation.resume()
            }
        }
    }
    
    private func speakWithKokoro(_ text: String) async -> Bool {
        guard !cancelled else { return false }
        
        guard let pythonPath = resolveKokoroPythonPath() else {
            clawLog("⚠️ Kokoro python runtime not found")
            return false
        }
        
        guard let scriptPath = resolveKokoroScriptPath() else {
            clawLog("⚠️ Kokoro script not found")
            return false
        }
        
        let outputPath = "/tmp/claw-island-kokoro-\(UUID().uuidString).wav"
        let synthesisSucceeded = await runProcess(
            executable: pythonPath,
            arguments: [
                scriptPath,
                "--text", text,
                "--voice", config.kokoroVoice,
                "--lang", config.kokoroLangCode,
                "--speed", String(config.kokoroSpeed),
                "--output", outputPath
            ],
            label: "Kokoro synth"
        )
        
        guard synthesisSucceeded, !cancelled else {
            try? FileManager.default.removeItem(atPath: outputPath)
            return false
        }
        
        let player = ExecutableResolver.resolve(executable: "afplay", preferredPaths: ["/usr/bin/afplay"]) ?? "/usr/bin/afplay"
        let played = await runProcess(
            executable: player,
            arguments: [outputPath],
            label: "Kokoro playback"
        )
        
        try? FileManager.default.removeItem(atPath: outputPath)
        return played
    }
    
    private func runProcess(executable: String, arguments: [String], label: String) async -> Bool {
        guard !cancelled else { return false }
        
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            
            let errPipe = Pipe()
            process.standardError = errPipe
            self.currentProcess = process
            
            process.terminationHandler = { proc in
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                if proc.terminationStatus != 0 {
                    let err = String(data: errData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !err.isEmpty {
                        clawLog("⚠️ \(label) failed: \(err.prefix(180))")
                    } else {
                        clawLog("⚠️ \(label) failed with status \(proc.terminationStatus)")
                    }
                }
                continuation.resume(returning: proc.terminationStatus == 0)
            }
            
            do {
                try process.run()
            } catch {
                clawLog("⚠️ \(label) launch error: \(error)")
                continuation.resume(returning: false)
            }
        }
    }
    
    private func resolveKokoroPythonPath() -> String? {
        if let configured = normalizedConfiguredPath(config.kokoroPythonPath),
           FileManager.default.isExecutableFile(atPath: configured) {
            return configured
        }
        
        let home = NSHomeDirectory()
        let venvPython = "\(home)/.openclaw/clawIsland/kokoro-venv/bin/python3"
        if FileManager.default.isExecutableFile(atPath: venvPython) {
            return venvPython
        }

        if let py311 = ExecutableResolver.resolve(
            executable: "python3.11",
            preferredPaths: ["/opt/homebrew/bin/python3.11", "/usr/local/bin/python3.11"]
        ) {
            return py311
        }
        
        return ExecutableResolver.resolve(
            executable: "python3",
            preferredPaths: ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
        )
    }
    
    private func resolveKokoroScriptPath() -> String? {
        let fileManager = FileManager.default
        
        if let configured = normalizedConfiguredPath(config.kokoroScriptPath),
           fileManager.fileExists(atPath: configured) {
            return configured
        }
        
        if let bundled = Bundle.main.path(forResource: "kokoro_tts", ofType: "py"),
           fileManager.fileExists(atPath: bundled) {
            return bundled
        }
        
        if let exeURL = Bundle.main.executableURL {
            let resourcesPath = exeURL.deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/kokoro_tts.py").path
            if fileManager.fileExists(atPath: resourcesPath) {
                return resourcesPath
            }
        }
        
        let cwd = fileManager.currentDirectoryPath
        let candidates = [
            "\(cwd)/scripts/kokoro_tts.py",
            "\(cwd)/../scripts/kokoro_tts.py",
            "\(NSHomeDirectory())/.openclaw/clawIsland/kokoro_tts.py"
        ]
        
        return candidates.first(where: { fileManager.fileExists(atPath: $0) })
    }
    
    private func normalizedConfiguredPath(_ value: String?) -> String? {
        guard var path = value?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            return nil
        }
        if path.hasPrefix("~") {
            path = (path as NSString).expandingTildeInPath
        }
        return path
    }
    
    /// Speaks full text as a single block without sentence splitting.
    ///
    /// Legacy fallback path for non-streaming responses. Equivalent to calling `speakSentence()`.
    ///
    /// - Parameter text: Complete text to speak
    func speak(_ text: String) async {
        await speakSentence(text)
    }

    /// Immediately cancels any in-progress speech playback.
    ///
    /// Terminates the underlying process and sets the cancellation flag.
    /// Safe to call when no speech is playing.
    func stop() {
        cancelled = true
        if let proc = currentProcess, proc.isRunning {
            proc.terminate()
        }
        currentProcess = nil
    }

    /// Resets the engine for a new interaction.
    ///
    /// Clears the cancellation flag and process reference.
    /// Call this before starting a new TTS sequence.
    func reset() {
        cancelled = false
        currentProcess = nil
    }
}

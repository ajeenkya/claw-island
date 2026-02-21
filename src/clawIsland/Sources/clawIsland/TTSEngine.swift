import Foundation
import Cocoa

/// Text-to-speech engine that supports sentence-by-sentence speaking.
/// Supports local system voices (`say`) and local Kokoro synthesis.
class TTSEngine {
    private var currentProcess: Process?
    private var cancelled = false
    private let config: MiloConfig
    
    var isCancelled: Bool { cancelled }

    init(config: MiloConfig) {
        self.config = config
    }

    /// Speak a single sentence. Returns when speech completes.
    func speakSentence(_ text: String) async {
        guard !cancelled else { return }
        
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        if config.ttsEngine.lowercased() == "kokoro" {
            miloLog("🗣️ TTS engine: kokoro (\(config.kokoroVoice))")
            let ok = await speakWithKokoro(cleaned)
            if ok || cancelled {
                return
            }
            miloLog("⚠️ Kokoro TTS unavailable; falling back to system voice")
        }

        miloLog("🗣️ TTS engine: system (\(config.ttsVoice ?? "default"))")
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
                miloLog("⚠️ TTS error: \(error)")
                continuation.resume()
            }
        }
    }
    
    private func speakWithKokoro(_ text: String) async -> Bool {
        guard !cancelled else { return false }
        
        guard let pythonPath = resolveKokoroPythonPath() else {
            miloLog("⚠️ Kokoro python runtime not found")
            return false
        }
        
        guard let scriptPath = resolveKokoroScriptPath() else {
            miloLog("⚠️ Kokoro script not found")
            return false
        }
        
        let outputPath = "/tmp/milo-kokoro-\(UUID().uuidString).wav"
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
                        miloLog("⚠️ \(label) failed: \(err.prefix(180))")
                    } else {
                        miloLog("⚠️ \(label) failed with status \(proc.terminationStatus)")
                    }
                }
                continuation.resume(returning: proc.terminationStatus == 0)
            }
            
            do {
                try process.run()
            } catch {
                miloLog("⚠️ \(label) launch error: \(error)")
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
    
    /// Speak full text as one block (legacy, non-streaming fallback)
    func speak(_ text: String) async {
        await speakSentence(text)
    }

    /// Cancel any in-progress speech immediately
    func stop() {
        cancelled = true
        if let proc = currentProcess, proc.isRunning {
            proc.terminate()
        }
        currentProcess = nil
    }
    
    /// Reset cancellation flag for new interaction
    func reset() {
        cancelled = false
        currentProcess = nil
    }
}

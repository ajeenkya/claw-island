import Foundation

/// Records microphone audio using ffmpeg subprocess.
/// Monitors audio levels by reading the growing WAV file.
@MainActor
class AudioRecorder: ObservableObject {
    private var process: Process?
    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0
    
    private var levelTimer: Timer?
    private var lastFileOffset: UInt64 = 44 // Skip WAV header
    
    let outputPath = "/tmp/milo-recording.wav"

    func startRecording() throws {
        // Kill any lingering ffmpeg
        if let proc = process, proc.isRunning {
            proc.terminate()
            proc.waitUntilExit()
        }
        process = nil
        
        // Remove old recording
        try? FileManager.default.removeItem(atPath: outputPath)
        
        guard let ffmpegPath = ExecutableResolver.resolve(
            executable: "ffmpeg",
            preferredPaths: ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
        ) else {
            throw AudioRecorderError.ffmpegNotFound
        }
        
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ffmpegPath)
        proc.arguments = [
            "-y",
            "-f", "avfoundation",
            "-i", ":default",
            "-ar", "16000",
            "-ac", "1",
            "-acodec", "pcm_s16le",
            outputPath
        ]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        
        try proc.run()
        self.process = proc
        self.isRecording = true
        self.lastFileOffset = 44
        miloLog("🎤 ffmpeg recording (PID: \(proc.processIdentifier), bin: \(ffmpegPath))")
        
        // Start reading levels from the WAV file
        startLevelMonitor()
    }

    func stopRecording() -> String {
        stopLevelMonitor()
        
        if let proc = process, proc.isRunning {
            proc.terminate()
            let deadline = Date().addingTimeInterval(3)
            while proc.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
            }
            if proc.isRunning {
                proc.interrupt()
            }
            miloLog("🛑 ffmpeg exit: \(proc.terminationStatus)")
        }
        process = nil
        isRecording = false
        audioLevel = 0.0
        
        let attrs = try? FileManager.default.attributesOfItem(atPath: outputPath)
        let size = (attrs?[.size] as? Int) ?? 0
        miloLog("📁 Recording file: \(size) bytes")
        
        return outputPath
    }
    
    // MARK: - Level Monitor (reads PCM samples from growing WAV file)
    
    private func startLevelMonitor() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.readCurrentLevel()
            }
        }
    }
    
    private func stopLevelMonitor() {
        levelTimer?.invalidate()
        levelTimer = nil
    }
    
    private func readCurrentLevel() {
        guard let handle = FileHandle(forReadingAtPath: outputPath) else { return }
        defer { try? handle.close() }
        
        // Get file size
        handle.seekToEndOfFile()
        let fileSize = handle.offsetInFile
        
        // Need at least some new data (1600 samples = 100ms at 16kHz)
        let chunkBytes: UInt64 = 3200 // 1600 samples × 2 bytes
        guard fileSize > lastFileOffset + chunkBytes else { return }
        
        // Read the latest chunk
        let readOffset = fileSize - chunkBytes
        handle.seek(toFileOffset: readOffset)
        let data = handle.readData(ofLength: Int(chunkBytes))
        guard data.count >= 2 else { return }
        
        lastFileOffset = fileSize
        
        // Calculate RMS from 16-bit PCM samples
        var sumSquares: Float = 0
        let sampleCount = data.count / 2
        
        data.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                let normalized = Float(samples[i]) / 32768.0
                sumSquares += normalized * normalized
            }
        }
        
        let rms = sqrt(sumSquares / Float(max(sampleCount, 1)))

        // Map RMS to a perceptual 0-1 range.
        // Typical speech RMS can look numerically small (~0.005-0.05), which made
        // the old linear mapping appear visually flat in the HUD visualizer.
        let clampedRMS = max(rms, 0.000001)
        let db = 20.0 * log10(clampedRMS) // usually around -60 dB (quiet) to -10 dB (loud speech)
        let dbNormalized = (db + 55.0) / 45.0 // -55 dB -> 0, -10 dB -> 1
        let linearFallback = min(rms * 5.0, 1.0) * 0.35
        var mappedLevel = max(dbNormalized, linearFallback)
        mappedLevel = min(max(mappedLevel, 0.0), 1.0)

        // Small noise gate to keep true silence at rest.
        let newLevel: Float = mappedLevel < 0.03 ? 0.0 : mappedLevel
        
        // Smooth: fast attack, moderate decay (keeps motion responsive while stable).
        if newLevel > audioLevel {
            audioLevel = audioLevel + (newLevel - audioLevel) * 0.78
        } else {
            audioLevel = audioLevel + (newLevel - audioLevel) * 0.32
        }
    }
}

enum AudioRecorderError: Error, LocalizedError {
    case ffmpegNotFound
    
    var errorDescription: String? {
        switch self {
        case .ffmpegNotFound:
            return "ffmpeg not found. Install it with `brew install ffmpeg`."
        }
    }
}

import Foundation

/// Records microphone audio using ffmpeg subprocess with real-time level monitoring.
///
/// Records 16kHz mono PCM audio to a growing WAV file, continuously monitoring audio levels
/// by reading PCM samples and converting them to dB-normalized values (0.0-1.0 range).
/// Uses exponential smoothing with asymmetric attack/decay for responsive yet stable visualization.
///
/// Audio levels are calculated from RMS values with dB-based normalization:
/// - Quiet speech (-55 dB) maps to 0.0
/// - Loud speech (-10 dB) maps to 1.0
/// - Includes noise gate to suppress true silence below 0.03 threshold
///
/// - Parameters: None. Configuration is via ffmpeg arguments (16kHz mono, pcm_s16le codec)
/// - Output: WAV file written to `/tmp/milo-recording.wav`
/// - Requires: ffmpeg installed and in PATH
@MainActor
class AudioRecorder: ObservableObject {
    /// Underlying ffmpeg process for audio capture
    private var process: Process?
    /// Whether audio is currently being recorded
    @Published var isRecording = false
    /// Current audio level (0.0 = silence, 1.0 = loud speech). Updated via level monitoring.
    @Published var audioLevel: Float = 0.0
    
    private var levelTimer: Timer?
    private var lastFileOffset: UInt64 = 44 // Skip WAV header
    
    let outputPath = "/tmp/milo-recording.wav"

    /// Starts recording audio from the default microphone.
    ///
    /// Spawns an ffmpeg process to capture audio at 16kHz mono (pcm_s16le).
    /// Automatically starts the level monitoring timer.
    /// Cleans up any existing recording before starting.
    ///
    /// - Throws: `AudioRecorderError.ffmpegNotFound` if ffmpeg is not available in PATH
    /// - Note: Requires microphone permission to be granted in System Settings
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

    /// Stops recording audio and returns the path to the recorded WAV file.
    ///
    /// Terminates the ffmpeg process gracefully with a 3-second timeout.
    /// Resets the audio level to 0.0 and stops the level monitoring timer.
    ///
    /// - Returns: The path to the recorded WAV file (`/tmp/milo-recording.wav`)
    /// - Note: The WAV file persists after this call; the caller is responsible for cleanup if needed
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
            guard let strongSelf = self else { return }
            Task { @MainActor in
                strongSelf.readCurrentLevel()
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

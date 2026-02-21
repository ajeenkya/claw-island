import Foundation
import Speech
import AVFoundation

/// Live speech-to-text using Apple's SFSpeechRecognizer.
/// Provides real-time partial transcripts while recording.
@MainActor
class LiveTranscriber: ObservableObject {
    @Published var partialText: String = ""
    @Published var finalText: String = ""
    @Published var isRunning: Bool = false
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    
    /// Start live transcription. Runs on-device speech recognition in parallel with ffmpeg recording.
    func start() {
        guard !isRunning else { return }
        
        partialText = ""
        finalText = ""
        
        // Check authorization
        guard speechRecognizer?.isAvailable == true else {
            miloLog("⚠️ SFSpeechRecognizer not available")
            return
        }
        
        miloLog("🎤 Starting live transcription...")
        
        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true  // Keep it local, fast, private
        
        // Tap the mic input and feed to recognizer
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        miloLog("🔊 Audio format: \(recordingFormat.sampleRate) Hz, \(recordingFormat.channelCount) channels")
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }
        
        do {
            try engine.start()
            miloLog("✅ Audio engine started successfully")
        } catch {
            miloLog("⚠️ LiveTranscriber engine start failed: \(error)")
            return
        }
        
        self.audioEngine = engine
        self.recognitionRequest = request
        self.isRunning = true
        
        // Start recognition
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                let text = result.bestTranscription.formattedString
                miloLog("🔍 Live transcript update: '\(text)' (final: \(result.isFinal))")
                Task { @MainActor in
                    if result.isFinal {
                        self.finalText = text
                        self.partialText = text
                        miloLog("🎯 Live final: \(text)")
                    } else {
                        self.partialText = text
                    }
                }
            }
            
            if let error = error {
                // Errors during recognition are common (silence timeouts, etc.)
                // Only log if we care
                let nsError = error as NSError
                if nsError.code != 1110 { // 1110 = "no speech detected" — normal
                    miloLog("⚠️ LiveTranscriber: \(error.localizedDescription)")
                }
            }
        }
        
        miloLog("🎙️ Live transcription started")
    }
    
    /// Stop live transcription and return the best transcript.
    func stop() -> String {
        miloLog("🛑 Stopping live transcription...")
        
        recognitionRequest?.endAudio()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRunning = false
        
        // Return final if available, otherwise partial
        let result = finalText.isEmpty ? partialText : finalText
        miloLog("🎙️ Live transcription stopped: '\(result)' (length: \(result.count))")
        return result
    }
    
    /// Request speech recognition permission (call once at app startup)
    static func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { status in
            switch status {
            case .authorized:
                miloLog("✅ Speech recognition authorized")
            case .denied:
                miloLog("❌ Speech recognition denied")
            case .restricted:
                miloLog("⚠️ Speech recognition restricted")
            case .notDetermined:
                miloLog("⚠️ Speech recognition not determined")
            @unknown default:
                break
            }
        }
    }
}

import SwiftUI
import Cocoa
import AVFoundation
import ApplicationServices
import QuartzCore

func miloLog(_ msg: String) {
    let line = "[\(Date())] \(msg)\n"
    let logPath = NSHomeDirectory() + "/.openclaw/milo-overlay.log"
    if let handle = FileHandle(forWritingAtPath: logPath) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: logPath, contents: line.data(using: .utf8))
    }
    print(msg)
    fflush(stdout)
}

@main
struct MiloOverlayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}

enum MiloState: Equatable, CustomStringConvertible {
    case idle
    case recording
    case processing
    case speaking(String)
    
    var description: String {
        switch self {
        case .idle: return "idle"
        case .recording: return "recording"
        case .processing: return "processing"
        case .speaking: return "speaking"
        }
    }
    
    static func == (lhs: MiloState, rhs: MiloState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.recording, .recording), (.processing, .processing):
            return true
        case (.speaking(let a), .speaking(let b)):
            return a == b
        default:
            return false
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotkeyManager = HotkeyManager()
    private var audioRecorder = AudioRecorder()
    private var liveTranscriber = LiveTranscriber()
    private var config = MiloConfig.load()
    private var recordingTimer: Timer?
    private var hudUpdateTimer: Timer?
    
    /// Persistent OpenClaw client — keeps conversation buffer across interactions
    private lazy var openClawClient = OpenClawClient(config: config)
    
    // HUD
    private var hudWindow: HUDWindow?
    private var hudHostView: NSHostingView<RecordingHUD>?
    private let hudModel = HUDModel()
    private let collapsedHudSize = NSSize(width: 190, height: 34)
    private var transcript: String = ""
    
    private var state: MiloState = .idle {
        didSet {
            updateMenuBarIcon()
            updateHUD()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        miloLog("🚀 MiloOverlay launched")
        requestPermissions()
        setupMenuBar()
        setupHotkey()
        miloLog("✅ Ready — press \(config.hotkey) to toggle recording")
    }
    
    private func requestPermissions() {
        requestAccessibilityPermission()
        
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            miloLog(granted ? "✅ Microphone authorized" : "❌ Microphone denied")
        }
        
        // Request speech recognition permission
        LiveTranscriber.requestAuthorization()
        
        miloLog("🎤 Requested microphone + speech recognition permissions")
    }
    
    private func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if trusted {
            miloLog("✅ Accessibility authorized")
        } else {
            miloLog("⚠️ Accessibility not granted — global hotkey will not work until enabled")
        }
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateMenuBarIcon()
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Toggle Recording", action: #selector(toggleFromMenu), keyEquivalent: ""))
        menu.addItem(.separator())

        let engineMenu = NSMenu(title: "Speech Engine")
        let engineMenuItem = NSMenuItem(title: "Speech Engine", action: nil, keyEquivalent: "")
        engineMenuItem.submenu = engineMenu
        populateSpeechEngineMenu(engineMenu)
        menu.addItem(engineMenuItem)
        
        // Voice selection submenu
        let voiceMenu = NSMenu(title: "Voice")
        let voiceMenuItem = NSMenuItem(title: "Voice", action: nil, keyEquivalent: "")
        voiceMenuItem.submenu = voiceMenu
        populateVoiceMenu(voiceMenu)
        menu.addItem(voiceMenuItem)
        
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit MiloOverlay", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func updateMenuBarIcon() {
        guard let button = statusItem?.button else { return }
        let image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Milo")
        switch state {
        case .recording:
            button.image = image?.withSymbolConfiguration(.init(paletteColors: [.systemRed]))
        case .processing:
            button.image = image?.withSymbolConfiguration(.init(paletteColors: [.systemYellow]))
        case .speaking:
            button.image = image?.withSymbolConfiguration(.init(paletteColors: [.systemGreen]))
        case .idle:
            button.image = image
        }
    }

    // MARK: - HUD
    
    private func showHUD() {
        if hudWindow == nil {
            hudWindow = HUDWindow()
        }
        guard let window = hudWindow else { return }
        
        if hudHostView == nil {
            let hostView = NSHostingView(rootView: RecordingHUD(model: hudModel))
            hudHostView = hostView
            window.contentView = hostView
        }
        guard let hostView = hudHostView else { return }
        
        if !window.isVisible {
            let collapsedFrame = hudFrame(for: collapsedHudSize)
            
            // Stage 1: render compact notch before expansion.
            hudModel.state = .idle
            hudModel.transcript = ""
            hudModel.audioLevel = 0
            hostView.layoutSubtreeIfNeeded()
            
            window.alphaValue = 1
            window.setFrame(collapsedFrame, display: true)
            window.orderFrontRegardless()
            
            // Stage 2: morph notch into the live state size.
            applyHUDModel()
            let targetFrame = hudFrame(for: measuredHUDSize(hostView: hostView))
            let overshootFrame = NSRect(
                x: targetFrame.origin.x - (targetFrame.width * 0.01),
                y: targetFrame.origin.y - (targetFrame.height * 0.01),
                width: targetFrame.width * 1.02,
                height: targetFrame.height * 1.02
            )
            
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.17
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(overshootFrame, display: true)
            } completionHandler: {
                NSAnimationContext.runAnimationGroup { settle in
                    settle.duration = 0.11
                    settle.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    window.animator().setFrame(targetFrame, display: true)
                }
            }
        } else {
            updateHUDContent(animated: true)
            window.orderFrontRegardless()
        }
    }
    
    private func hideHUD() {
        guard let window = hudWindow, let hostView = hudHostView else { return }
        let currentFrame = window.frame
        let collapsedFrame = hudFrame(for: collapsedHudSize)
        
        // Collapse visual content into notch before dismissing.
        hudModel.state = .idle
        hudModel.transcript = ""
        hudModel.audioLevel = 0
        hostView.layoutSubtreeIfNeeded()
        
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(collapsedFrame, display: true)
            window.animator().alphaValue = 0.9
        }) {
            window.orderOut(nil)
            window.alphaValue = 1
            window.setFrame(currentFrame, display: false)
        }
    }
    
    private func updateHUD() {
        switch state {
        case .idle:
            hideHUD()
            transcript = ""
        case .recording, .processing, .speaking:
            showHUD()
            updateHUDContent(animated: true)
        }
    }
    
    private func updateHUDContent(animated: Bool = false) {
        guard let window = hudWindow, let hostView = hudHostView else { return }
        
        applyHUDModel()
        let targetFrame = hudFrame(for: measuredHUDSize(hostView: hostView))
        
        if animated, window.isVisible {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.16
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(targetFrame, display: true)
            }
        } else {
            window.setFrame(targetFrame, display: true)
        }
    }
    
    private func hudFrame(for size: NSSize) -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(x: 0, y: 0, width: size.width, height: size.height)
        }
        
        let screenFrame = screen.frame
        let x = screenFrame.midX - size.width / 2
        let y = screenFrame.maxY - size.height
        
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
    
    private func applyHUDModel() {
        hudModel.state = state
        hudModel.transcript = transcript
        hudModel.audioLevel = audioRecorder.audioLevel
    }
    
    private func measuredHUDSize(hostView: NSHostingView<RecordingHUD>) -> NSSize {
        hostView.layoutSubtreeIfNeeded()
        let fittingSize = hostView.fittingSize
        return NSSize(width: max(fittingSize.width, 220), height: max(fittingSize.height, 60))
    }

    // MARK: - Hotkey

    private func setupHotkey() {
        hotkeyManager.onToggle = { [weak self] in
            self?.handleToggle()
        }
        hotkeyManager.register(hotkey: config.hotkey)
    }

    // MARK: - Toggle (configured hotkey press)
    
    private func handleToggle() {
        miloLog("🔄 toggle, state: \(state)")
        switch state {
        case .idle:
            startRecording()
        case .recording:
            stopRecording()
        case .processing:
            miloLog("⏳ processing, ignoring")
        case .speaking:
            miloLog("🔇 cancelling speech, going idle")
            ttsEngine?.stop()
            state = .idle
        }
    }

    private func startRecording() {
        do {
            transcript = ""
            try audioRecorder.startRecording()
            liveTranscriber.start()
            state = .recording
            miloLog("🎙️ RECORDING — press \(config.hotkey) again to stop")
            
            // Update HUD with audio levels + live transcript ~30fps
            hudUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self = self else { return }
                    // Feed live transcript to HUD
                    let partial = self.liveTranscriber.partialText
                    if !partial.isEmpty {
                        self.transcript = partial
                    }
                    self.updateHUDContent(animated: false)
                }
            }
            
            // Auto-stop after max duration
            recordingTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(config.maxRecordingSeconds), repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.stopRecording()
                }
            }
        } catch {
            miloLog("❌ Failed to start recording: \(error)")
            state = .idle
        }
    }

    private func stopRecording() {
        guard state == .recording else { return }
        recordingTimer?.invalidate()
        recordingTimer = nil
        hudUpdateTimer?.invalidate()
        hudUpdateTimer = nil
        
        // Stop both recorders
        let _ = audioRecorder.stopRecording()
        let liveText = liveTranscriber.stop()
        
        state = .processing
        miloLog("⏳ Processing...")

        Task {
            await processWithText(liveText)
        }
    }

    // MARK: - Pipeline

    private var ttsEngine: TTSEngine?

    private func processWithText(_ liveText: String) async {
        do {
            var text = liveText.trimmingCharacters(in: .whitespacesAndNewlines)
            miloLog("📝 Live transcript result: '\(text)' (length: \(text.count))")
            
            // Fix #2: Only fall back to Whisper if live transcript is completely empty.
            // SFSpeechRecognizer is usually good enough — don't waste time on Whisper
            // for short but valid transcripts like "hi" or "yes".
            if text.isEmpty {
                miloLog("⚠️ Live transcript empty, falling back to Whisper...")
                let transcriber = Transcriber(config: config)
                text = try await transcriber.transcribe(audioPath: audioRecorder.outputPath)
                miloLog("📝 Whisper fallback result: '\(text)' (length: \(text.count))")
            }
            
            if text.isEmpty || text == "[BLANK_AUDIO]" {
                miloLog("⚠️ No speech detected")
                state = .idle
                return
            }
            miloLog("💬 Final transcript: \(text)")
            
            // Update HUD with final transcript
            transcript = text
            updateHUDContent(animated: true)

            miloLog("📡 Sending with configured OpenClaw session routing: \(text)")
            let screenshotPath: String?
            if config.screenshotOnTrigger {
                screenshotPath = await ScreenCapture.captureActiveWindow()
                if let screenshotPath = screenshotPath {
                    miloLog("📸 Screenshot captured: \(screenshotPath)")
                } else {
                    miloLog("⚠️ Screenshot capture failed; continuing without image context")
                }
            } else {
                screenshotPath = nil
            }
            
            let engine = TTSEngine(config: config)
            engine.reset()
            ttsEngine = engine
            
            // Get response via config-driven OpenClaw request (agentId/sessionKey from config)
            let fullResponse = try await openClawClient.sendMessage(text: text, screenshotPath: screenshotPath)
            miloLog("✅ Got response: \(fullResponse.count) chars")
            
            // Speak sentence-by-sentence and mirror current spoken text in the HUD.
            let segments = speechSegments(from: fullResponse)
            if segments.isEmpty {
                state = .speaking(fullResponse)
                await engine.speak(fullResponse)
            } else {
                for segment in segments {
                    if engine.isCancelled || state == .idle { break }
                    state = .speaking(segment)
                    await engine.speakSentence(segment)
                }
            }
            
            ttsEngine = nil
            if state != .idle {
                miloLog("✅ Done")
                state = .idle
            } else {
                miloLog("✅ Done (cancelled)")
            }
        } catch {
            miloLog("❌ Pipeline error: \(error)")
            state = .idle
        }
    }

    private func speechSegments(from text: String) -> [String] {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return [] }
        
        var segments: [String] = []
        var current = ""
        let terminators: Set<Character> = [".", "!", "?", "\n"]
        
        for char in cleaned {
            current.append(char)
            if terminators.contains(char) {
                let part = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !part.isEmpty {
                    segments.append(part)
                }
                current = ""
            }
        }
        
        let trailing = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trailing.isEmpty {
            segments.append(trailing)
        }
        
        return segments
    }

    // MARK: - Menu Actions

    @objc private func toggleFromMenu() { handleToggle() }
    
    @objc private func quitApp() {
        hotkeyManager.unregister()
        NSApplication.shared.terminate(nil)
    }
    
    // MARK: - Voice Selection
    
    private func getSystemVoices() -> [String] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        task.arguments = ["-v", "?"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            // Parse voice list - each line format: "VoiceName locale # Description"
            let voices = output
                .components(separatedBy: .newlines)
                .compactMap(parseVoiceName(from:))
            
            return Array(Set(voices)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        } catch {
            miloLog("⚠️ Failed to get voices: \(error)")
            return ["Samantha (English (US))", "Daniel (English (UK))", "Fred (English (US))"]
        }
    }
    
    private func parseVoiceName(from line: String) -> String? {
        let withoutDescription = line.components(separatedBy: "#").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !withoutDescription.isEmpty else { return nil }
        
        let tokens = withoutDescription.split(whereSeparator: \.isWhitespace)
        guard !tokens.isEmpty else { return nil }
        
        if let localeIndex = tokens.firstIndex(where: { isLocaleToken(String($0)) }), localeIndex > 0 {
            return tokens[..<localeIndex].map(String.init).joined(separator: " ")
        }
        
        return String(tokens[0])
    }
    
    private func isLocaleToken(_ token: String) -> Bool {
        token.range(of: #"^[a-z]{2}_[A-Z]{2}$"#, options: .regularExpression) != nil
    }
    
    private func normalizedTTSEngine() -> String {
        config.ttsEngine.lowercased() == "kokoro" ? "kokoro" : "system"
    }
    
    private func populateSpeechEngineMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let current = normalizedTTSEngine()
        let options: [(id: String, title: String)] = [
            ("system", "System (Apple voices)"),
            ("kokoro", "Kokoro (local open-source)")
        ]
        
        for option in options {
            let item = NSMenuItem(title: option.title, action: #selector(selectSpeechEngine(_:)), keyEquivalent: "")
            item.representedObject = option.id
            item.target = self
            item.state = (option.id == current) ? .on : .off
            menu.addItem(item)
        }
    }
    
    private func getKokoroVoices() -> [(name: String, description: String)] {
        [
            ("af_heart", "Balanced female (recommended)")
        ]
    }
    
    private func getPopularVoices() -> [(name: String, description: String)] {
        return [
            ("Samantha (English (US))", "Default female"),
            ("Daniel (English (UK))", "British male"),
            ("Karen (English (AU))", "Australian female"),
            ("Fred (English (US))", "Classic male"),
            ("Eddy (English (US))", "Neural male"),
            ("Flo (English (US))", "Neural female"),
            ("Whisper", "Soft whisper"),
            ("Zarvox", "Robot voice")
        ]
    }
    
    private func populateVoiceMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let engine = normalizedTTSEngine()
        
        if engine == "kokoro" {
            let currentVoice = config.kokoroVoice
            for (voice, description) in getKokoroVoices() {
                let item = NSMenuItem(title: "\(voice) - \(description)", action: #selector(selectKokoroVoice(_:)), keyEquivalent: "")
                item.representedObject = voice
                item.target = self
                if voice == currentVoice {
                    item.state = .on
                }
                menu.addItem(item)
            }
            
            menu.addItem(.separator())
            let hint = NSMenuItem(title: "Custom via ~/.openclaw/milo-overlay.json → kokoroVoice", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
            return
        }
        
        let currentVoice = config.ttsVoice ?? "Samantha (English (US))"
        
        // Add popular voices first
        let popularVoices = getPopularVoices()
        for (voice, description) in popularVoices {
            let item = NSMenuItem(title: "\(voice) - \(description)", action: #selector(selectVoice(_:)), keyEquivalent: "")
            item.representedObject = voice
            item.target = self
            if voice == currentVoice {
                item.state = .on
            }
            menu.addItem(item)
        }
        
        menu.addItem(.separator())
        
        let allVoicesItem = NSMenuItem(title: "All System Voices", action: nil, keyEquivalent: "")
        let allVoicesMenu = NSMenu(title: "All System Voices")
        allVoicesItem.submenu = allVoicesMenu
        
        let popularVoiceNames = Set(popularVoices.map(\.name))
        let allVoices = getSystemVoices().filter { !popularVoiceNames.contains($0) }
        
        for voiceName in allVoices {
            let item = NSMenuItem(title: voiceName, action: #selector(selectVoice(_:)), keyEquivalent: "")
            item.representedObject = voiceName
            item.target = self
            if voiceName == currentVoice {
                item.state = .on
            }
            allVoicesMenu.addItem(item)
        }
        
        if allVoices.isEmpty {
            let noneItem = NSMenuItem(title: "No additional voices found", action: nil, keyEquivalent: "")
            noneItem.isEnabled = false
            allVoicesMenu.addItem(noneItem)
        }
        
        menu.addItem(allVoicesItem)
    }
    
    @objc private func selectSpeechEngine(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        let selected = value == "kokoro" ? "kokoro" : "system"
        guard selected != normalizedTTSEngine() else { return }
        
        config.ttsEngine = selected
        do {
            try config.save()
            miloLog("✅ TTS engine changed to: \(selected)")
            refreshSpeechMenus()
        } catch {
            miloLog("❌ Failed to save TTS engine config: \(error)")
            return
        }
        
        Task { [config] in
            let preview = TTSEngine(config: config)
            preview.reset()
            let line = selected == "kokoro" ? "Kokoro voice enabled." : "System voice enabled."
            await preview.speakSentence(line)
        }
    }
    
    @objc private func selectVoice(_ sender: NSMenuItem) {
        guard let voiceName = sender.representedObject as? String else { return }
        
        // Test the voice first
        testVoice(voiceName) { [weak self] success in
            DispatchQueue.main.async {
                if success {
                    self?.updateVoiceConfig(voiceName)
                } else {
                    self?.showVoiceError(voiceName)
                }
            }
        }
    }
    
    @objc private func selectKokoroVoice(_ sender: NSMenuItem) {
        guard let voiceName = sender.representedObject as? String else { return }
        updateKokoroVoiceConfig(voiceName)
        
        Task { [config] in
            let preview = TTSEngine(config: config)
            preview.reset()
            await preview.speakSentence("Kokoro voice set to \(voiceName).")
        }
    }
    
    private func testVoice(_ voiceName: String, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            task.arguments = ["-v", voiceName, "Voice changed to \(voiceName)"]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            
            do {
                try task.run()
                task.waitUntilExit()
                completion(task.terminationStatus == 0)
            } catch {
                completion(false)
            }
        }
    }
    
    private func updateVoiceConfig(_ voiceName: String) {
        config.ttsVoice = voiceName
        
        do {
            try config.save()
            miloLog("✅ Voice changed to: \(voiceName)")
            refreshSpeechMenus()
        } catch {
            miloLog("❌ Failed to save voice config: \(error)")
        }
    }
    
    private func updateKokoroVoiceConfig(_ voiceName: String) {
        config.kokoroVoice = voiceName
        
        do {
            try config.save()
            miloLog("✅ Kokoro voice changed to: \(voiceName)")
            refreshSpeechMenus()
        } catch {
            miloLog("❌ Failed to save Kokoro voice config: \(error)")
        }
    }
    
    private func refreshSpeechMenus() {
        if let engineMenu = statusItem.menu?.item(withTitle: "Speech Engine")?.submenu {
            populateSpeechEngineMenu(engineMenu)
        }
        if let voiceMenu = statusItem.menu?.item(withTitle: "Voice")?.submenu {
            populateVoiceMenu(voiceMenu)
        }
    }
    
    private func showVoiceError(_ voiceName: String) {
        let alert = NSAlert()
        alert.messageText = "Voice Not Available"
        alert.informativeText = "The voice '\(voiceName)' is not available on this system."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
}

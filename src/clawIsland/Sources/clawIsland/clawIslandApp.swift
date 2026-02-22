import SwiftUI
import Cocoa
import AVFoundation
import ApplicationServices
import QuartzCore

func clawLog(_ msg: String) {
    let line = "[\(Date())] \(msg)\n"
    let logPath = NSHomeDirectory() + "/.openclaw/clawIsland.log"
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
struct clawIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}

enum ClawState: Equatable, CustomStringConvertible {
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
    
    static func == (lhs: ClawState, rhs: ClawState) -> Bool {
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
    private struct PendingSelectionRewrite {
        let original: String
        let rewritten: String
        let request: String
    }
    
    private var statusItem: NSStatusItem!
    private var hotkeyManager = HotkeyManager()
    private var audioRecorder = AudioRecorder()
    private var liveTranscriber = LiveTranscriber()
    private var config = ClawConfig.load()
    private var recordingTimer: Timer?
    private var hudUpdateTimer: Timer?
    
    /// Persistent OpenClaw client — keeps conversation buffer across interactions
    private lazy var openClawClient = OpenClawClient(config: config)
    
    // HUD
    private var hudWindow: HUDWindow?
    private var hudHostView: NSHostingView<RecordingHUD>?
    private let hudModel = HUDModel()
    private let collapsedHudSize = NSSize(width: 400, height: 34)
    private let activeHudWidth: CGFloat = 400
    private var lastMeasuredHUDSize = NSSize(width: 0, height: 0)
    private let hudShowFadeDuration: TimeInterval = 0.10
    private let hudHideFadeDuration: TimeInterval = 0.10
    private var openedAccessibilitySettingsThisLaunch = false
    private var transcript: String = ""
    private var pendingSelectionRewrite: PendingSelectionRewrite?
    private let bridgeScriptPath = NSHomeDirectory() + "/.openclaw/workspace/skills/claw-island-desktop-actions/scripts/claw_bridge.py"
    private var committedLiveTranscript: String = ""
    private var currentLivePartial: String = ""
    private var lastLivePartialAt: Date?
    private let livePauseResetThreshold: TimeInterval = 0.65
    
    private var state: ClawState = .idle {
        didSet {
            updateMenuBarIcon()
            updateHUD()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        clawLog("🚀 clawIsland launched")
        requestPermissions()
        setupMenuBar()
        setupHotkey()
        clawLog("✅ Ready — press \(config.hotkey) to toggle recording")
    }
    
    private func requestPermissions() {
        requestAccessibilityPermission()
        
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            clawLog(granted ? "✅ Microphone authorized" : "❌ Microphone denied")
        }
        
        // Request speech recognition permission
        LiveTranscriber.requestAuthorization()
        
        clawLog("🎤 Requested microphone + speech recognition permissions")
    }
    
    private func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if trusted {
            clawLog("✅ Accessibility authorized")
        } else {
            clawLog("⚠️ Accessibility not granted — global hotkey will not work until enabled")
            openAccessibilitySettingsIfNeeded()
        }
    }
    
    private func openAccessibilitySettingsIfNeeded() {
        guard !openedAccessibilitySettingsThisLaunch else { return }
        openedAccessibilitySettingsThisLaunch = true
        
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
        clawLog("↗️ Opened System Settings → Privacy & Security → Accessibility")
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
        menu.addItem(NSMenuItem(title: "Quit clawIsland", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func updateMenuBarIcon() {
        guard let button = statusItem?.button else { return }
        let image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Claw Island")
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
            hostView.wantsLayer = true
            hostView.layer?.backgroundColor = NSColor.clear.cgColor
            hudHostView = hostView
            window.contentView = hostView
        }
        guard let hostView = hudHostView else { return }
        
        if !window.isVisible {
            // Keep geometry fixed (no y/height animation) to avoid top-edge gap artifacts.
            applyHUDModel()
            let targetFrame = hudFrame(for: measuredHUDSize(hostView: hostView))
            window.alphaValue = 0
            window.setFrame(targetFrame, display: true)
            window.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = hudShowFadeDuration
                ctx.timingFunction = CAMediaTimingFunction(name: .linear)
                window.animator().alphaValue = 1.0
            }
        } else {
            updateHUDContent(animated: false)
            window.orderFrontRegardless()
        }
    }
    
    private func hideHUD() {
        guard let window = hudWindow, let hostView = hudHostView else { return }
        hostView.layoutSubtreeIfNeeded()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = hudHideFadeDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .linear)
            window.animator().alphaValue = 0.0
        }) {
            Task { @MainActor in
                window.orderOut(nil)
                window.alphaValue = 1
                self.hudModel.state = .idle
                self.hudModel.transcript = ""
                self.hudModel.audioLevel = 0
                self.lastMeasuredHUDSize = NSSize(width: 0, height: 0)
            }
        }
    }
    
    private func updateHUD() {
        switch state {
        case .idle:
            hideHUD()
            transcript = ""
        case .recording, .processing, .speaking:
            showHUD()
            // Keep geometry stable while visible: only animate on show and hide.
            updateHUDContent(animated: false)
        }
    }
    
    private func updateHUDContent(animated: Bool = false) {
        guard let window = hudWindow, let hostView = hudHostView else { return }
        
        applyHUDModel()
        let measuredSize = measuredHUDSize(hostView: hostView)
        let needsResize = abs(measuredSize.width - lastMeasuredHUDSize.width) > 0.5 || abs(measuredSize.height - lastMeasuredHUDSize.height) > 0.5
        
        guard needsResize else { return }
        lastMeasuredHUDSize = measuredSize
        
        let targetFrame = hudFrame(for: measuredSize)

        // CRITICAL UX GUARDRAIL:
        // Never animate HUD frame geometry again. Geometry interpolation can create
        // a visible top-edge gap; we only animate opacity on show/hide.
        window.setFrame(targetFrame, display: true)
    }
    
    private func hudFrame(for size: NSSize) -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(x: 0, y: 0, width: size.width, height: size.height)
        }
        
        let screenFrame = screen.frame
        let scale = max(screen.backingScaleFactor, 1)
        let width = ceil(size.width * scale) / scale
        let height = ceil(size.height * scale) / scale
        let x = round((screenFrame.midX - width / 2) * scale) / scale
        // Use ceil so the top edge never lands below the screen edge due to fractional rounding.
        let y = ceil((screenFrame.maxY - height) * scale) / scale
        
        return NSRect(x: x, y: y, width: width, height: height)
    }
    
    private func applyHUDModel() {
        hudModel.state = state
        hudModel.transcript = transcript
        hudModel.audioLevel = audioRecorder.audioLevel
    }
    
    private func measuredHUDSize(hostView: NSHostingView<RecordingHUD>) -> NSSize {
        hostView.layoutSubtreeIfNeeded()
        let fittingSize = hostView.fittingSize
        let width = (state == .idle) ? collapsedHudSize.width : activeHudWidth
        let minHeight: CGFloat = (state == .idle) ? collapsedHudSize.height : 60
        return NSSize(width: width, height: max(fittingSize.height, minHeight))
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
        clawLog("🔄 toggle, state: \(state)")
        switch state {
        case .idle:
            startRecording()
        case .recording:
            stopRecording()
        case .processing:
            clawLog("⏳ processing, ignoring")
        case .speaking:
            clawLog("🔇 cancelling speech, going idle")
            ttsEngine?.stop()
            state = .idle
        }
    }

    private func startRecording() {
        do {
            transcript = ""
            committedLiveTranscript = ""
            currentLivePartial = ""
            lastLivePartialAt = nil
            try audioRecorder.startRecording()
            liveTranscriber.start()
            state = .recording
            clawLog("🎙️ RECORDING — press \(config.hotkey) again to stop")
            
            // Update HUD with audio levels + live transcript ~30fps
            hudUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { [weak self] _ in
                guard let strongSelf = self else { return }
                Task { @MainActor in
                    // Feed live transcript to HUD
                    let partial = strongSelf.liveTranscriber.partialText
                    if !partial.isEmpty {
                        strongSelf.ingestLivePartial(partial)
                    }
                    strongSelf.updateHUDContent(animated: false)
                }
            }
            
            // Auto-stop after max duration
            recordingTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(config.maxRecordingSeconds), repeats: false) { [weak self] _ in
                guard let strongSelf = self else { return }
                Task { @MainActor in
                    strongSelf.stopRecording()
                }
            }
        } catch {
            clawLog("❌ Failed to start recording: \(error)")
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
        let liveText = finalizeLiveTranscript(with: liveTranscriber.stop())
        
        state = .processing
        clawLog("⏳ Processing...")

        Task {
            await processWithText(liveText)
        }
    }

    // MARK: - Pipeline

    private var ttsEngine: TTSEngine?

    private func ingestLivePartial(_ rawPartial: String) {
        let partial = rawPartial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !partial.isEmpty else { return }
        
        let now = Date()
        let gap = now.timeIntervalSince(lastLivePartialAt ?? now)
        
        if shouldStartNewLiveSegment(current: currentLivePartial, candidate: partial, gap: gap) {
            committedLiveTranscript = appendSegment(committedLiveTranscript, segment: currentLivePartial)
            currentLivePartial = partial
        } else {
            currentLivePartial = reconcileCurrentSegment(current: currentLivePartial, candidate: partial)
        }
        
        lastLivePartialAt = now
        transcript = mergeCommittedAndCurrent(committedLiveTranscript, current: currentLivePartial)
    }
    
    private func finalizeLiveTranscript(with rawFinal: String) -> String {
        let finalCandidate = rawFinal.trimmingCharacters(in: .whitespacesAndNewlines)
        if !finalCandidate.isEmpty {
            if shouldStartNewLiveSegment(current: currentLivePartial, candidate: finalCandidate, gap: livePauseResetThreshold) {
                committedLiveTranscript = appendSegment(committedLiveTranscript, segment: currentLivePartial)
                currentLivePartial = finalCandidate
            } else {
                currentLivePartial = reconcileCurrentSegment(current: currentLivePartial, candidate: finalCandidate)
            }
        }
        
        let merged = mergeCommittedAndCurrent(committedLiveTranscript, current: currentLivePartial)
        return merged.isEmpty ? finalCandidate : merged
    }
    
    private func shouldStartNewLiveSegment(current: String, candidate: String, gap: TimeInterval) -> Bool {
        let existing = current.trimmingCharacters(in: .whitespacesAndNewlines)
        let incoming = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !existing.isEmpty, !incoming.isEmpty else { return false }
        
        let existingLower = existing.lowercased()
        let incomingLower = incoming.lowercased()
        
        if existingLower == incomingLower { return false }
        if incomingLower.hasPrefix(existingLower) || existingLower.hasPrefix(incomingLower) { return false }
        if sharedPrefixWordCount(existingLower, incomingLower) >= 2 { return false }
        if suffixPrefixWordOverlap(existingLower, incomingLower) > 0 { return false }
        
        if gap >= livePauseResetThreshold { return true }
        if wordCount(incomingLower) <= 3 && wordCount(existingLower) >= 3 { return true }
        
        return false
    }
    
    private func reconcileCurrentSegment(current: String, candidate: String) -> String {
        let existing = current.trimmingCharacters(in: .whitespacesAndNewlines)
        let incoming = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !incoming.isEmpty else { return existing }
        guard !existing.isEmpty else { return incoming }
        
        let existingLower = existing.lowercased()
        let incomingLower = incoming.lowercased()
        
        if incomingLower == existingLower { return existing }
        if incomingLower.hasPrefix(existingLower) || existingLower.hasPrefix(incomingLower) { return incoming }
        if sharedPrefixWordCount(existingLower, incomingLower) >= 2 { return incoming }
        
        let overlap = suffixPrefixWordOverlap(existingLower, incomingLower)
        if overlap > 0 {
            let existingWords = words(existing)
            let incomingWords = words(incoming)
            let suffix = incomingWords.dropFirst(overlap).joined(separator: " ")
            if suffix.isEmpty { return existing }
            return (existingWords + suffix.split(whereSeparator: \.isWhitespace).map(String.init)).joined(separator: " ")
        }
        
        return incoming
    }
    
    private func appendSegment(_ base: String, segment: String) -> String {
        let committed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let incoming = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !incoming.isEmpty else { return committed }
        guard !committed.isEmpty else { return incoming }
        
        let committedLower = committed.lowercased()
        let incomingLower = incoming.lowercased()
        if committedLower.hasSuffix(incomingLower) || committedLower.contains(incomingLower) {
            return committed
        }
        
        let overlap = suffixPrefixWordOverlap(committedLower, incomingLower)
        if overlap > 0 {
            let incomingWords = words(incoming)
            let tail = incomingWords.dropFirst(overlap).joined(separator: " ")
            if tail.isEmpty { return committed }
            return committed + " " + tail
        }
        
        return committed + " " + incoming
    }
    
    private func mergeCommittedAndCurrent(_ committed: String, current: String) -> String {
        let stable = committed.trimmingCharacters(in: .whitespacesAndNewlines)
        let live = current.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stable.isEmpty else { return live }
        guard !live.isEmpty else { return stable }
        
        let stableLower = stable.lowercased()
        let liveLower = live.lowercased()
        if stableLower.hasSuffix(liveLower) {
            return stable
        }
        
        let overlap = suffixPrefixWordOverlap(stableLower, liveLower)
        if overlap > 0 {
            let liveWords = words(live)
            let tail = liveWords.dropFirst(overlap).joined(separator: " ")
            if tail.isEmpty { return stable }
            return stable + " " + tail
        }
        
        return stable + " " + live
    }
    
    private func words(_ value: String) -> [String] {
        value.split(whereSeparator: \.isWhitespace).map(String.init)
    }
    
    private func wordCount(_ value: String) -> Int {
        words(value).count
    }
    
    private func sharedPrefixWordCount(_ first: String, _ second: String) -> Int {
        let a = words(first)
        let b = words(second)
        let maxCount = min(a.count, b.count)
        guard maxCount > 0 else { return 0 }
        
        var count = 0
        while count < maxCount, a[count].lowercased() == b[count].lowercased() {
            count += 1
        }
        return count
    }
    
    private func suffixPrefixWordOverlap(_ first: String, _ second: String) -> Int {
        let a = words(first)
        let b = words(second)
        let maxCount = min(a.count, b.count)
        guard maxCount > 0 else { return 0 }
        
        for overlap in stride(from: maxCount, through: 1, by: -1) {
            let left = a.suffix(overlap).map { $0.lowercased() }
            let right = b.prefix(overlap).map { $0.lowercased() }
            if left == right {
                return overlap
            }
        }
        
        return 0
    }
    
    private func desktopRuntimeContext() -> String {
        var parts: [String] = []
        
        if let app = NSWorkspace.shared.frontmostApplication {
            if let name = app.localizedName, !name.isEmpty {
                parts.append("frontmost_app=\(name)")
            }
            if let bundleID = app.bundleIdentifier, !bundleID.isEmpty {
                parts.append("bundle_id=\(bundleID)")
            }
        }
        
        if let windowTitle = frontmostWindowTitle() {
            parts.append("window_title=\(windowTitle)")
        }
        
        parts.append("hotkey=\(config.hotkey)")
        return parts.joined(separator: "; ")
    }
    
    private func frontmostWindowTitle() -> String? {
        guard let frontmostAppName = NSWorkspace.shared.frontmostApplication?.localizedName else {
            return nil
        }
        
        guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        
        for info in infoList {
            guard let ownerName = info[kCGWindowOwnerName as String] as? String,
                  ownerName == frontmostAppName else {
                continue
            }
            
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else {
                continue
            }
            
            if let title = info[kCGWindowName as String] as? String {
                let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        
        return nil
    }
    
    private func isSelectionRewriteRequest(_ value: String) -> Bool {
        let lower = value.lowercased()
        let keywords = [
            "rewrite", "rephrase", "polish", "improve this",
            "make this shorter", "shorter", "friendlier",
            "professional tone", "change the tone", "make this better"
        ]
        return keywords.contains { lower.contains($0) }
    }
    
    private func isDirectApplyRewriteRequest(_ value: String) -> Bool {
        let lower = value.lowercased()
        let directApplyPhrases = [
            "and apply",
            "apply it",
            "replace it",
            "rewrite and apply",
            "rewrite and replace",
            "skip preview",
            "no preview",
            "directly apply",
            "just apply"
        ]
        return directApplyPhrases.contains { lower.contains($0) }
    }
    
    private func isApplyConfirmation(_ value: String) -> Bool {
        let normalized = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let explicit = [
            "apply", "yes", "yes apply", "confirm", "go ahead",
            "do it", "replace it", "approved"
        ]
        return explicit.contains(normalized)
    }
    
    private func isCancelPendingRewrite(_ value: String) -> Bool {
        let normalized = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let cancelWords = ["cancel", "never mind", "dismiss", "skip that"]
        return cancelWords.contains(normalized)
    }
    
    private func buildSelectionRewritePrompt(request: String, selection: String) -> String {
        """
        Rewrite the selected text according to the user's request.
        
        User request:
        \(request)
        
        Selected text:
        \(selection)
        
        Return only the rewritten text. Do not include labels, quotes, markdown, or explanations.
        """
    }
    
    private func extractRewriteText(from response: String) -> String {
        var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned.replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        if cleaned.lowercased().hasPrefix("rewritten:") {
            cleaned = String(cleaned.dropFirst("rewritten:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        if cleaned.lowercased().hasPrefix("revised:") {
            cleaned = String(cleaned.dropFirst("revised:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return cleaned
    }
    
    private func speakThenReturnToIdle(_ message: String) async {
        let line = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else {
            state = .idle
            return
        }
        
        let engine = TTSEngine(config: config)
        engine.reset()
        ttsEngine = engine
        state = .speaking(line)
        await engine.speak(line)
        ttsEngine = nil
        if state != .idle {
            state = .idle
        }
    }
    
    private func runBridgeCommand(arguments: [String], stdin: String? = nil) async -> [String: Any]? {
        let bridgePath = bridgeScriptPath
        return await Task.detached(priority: .userInitiated) {
            guard FileManager.default.fileExists(atPath: bridgePath) else {
                return [
                    "ok": false,
                    "error": "Bridge script not found at \(bridgePath)"
                ]
            }
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = [bridgePath] + arguments
            
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = outputPipe
            
            if let stdin {
                let inputPipe = Pipe()
                process.standardInput = inputPipe
                if let inputData = stdin.data(using: .utf8) {
                    inputPipe.fileHandleForWriting.write(inputData)
                }
                inputPipe.fileHandleForWriting.closeFile()
            }
            
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                return [
                    "ok": false,
                    "error": "Failed to run bridge command: \(error.localizedDescription)"
                ]
            }
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let rawOutput = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard let data = rawOutput.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return [
                    "ok": false,
                    "error": "Bridge returned non-JSON output",
                    "raw": rawOutput
                ]
            }
            
            return json
        }.value
    }
    
    private func fetchSelectedTextFromBridge() async -> String? {
        guard let result = await runBridgeCommand(arguments: ["get_selection", "--json"]) else { return nil }
        if let ok = result["ok"] as? Bool, !ok {
            let reason = (result["error"] as? String) ?? "unknown error"
            clawLog("⚠️ Bridge get_selection failed: \(reason)")
            return nil
        }
        
        let selection = (result["selection"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return selection.isEmpty ? nil : selection
    }
    
    private func applySelectionRewrite(_ text: String) async -> Bool {
        guard let result = await runBridgeCommand(arguments: ["replace_selection", "--stdin", "--json"], stdin: text) else {
            return false
        }
        
        if let ok = result["ok"] as? Bool, ok {
            return true
        }
        
        let reason = (result["error"] as? String) ?? "unknown error"
        clawLog("⚠️ Bridge replace_selection failed: \(reason)")
        return false
    }

    private func processWithText(_ liveText: String) async {
        do {
            var text = liveText.trimmingCharacters(in: .whitespacesAndNewlines)
            clawLog("📝 Live transcript result: '\(text)' (length: \(text.count))")
            
            // Fix #2: Only fall back to Whisper if live transcript is completely empty.
            // SFSpeechRecognizer is usually good enough — don't waste time on Whisper
            // for short but valid transcripts like "hi" or "yes".
            if text.isEmpty {
                clawLog("⚠️ Live transcript empty, falling back to Whisper...")
                let transcriber = Transcriber(config: config)
                text = try await transcriber.transcribe(audioPath: audioRecorder.outputPath)
                clawLog("📝 Whisper fallback result: '\(text)' (length: \(text.count))")
            }
            
            if text.isEmpty || text == "[BLANK_AUDIO]" {
                clawLog("⚠️ No speech detected")
                state = .idle
                return
            }
            clawLog("💬 Final transcript: \(text)")
            
            // Update HUD with final transcript
            transcript = text
            updateHUDContent(animated: false)
            
            let runtimeContext = desktopRuntimeContext()
            clawLog("🖥️ Desktop context: \(runtimeContext)")
            
            if pendingSelectionRewrite != nil, isCancelPendingRewrite(text) {
                pendingSelectionRewrite = nil
                clawLog("🧹 Pending rewrite cancelled")
                await speakThenReturnToIdle("Cancelled the pending rewrite.")
                return
            }
            
            if let pending = pendingSelectionRewrite, isApplyConfirmation(text) {
                let applied = await applySelectionRewrite(pending.rewritten)
                if applied {
                    pendingSelectionRewrite = nil
                    clawLog("✅ Applied pending rewrite (\(pending.rewritten.count) chars)")
                    await speakThenReturnToIdle("Applied. I replaced the selected text.")
                } else {
                    clawLog("⚠️ Failed applying pending rewrite")
                    await speakThenReturnToIdle("I couldn't apply that edit. Keep the text selected and say apply again.")
                }
                return
            }
            
            if isSelectionRewriteRequest(text) {
                guard let selection = await fetchSelectedTextFromBridge(), !selection.isEmpty else {
                    clawLog("⚠️ Rewrite requested but no selected text was found")
                    await speakThenReturnToIdle("I couldn't read selected text. Select the text first, then ask me to rewrite it.")
                    return
                }
                
                clawLog("✍️ Selection rewrite requested: \(selection.count) chars")
                let rewritePrompt = buildSelectionRewritePrompt(request: text, selection: selection)
                let rewriteResponse = try await openClawClient.sendMessage(text: rewritePrompt, screenshotPath: nil, runtimeContext: runtimeContext)
                let rewritten = extractRewriteText(from: rewriteResponse)
                
                guard !rewritten.isEmpty else {
                    clawLog("⚠️ Rewrite response was empty")
                    await speakThenReturnToIdle("I couldn't generate a rewrite for that selection.")
                    return
                }
                
                if isDirectApplyRewriteRequest(text) {
                    let applied = await applySelectionRewrite(rewritten)
                    if applied {
                        pendingSelectionRewrite = nil
                        clawLog("✅ Direct rewrite applied (\(rewritten.count) chars)")
                        await speakThenReturnToIdle("Done. I rewrote and replaced the selected text.")
                    } else {
                        clawLog("⚠️ Direct rewrite apply failed")
                        await speakThenReturnToIdle("I generated the rewrite but couldn't apply it. Keep the text selected and say apply.")
                    }
                    return
                }
                
                pendingSelectionRewrite = PendingSelectionRewrite(
                    original: selection,
                    rewritten: rewritten,
                    request: text
                )
                
                let preview = "Preview: \(rewritten). Say apply to replace your selected text."
                clawLog("📝 Rewrite preview ready (\(rewritten.count) chars)")
                await speakThenReturnToIdle(preview)
                return
            }
            
            clawLog("📡 Sending with configured OpenClaw session routing: \(text)")
            let screenshotPath: String?
            if config.screenshotOnTrigger {
                screenshotPath = await ScreenCapture.captureActiveWindow()
                if let screenshotPath = screenshotPath {
                    clawLog("📸 Screenshot captured: \(screenshotPath)")
                } else {
                    clawLog("⚠️ Screenshot capture failed; continuing without image context")
                }
            } else {
                screenshotPath = nil
            }
            
            let engine = TTSEngine(config: config)
            engine.reset()
            ttsEngine = engine
            
            // Primary path: stream model output and speak on first complete sentence.
            let modelRequestStart = Date()
            var streamedAnySentence = false
            var streamedFullResponse = ""
            var streamError: Error?
            
            for await event in openClawClient.streamMessage(text: text, screenshotPath: screenshotPath, runtimeContext: runtimeContext) {
                if engine.isCancelled || state == .idle { break }
                
                switch event {
                case .sentence(let sentence):
                    if !streamedAnySentence {
                        let firstSentenceLatency = Date().timeIntervalSince(modelRequestStart)
                        clawLog(String(format: "⚡ First sentence latency: %.2fs", firstSentenceLatency))
                    }
                    streamedAnySentence = true
                    state = .speaking(sentence)
                    await engine.speakSentence(sentence)
                    
                case .done(let full):
                    streamedFullResponse = full
                    clawLog("✅ Stream done: \(full.count) chars")
                    
                case .error(let err):
                    streamError = err
                }
            }
            
            if let streamError {
                clawLog("⚠️ Stream failed, falling back to non-streaming: \(streamError.localizedDescription)")
            }
            
            // Fallback: if nothing was spoken from stream, use non-streaming completion.
            if !streamedAnySentence && state != .idle && !engine.isCancelled {
                let fallbackResponse: String
                let streamedCandidate = streamedFullResponse.trimmingCharacters(in: .whitespacesAndNewlines)
                if !streamedCandidate.isEmpty {
                    fallbackResponse = streamedCandidate
                } else {
                    fallbackResponse = try await openClawClient.sendMessage(text: text, screenshotPath: screenshotPath, runtimeContext: runtimeContext)
                    clawLog("✅ Got fallback response: \(fallbackResponse.count) chars")
                }
                
                let segments = speechSegments(from: fallbackResponse)
                if segments.isEmpty {
                    state = .speaking(fallbackResponse)
                    await engine.speak(fallbackResponse)
                } else {
                    for segment in segments {
                        if engine.isCancelled || state == .idle { break }
                        state = .speaking(segment)
                        await engine.speakSentence(segment)
                    }
                }
            }
            
            ttsEngine = nil
            if state != .idle {
                clawLog("✅ Done")
                state = .idle
            } else {
                clawLog("✅ Done (cancelled)")
            }
        } catch {
            clawLog("❌ Pipeline error: \(error)")
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
            clawLog("⚠️ Failed to get voices: \(error)")
            return ["Samantha (English (US))", "Daniel (English (UK))", "Fred (English (US))"]
        }
    }
    
    private struct PreferredSystemVoice {
        let menuTitle: String
        let aliases: [String]
    }
    
    private let preferredSystemVoices: [PreferredSystemVoice] = [
        PreferredSystemVoice(menuTitle: "Siri Voice 1 (527.6MB)", aliases: ["Siri Voice 1", "Siri"]),
        PreferredSystemVoice(menuTitle: "Zoe (Premium)", aliases: ["Zoe (Premium)", "Zoe"]),
        PreferredSystemVoice(menuTitle: "Ava (Premium)", aliases: ["Ava (Premium)", "Ava"]),
        PreferredSystemVoice(menuTitle: "Alex", aliases: ["Alex"]),
        PreferredSystemVoice(menuTitle: "Lee", aliases: ["Lee"]),
        PreferredSystemVoice(menuTitle: "Jamie", aliases: ["Jamie (Premium)", "Jamie"])
    ]
    
    private func getInstalledSystemVoices() -> [String] {
        var all = Set(getSystemVoices())
        for voice in AVSpeechSynthesisVoice.speechVoices() {
            all.insert(voice.name)
        }
        return all.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    
    private func normalizedVoiceName(_ value: String) -> String {
        let lower = value.lowercased()
            .replacingOccurrences(of: "voice", with: "")
            .replacingOccurrences(of: "premium", with: "")
            .replacingOccurrences(of: "enhanced", with: "")
        return lower.replacingOccurrences(of: #"[^a-z0-9]+"#, with: "", options: .regularExpression)
    }
    
    private func resolveInstalledVoice(for preferredVoice: PreferredSystemVoice, installedVoices: [String]) -> String? {
        let aliasSet = Set(preferredVoice.aliases.map(normalizedVoiceName(_:)))
        if preferredVoice.menuTitle.lowercased().contains("siri voice 1") {
            if let exactSiri = installedVoices.first(where: { name in
                let normalized = normalizedVoiceName(name)
                return normalized == "siri1" || normalized == "siri01" || normalized == "sirivoice1"
            }) {
                return exactSiri
            }
        }
        
        if let direct = installedVoices.first(where: { aliasSet.contains(normalizedVoiceName($0)) }) {
            return direct
        }
        
        if preferredVoice.menuTitle.lowercased().contains("siri voice 1") {
            let siriCandidates = installedVoices.filter { normalizedVoiceName($0).contains("siri") }
            if siriCandidates.count == 1 {
                return siriCandidates[0]
            }
        }
        
        return nil
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
            let hint = NSMenuItem(title: "Custom via ~/.openclaw/clawIsland.json → kokoroVoice", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
            return
        }
        
        let currentVoice = config.ttsVoice ?? "Samantha (English (US))"
        let installedVoices = getInstalledSystemVoices()
        
        for preferredVoice in preferredSystemVoices {
            if let installedVoice = resolveInstalledVoice(for: preferredVoice, installedVoices: installedVoices) {
                let item = NSMenuItem(title: preferredVoice.menuTitle, action: #selector(selectVoice(_:)), keyEquivalent: "")
                item.representedObject = installedVoice
                item.target = self
                if normalizedVoiceName(installedVoice) == normalizedVoiceName(currentVoice) {
                    item.state = .on
                }
                menu.addItem(item)
            } else {
                let item = NSMenuItem(title: "\(preferredVoice.menuTitle) (Download…)", action: #selector(downloadSystemVoice(_:)), keyEquivalent: "")
                item.representedObject = preferredVoice.menuTitle
                item.target = self
                menu.addItem(item)
            }
        }
    }
    
    @objc private func selectSpeechEngine(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        let selected = value == "kokoro" ? "kokoro" : "system"
        guard selected != normalizedTTSEngine() else { return }
        
        config.ttsEngine = selected
        do {
            try config.save()
            clawLog("✅ TTS engine changed to: \(selected)")
            refreshSpeechMenus()
        } catch {
            clawLog("❌ Failed to save TTS engine config: \(error)")
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
    
    @objc private func downloadSystemVoice(_ sender: NSMenuItem) {
        let requestedVoice = sender.representedObject as? String ?? "selected voice"
        clawLog("↗️ Opening voice downloads for \(requestedVoice)")
        openVoiceDownloadSettings()
    }
    
    private func openVoiceDownloadSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.accessibility?SpokenContent",
            "x-apple.systempreferences:com.apple.preference.universalaccess?SpokenContent",
            "x-apple.systempreferences:com.apple.preference.accessibility"
        ]
        
        for raw in urls {
            guard let url = URL(string: raw) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
        
        let fallback = URL(fileURLWithPath: "/System/Library/PreferencePanes/Accessibility.prefPane")
        NSWorkspace.shared.open(fallback)
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
            clawLog("✅ Voice changed to: \(voiceName)")
            refreshSpeechMenus()
        } catch {
            clawLog("❌ Failed to save voice config: \(error)")
        }
    }
    
    private func updateKokoroVoiceConfig(_ voiceName: String) {
        config.kokoroVoice = voiceName
        
        do {
            try config.save()
            clawLog("✅ Kokoro voice changed to: \(voiceName)")
            refreshSpeechMenus()
        } catch {
            clawLog("❌ Failed to save Kokoro voice config: \(error)")
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

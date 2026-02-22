import Cocoa

/// Manages global hotkey registration and triggering for push-to-talk activation.
///
/// Supports two trigger modes:
/// - Function key only (`fn` key)
/// - Custom key combinations (e.g., `Option+Space`, `Cmd+Shift+F1`)
///
/// Hotkey format: `"FN"` or `"MODIFIER+MODIFIER+KEY"` where:
/// - Modifiers: CMD/COMMAND, OPTION/ALT, CONTROL/CTRL, SHIFT, FN
/// - Keys: Alphanumeric (A-Z, 0-9), Function keys (F1-F20), or literals (SPACE, RETURN, TAB, etc.)
///
/// Uses global and local event monitors to detect key presses. Includes 0.3-second debounce
/// to prevent duplicate triggers. Automatically falls back to `fn` if hotkey parsing fails.
/// Requires Accessibility permission for global hotkey monitoring.
class HotkeyManager {
    private enum TriggerStyle {
        case functionOnly
        case keyCombo(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, description: String)
    }
    
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalKeyDownMonitor: Any?
    private var localKeyDownMonitor: Any?
    var onToggle: (() -> Void)?
    
    private var fnIsDown = false
    private var lastTriggerTime: Date = .distantPast
    private var triggerStyle: TriggerStyle = .functionOnly
    private let debounceSeconds = 0.3
    private static let fnRawFallbackValues: Set<UInt> = [131332, 1048840, 8388864]
    
    private static let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift, .function]
    private static let supportedModifierKeys: [String: NSEvent.ModifierFlags] = [
        "CMD": .command,
        "COMMAND": .command,
        "OPTION": .option,
        "ALT": .option,
        "CONTROL": .control,
        "CTRL": .control,
        "SHIFT": .shift,
        "FN": .function,
        "FUNCTION": .function
    ]
    
    private static let literalKeyCodes: [String: UInt16] = [
        "SPACE": 49,
        "RETURN": 36,
        "ENTER": 76,
        "TAB": 48,
        "ESC": 53,
        "ESCAPE": 53,
        "DELETE": 51,
        "BACKSPACE": 51,
        "PERIOD": 47,
        ".": 47,
        "COMMA": 43,
        ",": 43,
        "SLASH": 44,
        "/": 44,
        "SEMICOLON": 41,
        ";": 41
    ]
    
    private static let alphaNumericKeyCodes: [String: UInt16] = [
        "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5, "Z": 6, "X": 7, "C": 8, "V": 9,
        "B": 11, "Q": 12, "W": 13, "E": 14, "R": 15, "Y": 16, "T": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
        "-": 27, "8": 28, "0": 29, "]": 30, "O": 31, "U": 32, "[": 33, "I": 34, "P": 35,
        "L": 37, "J": 38, "'": 39, "K": 40, "\\": 42, "N": 45, "M": 46, "`": 50
    ]
    
    private static let functionKeyCodes: [String: UInt16] = [
        "F1": 122, "F2": 120, "F3": 99, "F4": 118, "F5": 96, "F6": 97, "F7": 98, "F8": 100,
        "F9": 101, "F10": 109, "F11": 103, "F12": 111, "F13": 105, "F14": 107,
        "F15": 113, "F16": 106, "F17": 64, "F18": 79, "F19": 80, "F20": 90
    ]

    /// Registers a global hotkey trigger with the system.
    ///
    /// Parses the hotkey string and sets up event monitors for both global and local key events.
    /// If hotkey parsing fails, silently falls back to `fn` trigger.
    /// Call this once during app initialization.
    ///
    /// - Parameter hotkey: Hotkey specification string (e.g., "fn", "Option+Space", "Cmd+Shift+F1")
    /// - Note: Requires Accessibility permission to be granted for global hotkey monitoring
    /// - SeeAlso: `unregister()` to clean up monitors when no longer needed
    func register(hotkey: String) {
        unregister()
        
        if let parsed = Self.parseHotkey(hotkey) {
            triggerStyle = parsed
        } else {
            triggerStyle = .functionOnly
            miloLog("⚠️ Invalid hotkey '\(hotkey)', falling back to fn")
        }
        
        miloLog("⌨️ Registering hotkey monitors for \(hotkeyDescription())")
        
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
        
        globalKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
        }
        
        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
            return event
        }
        
        miloLog("  ✅ Hotkey monitors registered")
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        guard case .functionOnly = triggerStyle else { return }
        
        let flags = event.modifierFlags.intersection(Self.relevantModifiers)
        let raw = event.modifierFlags.rawValue
        let hasFn = flags.contains(.function) ||
            (event.keyCode == 63 && raw != 256) ||
            Self.fnRawFallbackValues.contains(raw)
        let hasOtherModifiers = flags.intersection([.command, .option, .control, .shift]).isEmpty == false
        
        if hasFn && !hasOtherModifiers && !fnIsDown {
            fnIsDown = true
            miloLog("⌨️ fn flagsChanged keyCode=\(event.keyCode) raw=\(raw)")
            trigger(reason: "fn")
        } else if !hasFn {
            fnIsDown = false
        }
    }
    
    private func handleKeyDown(_ event: NSEvent) {
        guard case .keyCombo(let keyCode, let requiredModifiers, let description) = triggerStyle else { return }
        guard !event.isARepeat else { return }
        guard event.keyCode == keyCode else { return }
        
        let activeModifiers = event.modifierFlags.intersection(Self.relevantModifiers)
        guard activeModifiers == requiredModifiers else { return }
        
        trigger(reason: description)
    }
    
    private func trigger(reason: String) {
        let now = Date()
        guard now.timeIntervalSince(lastTriggerTime) > debounceSeconds else { return }
        lastTriggerTime = now
        miloLog("🎯 Hotkey trigger: \(reason)")
        
        DispatchQueue.main.async { [weak self] in
            self?.onToggle?()
        }
    }
    
    private func hotkeyDescription() -> String {
        switch triggerStyle {
        case .functionOnly:
            return "fn"
        case .keyCombo(_, _, let description):
            return description
        }
    }

    /// Unregisters the global hotkey and removes all event monitors.
    ///
    /// Call this when the app is terminating to clean up system resources.
    /// Safe to call multiple times.
    func unregister() {
        if let m = globalFlagsMonitor { NSEvent.removeMonitor(m) }
        if let m = localFlagsMonitor { NSEvent.removeMonitor(m) }
        if let m = globalKeyDownMonitor { NSEvent.removeMonitor(m) }
        if let m = localKeyDownMonitor { NSEvent.removeMonitor(m) }
        
        globalFlagsMonitor = nil
        localFlagsMonitor = nil
        globalKeyDownMonitor = nil
        localKeyDownMonitor = nil
        fnIsDown = false
    }
    
    private static func parseHotkey(_ raw: String) -> TriggerStyle? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        let parts = trimmed
            .split(separator: "+")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        
        if parts.count == 1 && isFnToken(parts[0]) {
            return .functionOnly
        }
        
        var modifiers = NSEvent.ModifierFlags()
        for token in parts.dropLast() {
            let normalized = token.uppercased()
            guard let modifier = supportedModifierKeys[normalized] else { return nil }
            modifiers.insert(modifier)
        }
        
        let keyToken = parts.last ?? ""
        if isFnToken(keyToken), modifiers.isEmpty {
            return .functionOnly
        }
        
        guard let keyCode = keyCode(for: keyToken) else { return nil }
        let canonical = parts.map(canonicalToken).joined(separator: "+")
        return .keyCombo(keyCode: keyCode, modifiers: modifiers, description: canonical)
    }
    
    private static func isFnToken(_ token: String) -> Bool {
        let normalized = token.uppercased()
        return normalized == "FN" || normalized == "FUNCTION"
    }
    
    private static func canonicalToken(_ token: String) -> String {
        switch token.uppercased() {
        case "CMD", "COMMAND":
            return "Cmd"
        case "OPTION", "ALT":
            return "Option"
        case "CONTROL", "CTRL":
            return "Control"
        case "SHIFT":
            return "Shift"
        case "FN", "FUNCTION":
            return "fn"
        default:
            return token.uppercased().hasPrefix("F") ? token.uppercased() : token
        }
    }
    
    private static func keyCode(for token: String) -> UInt16? {
        let normalized = token.uppercased()
        
        if let functionCode = functionKeyCodes[normalized] {
            return functionCode
        }
        if let literalCode = literalKeyCodes[normalized] {
            return literalCode
        }
        if let alphaNumericCode = alphaNumericKeyCodes[normalized] {
            return alphaNumericCode
        }
        
        return nil
    }
}

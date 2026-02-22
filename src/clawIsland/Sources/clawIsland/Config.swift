import Foundation

/// Configuration validation errors with user-friendly messages.
enum ConfigError: Error, LocalizedError {
    /// TTS engine value is not "system" or "kokoro"
    case invalidTtsEngine(String)
    /// Gateway URL is not a valid HTTP/HTTPS URL
    case invalidGatewayUrl(String)
    /// Hotkey string cannot be parsed into a valid key combination
    case invalidHotkey(String)
    /// Kokoro voice is not recognized when Kokoro engine is selected
    case invalidKokoroVoice(String)
    /// Numerical parameter is out of acceptable bounds
    case parameterOutOfBounds(String, String)

    var errorDescription: String? {
        switch self {
        case .invalidTtsEngine(let value):
            return "Invalid TTS engine '\(value)'. Must be 'system' or 'kokoro'."
        case .invalidGatewayUrl(let url):
            return "Invalid gateway URL '\(url)'. Must be a valid HTTP or HTTPS URL."
        case .invalidHotkey(let hotkey):
            return "Invalid hotkey '\(hotkey)'. Format: 'fn' or 'MODIFIER+MODIFIER+KEY' (e.g., 'Option+Space')."
        case .invalidKokoroVoice(let voice):
            return "Kokoro voice '\(voice)' not recognized. Supported: 'af_heart'."
        case .parameterOutOfBounds(let param, let bounds):
            return "Parameter '\(param)' out of bounds: \(bounds)"
        }
    }
}

/// App configuration loaded from ~/.openclaw/clawIsland.json
struct ClawConfig: Codable {
    var hotkey: String
    var gatewayUrl: String
    var gatewayToken: String?
    var screenshotOnTrigger: Bool
    var ttsEngine: String
    var ttsVoice: String?
    var kokoroVoice: String
    var kokoroSpeed: Double
    var kokoroLangCode: String
    var kokoroPythonPath: String?
    var kokoroScriptPath: String?
    var whisperModel: String
    var maxRecordingSeconds: Int
    var sessionKey: String?
    
    /// Model to use. Defaults to "openclaw" which routes through the gateway's
    /// configured agent (inheriting its model, tools, memory, and skills).
    /// Can also be set to a specific model like "anthropic/claude-opus-4-6".
    var model: String
    
    /// How many conversation turns (user+assistant pairs) to keep in the local buffer.
    /// These are sent as message history so the agent has conversational context.
    /// Only used when sessionKey is nil (stateless mode). With a sessionKey,
    /// the gateway manages history server-side.
    var conversationBufferSize: Int
    
    /// OpenClaw agent ID to route to. Defaults to "main".
    var agentId: String
    
    /// Maximum tokens requested from the gateway.
    var maxTokens: Int

    /// When true, clawIsland only relays voice transcripts to OpenClaw.
    /// Local desktop action shortcuts in the overlay are disabled.
    var relayOnlyMode: Bool

    /// Enable adaptive token budgeting based on utterance length/intent.
    var adaptiveMaxTokensEnabled: Bool

    /// Lower bound for adaptive token budgeting.
    var adaptiveMaxTokensFloor: Int

    /// When enabled, sends an early warmup request while recording to reduce first-token latency.
    var speculativePrewarmEnabled: Bool

    /// Minimum live transcript word count before speculative prewarm can start.
    var speculativePrewarmMinWords: Int

    /// Cooldown between speculative prewarm calls.
    var speculativePrewarmCooldownSeconds: Double

    static let defaultConfig = ClawConfig(
        hotkey: "Option+Space",
        gatewayUrl: "http://localhost:18789",
        gatewayToken: nil,
        screenshotOnTrigger: true,
        ttsEngine: "system",
        ttsVoice: "Samantha (English (US))",
        kokoroVoice: "af_heart",
        kokoroSpeed: 1.15,
        kokoroLangCode: "a",
        kokoroPythonPath: nil,
        kokoroScriptPath: nil,
        whisperModel: "base.en",
        maxRecordingSeconds: 30,
        sessionKey: nil,
        model: "openclaw",
        conversationBufferSize: 10,
        agentId: "main",
        maxTokens: 512,
        relayOnlyMode: true,
        adaptiveMaxTokensEnabled: true,
        adaptiveMaxTokensFloor: 128,
        speculativePrewarmEnabled: true,
        speculativePrewarmMinWords: 5,
        speculativePrewarmCooldownSeconds: 90
    )
    
    enum CodingKeys: String, CodingKey {
        case hotkey
        case gatewayUrl
        case gatewayToken
        case screenshotOnTrigger
        case ttsEngine
        case ttsVoice
        case kokoroVoice
        case kokoroSpeed
        case kokoroLangCode
        case kokoroPythonPath
        case kokoroScriptPath
        case whisperModel
        case maxRecordingSeconds
        case sessionKey
        case model
        case conversationBufferSize
        case agentId
        case maxTokens
        case relayOnlyMode
        case adaptiveMaxTokensEnabled
        case adaptiveMaxTokensFloor
        case speculativePrewarmEnabled
        case speculativePrewarmMinWords
        case speculativePrewarmCooldownSeconds
    }

    init(
        hotkey: String,
        gatewayUrl: String,
        gatewayToken: String?,
        screenshotOnTrigger: Bool,
        ttsEngine: String,
        ttsVoice: String?,
        kokoroVoice: String,
        kokoroSpeed: Double,
        kokoroLangCode: String,
        kokoroPythonPath: String?,
        kokoroScriptPath: String?,
        whisperModel: String,
        maxRecordingSeconds: Int,
        sessionKey: String?,
        model: String,
        conversationBufferSize: Int,
        agentId: String,
        maxTokens: Int,
        relayOnlyMode: Bool,
        adaptiveMaxTokensEnabled: Bool,
        adaptiveMaxTokensFloor: Int,
        speculativePrewarmEnabled: Bool,
        speculativePrewarmMinWords: Int,
        speculativePrewarmCooldownSeconds: Double
    ) {
        self.hotkey = hotkey
        self.gatewayUrl = gatewayUrl
        self.gatewayToken = gatewayToken
        self.screenshotOnTrigger = screenshotOnTrigger
        self.ttsEngine = ttsEngine
        self.ttsVoice = ttsVoice
        self.kokoroVoice = kokoroVoice
        self.kokoroSpeed = max(0.6, min(1.6, kokoroSpeed))
        if kokoroSpeed < 0.6 || kokoroSpeed > 1.6 {
            clawLog("⚠️ \(ConfigError.parameterOutOfBounds("kokoroSpeed", "[0.6, 1.6]").localizedDescription) Clamped to \(self.kokoroSpeed).")
        }
        self.kokoroLangCode = kokoroLangCode.isEmpty ? "a" : kokoroLangCode
        self.kokoroPythonPath = kokoroPythonPath
        self.kokoroScriptPath = kokoroScriptPath
        self.whisperModel = whisperModel
        self.maxRecordingSeconds = max(1, maxRecordingSeconds)
        if maxRecordingSeconds < 1 {
            clawLog("⚠️ \(ConfigError.parameterOutOfBounds("maxRecordingSeconds", ">= 1").localizedDescription) Clamped to \(self.maxRecordingSeconds).")
        }
        self.sessionKey = sessionKey
        self.model = model
        self.conversationBufferSize = max(1, conversationBufferSize)
        if conversationBufferSize < 1 {
            clawLog("⚠️ \(ConfigError.parameterOutOfBounds("conversationBufferSize", ">= 1").localizedDescription) Clamped to \(self.conversationBufferSize).")
        }
        self.agentId = agentId
        self.maxTokens = max(1, maxTokens)
        self.relayOnlyMode = relayOnlyMode
        self.adaptiveMaxTokensEnabled = adaptiveMaxTokensEnabled
        self.adaptiveMaxTokensFloor = max(1, min(self.maxTokens, adaptiveMaxTokensFloor))
        self.speculativePrewarmEnabled = speculativePrewarmEnabled
        self.speculativePrewarmMinWords = max(1, speculativePrewarmMinWords)
        self.speculativePrewarmCooldownSeconds = max(10, min(600, speculativePrewarmCooldownSeconds))
        if speculativePrewarmCooldownSeconds < 10 || speculativePrewarmCooldownSeconds > 600 {
            clawLog("⚠️ \(ConfigError.parameterOutOfBounds("speculativePrewarmCooldownSeconds", "[10, 600]").localizedDescription) Clamped to \(self.speculativePrewarmCooldownSeconds).")
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.defaultConfig
        
        hotkey = try container.decodeIfPresent(String.self, forKey: .hotkey) ?? defaults.hotkey
        gatewayUrl = try container.decodeIfPresent(String.self, forKey: .gatewayUrl) ?? defaults.gatewayUrl
        gatewayToken = try container.decodeIfPresent(String.self, forKey: .gatewayToken)
        screenshotOnTrigger = try container.decodeIfPresent(Bool.self, forKey: .screenshotOnTrigger) ?? defaults.screenshotOnTrigger
        ttsEngine = try container.decodeIfPresent(String.self, forKey: .ttsEngine) ?? defaults.ttsEngine
        ttsVoice = try container.decodeIfPresent(String.self, forKey: .ttsVoice) ?? defaults.ttsVoice
        kokoroVoice = try container.decodeIfPresent(String.self, forKey: .kokoroVoice) ?? defaults.kokoroVoice
        kokoroSpeed = max(0.6, min(1.6, try container.decodeIfPresent(Double.self, forKey: .kokoroSpeed) ?? defaults.kokoroSpeed))
        kokoroLangCode = try container.decodeIfPresent(String.self, forKey: .kokoroLangCode) ?? defaults.kokoroLangCode
        if kokoroLangCode.isEmpty { kokoroLangCode = defaults.kokoroLangCode }
        kokoroPythonPath = try container.decodeIfPresent(String.self, forKey: .kokoroPythonPath)
        kokoroScriptPath = try container.decodeIfPresent(String.self, forKey: .kokoroScriptPath)
        whisperModel = try container.decodeIfPresent(String.self, forKey: .whisperModel) ?? defaults.whisperModel
        maxRecordingSeconds = max(1, try container.decodeIfPresent(Int.self, forKey: .maxRecordingSeconds) ?? defaults.maxRecordingSeconds)
        sessionKey = try container.decodeIfPresent(String.self, forKey: .sessionKey)
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? defaults.model
        conversationBufferSize = max(1, try container.decodeIfPresent(Int.self, forKey: .conversationBufferSize) ?? defaults.conversationBufferSize)
        agentId = try container.decodeIfPresent(String.self, forKey: .agentId) ?? defaults.agentId
        maxTokens = max(1, try container.decodeIfPresent(Int.self, forKey: .maxTokens) ?? defaults.maxTokens)
        relayOnlyMode = try container.decodeIfPresent(Bool.self, forKey: .relayOnlyMode) ?? defaults.relayOnlyMode
        adaptiveMaxTokensEnabled = try container.decodeIfPresent(Bool.self, forKey: .adaptiveMaxTokensEnabled) ?? defaults.adaptiveMaxTokensEnabled
        adaptiveMaxTokensFloor = max(1, min(maxTokens, try container.decodeIfPresent(Int.self, forKey: .adaptiveMaxTokensFloor) ?? defaults.adaptiveMaxTokensFloor))
        speculativePrewarmEnabled = try container.decodeIfPresent(Bool.self, forKey: .speculativePrewarmEnabled) ?? defaults.speculativePrewarmEnabled
        speculativePrewarmMinWords = max(1, try container.decodeIfPresent(Int.self, forKey: .speculativePrewarmMinWords) ?? defaults.speculativePrewarmMinWords)
        speculativePrewarmCooldownSeconds = max(10, min(600, try container.decodeIfPresent(Double.self, forKey: .speculativePrewarmCooldownSeconds) ?? defaults.speculativePrewarmCooldownSeconds))
    }

    static var configPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".openclaw/clawIsland.json")
    }

    static var legacyConfigPaths: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(".openclaw/claw-island-overlay.json"),
            home.appendingPathComponent(".openclaw/claw-island.json"),
            home.appendingPathComponent(".openclaw/vyom-overlay.json")
        ]
    }

    /// Validates the configuration, logs warnings, and corrects invalid string fields.
    ///
    /// Checks and corrects:
    /// - ttsEngine → falls back to "system" if not "system" or "kokoro"; normalizes to lowercase
    /// - hotkey → falls back to "Option+Space" if empty or unparseable (invalid modifiers/keys)
    /// - kokoroVoice → falls back to "af_heart" if unrecognized (when Kokoro is selected)
    /// - gatewayUrl → logs warning if not valid HTTP/HTTPS (not corrected since no safe default)
    ///
    /// Numerical parameters are already clamped and logged in `init()` so they are not re-checked here.
    mutating func validate() {
        let defaults = Self.defaultConfig

        // Validate and correct TTS engine (also normalize to lowercase)
        let normalizedEngine = ttsEngine.lowercased()
        if normalizedEngine != "system" && normalizedEngine != "kokoro" {
            let error = ConfigError.invalidTtsEngine(ttsEngine)
            clawLog("⚠️ \(error.localizedDescription) Using 'system' instead.")
            ttsEngine = defaults.ttsEngine
        } else {
            ttsEngine = normalizedEngine
        }

        // Validate and correct Kokoro voice if Kokoro engine selected
        if ttsEngine == "kokoro" {
            let supportedVoices = ["af_heart"]
            if !supportedVoices.contains(kokoroVoice) {
                let error = ConfigError.invalidKokoroVoice(kokoroVoice)
                clawLog("⚠️ \(error.localizedDescription) Using 'af_heart' instead.")
                kokoroVoice = defaults.kokoroVoice
            }
        }

        // Validate and correct hotkey format
        if !isValidHotkey(hotkey) {
            let error = ConfigError.invalidHotkey(hotkey)
            clawLog("⚠️ \(error.localizedDescription) Using default 'Option+Space'.")
            hotkey = defaults.hotkey
        }

        // Validate gateway URL format (log only—no safe default to substitute)
        if !isValidUrl(gatewayUrl) {
            let error = ConfigError.invalidGatewayUrl(gatewayUrl)
            clawLog("⚠️ \(error.localizedDescription)")
        }
    }

    /// Checks if a hotkey string can be parsed into a valid key combination.
    ///
    /// Valid formats: "fn", "MODIFIER+KEY", "MODIFIER+MODIFIER+KEY".
    /// Mirrors the parsing logic in HotkeyManager.parseHotkey.
    private func isValidHotkey(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let parts = trimmed
            .split(separator: "+")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return false }

        let fnTokens: Set<String> = ["FN", "FUNCTION"]
        let modifierTokens: Set<String> = ["CMD", "COMMAND", "OPTION", "ALT", "CONTROL", "CTRL", "SHIFT", "FN", "FUNCTION"]
        // Simplified set of recognized key tokens (covers all keys in HotkeyManager)
        let literalKeys: Set<String> = [
            "SPACE", "RETURN", "ENTER", "TAB", "ESC", "ESCAPE", "DELETE", "BACKSPACE",
            "PERIOD", "COMMA", "SLASH", "SEMICOLON", ".", ",", "/", ";"
        ]

        // Single token: must be fn/function
        if parts.count == 1 {
            return fnTokens.contains(parts[0].uppercased())
                || isRecognizedKey(parts[0].uppercased(), literalKeys: literalKeys)
        }

        // Multi-token: all but last must be modifiers, last must be a key
        for token in parts.dropLast() {
            if !modifierTokens.contains(token.uppercased()) { return false }
        }
        let keyToken = parts.last!.uppercased()
        return isRecognizedKey(keyToken, literalKeys: literalKeys)
    }

    private func isRecognizedKey(_ key: String, literalKeys: Set<String>) -> Bool {
        if literalKeys.contains(key) { return true }
        // Single alphanumeric character (A-Z, 0-9)
        if key.count == 1, let c = key.first, c.isLetter || c.isNumber { return true }
        // Function keys F1-F20
        if key.hasPrefix("F"), key.count <= 3, let num = Int(key.dropFirst(1)), (1...20).contains(num) { return true }
        return false
    }

    /// Checks if a URL string is a valid HTTP or HTTPS URL.
    private func isValidUrl(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        let scheme = url.scheme?.lowercased() ?? ""
        return scheme == "http" || scheme == "https"
    }

    /// Load config from disk, falling back to defaults
    static func load() -> ClawConfig {
        let decoder = JSONDecoder()
        let candidatePaths = [configPath] + legacyConfigPaths

        for path in candidatePaths {
            guard let data = try? Data(contentsOf: path),
                  var config = try? decoder.decode(ClawConfig.self, from: data) else {
                continue
            }
            config.validate()
            return config
        }

        return defaultConfig
    }

    /// Save current config to disk
    func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: ClawConfig.configPath)
    }
}

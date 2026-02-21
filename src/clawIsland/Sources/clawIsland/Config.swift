import Foundation

/// App configuration loaded from ~/.openclaw/clawIsland.json
struct MiloConfig: Codable {
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

    /// When enabled, Milo sends an early warmup request while recording to reduce first-token latency.
    var speculativePrewarmEnabled: Bool

    /// Minimum live transcript word count before speculative prewarm can start.
    var speculativePrewarmMinWords: Int

    /// Cooldown between speculative prewarm calls.
    var speculativePrewarmCooldownSeconds: Double

    static let defaultConfig = MiloConfig(
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
        self.kokoroLangCode = kokoroLangCode.isEmpty ? "a" : kokoroLangCode
        self.kokoroPythonPath = kokoroPythonPath
        self.kokoroScriptPath = kokoroScriptPath
        self.whisperModel = whisperModel
        self.maxRecordingSeconds = max(1, maxRecordingSeconds)
        self.sessionKey = sessionKey
        self.model = model
        self.conversationBufferSize = max(1, conversationBufferSize)
        self.agentId = agentId
        self.maxTokens = max(1, maxTokens)
        self.relayOnlyMode = relayOnlyMode
        self.adaptiveMaxTokensEnabled = adaptiveMaxTokensEnabled
        self.adaptiveMaxTokensFloor = max(1, min(self.maxTokens, adaptiveMaxTokensFloor))
        self.speculativePrewarmEnabled = speculativePrewarmEnabled
        self.speculativePrewarmMinWords = max(1, speculativePrewarmMinWords)
        self.speculativePrewarmCooldownSeconds = max(10, min(600, speculativePrewarmCooldownSeconds))
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
            home.appendingPathComponent(".openclaw/milo-overlay.json"),
            home.appendingPathComponent(".openclaw/claw-island.json"),
            home.appendingPathComponent(".openclaw/vyom-overlay.json")
        ]
    }

    /// Load config from disk, falling back to defaults
    static func load() -> MiloConfig {
        let decoder = JSONDecoder()
        let candidatePaths = [configPath] + legacyConfigPaths

        for path in candidatePaths {
            guard let data = try? Data(contentsOf: path),
                  let config = try? decoder.decode(MiloConfig.self, from: data) else {
                continue
            }
            return config
        }

        return defaultConfig
    }

    /// Save current config to disk
    func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: MiloConfig.configPath)
    }
}

import XCTest
@testable import clawIsland

final class ConfigValidationTests: XCTestCase {

    // MARK: - ConfigError descriptions

    func testConfigError_InvalidTtsEngine_Description() {
        let error = ConfigError.invalidTtsEngine("invalid")
        XCTAssertTrue(error.localizedDescription.contains("invalid"))
        XCTAssertTrue(error.localizedDescription.contains("system"))
    }

    func testConfigError_InvalidGatewayUrl_Description() {
        let error = ConfigError.invalidGatewayUrl("not-a-url")
        XCTAssertTrue(error.localizedDescription.contains("not-a-url"))
        XCTAssertTrue(error.localizedDescription.contains("HTTP"))
    }

    func testConfigError_InvalidHotkey_Description() {
        let error = ConfigError.invalidHotkey("")
        XCTAssertTrue(error.localizedDescription.contains("Invalid hotkey"))
    }

    func testConfigError_InvalidKokoroVoice_Description() {
        let error = ConfigError.invalidKokoroVoice("unknown_voice")
        XCTAssertTrue(error.localizedDescription.contains("unknown_voice"))
        XCTAssertTrue(error.localizedDescription.contains("af_heart"))
    }

    func testConfigError_ParameterOutOfBounds_Description() {
        let error = ConfigError.parameterOutOfBounds("speed", "[0.6, 1.6]")
        XCTAssertTrue(error.localizedDescription.contains("speed"))
        XCTAssertTrue(error.localizedDescription.contains("[0.6, 1.6]"))
    }

    // MARK: - validate() corrections

    func testValidate_InvalidTtsEngine_CorrectedToSystem() {
        var config = ClawConfig.defaultConfig
        config.ttsEngine = "invalid_engine"
        config.validate()
        XCTAssertEqual(config.ttsEngine, "system")
    }

    func testValidate_ValidTtsEngine_NotChanged() {
        var config = ClawConfig.defaultConfig
        config.ttsEngine = "kokoro"
        config.validate()
        XCTAssertEqual(config.ttsEngine, "kokoro")
    }

    func testValidate_EmptyHotkey_CorrectedToDefault() {
        var config = ClawConfig.defaultConfig
        config.hotkey = "   "
        config.validate()
        XCTAssertEqual(config.hotkey, "Option+Space")
    }

    func testValidate_ValidHotkey_NotChanged() {
        var config = ClawConfig.defaultConfig
        config.hotkey = "Cmd+Shift+F1"
        config.validate()
        XCTAssertEqual(config.hotkey, "Cmd+Shift+F1")
    }

    func testValidate_InvalidKokoroVoice_CorrectedToDefault() {
        var config = ClawConfig.defaultConfig
        config.ttsEngine = "kokoro"
        config.kokoroVoice = "unknown_voice"
        config.validate()
        XCTAssertEqual(config.kokoroVoice, "af_heart")
    }

    func testValidate_KokoroVoice_IgnoredWhenSystemEngine() {
        var config = ClawConfig.defaultConfig
        config.ttsEngine = "system"
        config.kokoroVoice = "unknown_voice"
        config.validate()
        // Should not correct kokoroVoice when engine is system
        XCTAssertEqual(config.kokoroVoice, "unknown_voice")
    }

    func testValidate_ValidConfig_NoChanges() {
        var config = ClawConfig.defaultConfig
        let originalEngine = config.ttsEngine
        let originalHotkey = config.hotkey
        config.validate()
        XCTAssertEqual(config.ttsEngine, originalEngine)
        XCTAssertEqual(config.hotkey, originalHotkey)
    }

    // MARK: - init() clamping

    func testInit_KokoroSpeedClamped_TooLow() {
        var config = ClawConfig.defaultConfig
        config = ClawConfig(
            hotkey: config.hotkey, gatewayUrl: config.gatewayUrl,
            gatewayToken: nil, screenshotOnTrigger: true,
            ttsEngine: "system", ttsVoice: nil,
            kokoroVoice: "af_heart", kokoroSpeed: 0.1,
            kokoroLangCode: "a", kokoroPythonPath: nil, kokoroScriptPath: nil,
            whisperModel: "base.en", maxRecordingSeconds: 30, sessionKey: nil,
            model: "openclaw", conversationBufferSize: 10, agentId: "main",
            maxTokens: 512, relayOnlyMode: true,
            adaptiveMaxTokensEnabled: true, adaptiveMaxTokensFloor: 128,
            speculativePrewarmEnabled: true, speculativePrewarmMinWords: 5,
            speculativePrewarmCooldownSeconds: 90
        )
        XCTAssertEqual(config.kokoroSpeed, 0.6)
    }

    func testInit_KokoroSpeedClamped_TooHigh() {
        var config = ClawConfig.defaultConfig
        config = ClawConfig(
            hotkey: config.hotkey, gatewayUrl: config.gatewayUrl,
            gatewayToken: nil, screenshotOnTrigger: true,
            ttsEngine: "system", ttsVoice: nil,
            kokoroVoice: "af_heart", kokoroSpeed: 5.0,
            kokoroLangCode: "a", kokoroPythonPath: nil, kokoroScriptPath: nil,
            whisperModel: "base.en", maxRecordingSeconds: 30, sessionKey: nil,
            model: "openclaw", conversationBufferSize: 10, agentId: "main",
            maxTokens: 512, relayOnlyMode: true,
            adaptiveMaxTokensEnabled: true, adaptiveMaxTokensFloor: 128,
            speculativePrewarmEnabled: true, speculativePrewarmMinWords: 5,
            speculativePrewarmCooldownSeconds: 90
        )
        XCTAssertEqual(config.kokoroSpeed, 1.6)
    }

    func testInit_MaxRecordingSecondsClamped() {
        let config = ClawConfig(
            hotkey: "Option+Space", gatewayUrl: "http://localhost:18789",
            gatewayToken: nil, screenshotOnTrigger: true,
            ttsEngine: "system", ttsVoice: nil,
            kokoroVoice: "af_heart", kokoroSpeed: 1.0,
            kokoroLangCode: "a", kokoroPythonPath: nil, kokoroScriptPath: nil,
            whisperModel: "base.en", maxRecordingSeconds: -5, sessionKey: nil,
            model: "openclaw", conversationBufferSize: 10, agentId: "main",
            maxTokens: 512, relayOnlyMode: true,
            adaptiveMaxTokensEnabled: true, adaptiveMaxTokensFloor: 128,
            speculativePrewarmEnabled: true, speculativePrewarmMinWords: 5,
            speculativePrewarmCooldownSeconds: 90
        )
        XCTAssertEqual(config.maxRecordingSeconds, 1)
    }

    // MARK: - isValidUrl (tested indirectly via validate)

    func testValidate_InvalidGatewayUrl_LogsWarning() {
        // Invalid URL should not crash, just log
        var config = ClawConfig.defaultConfig
        config.gatewayUrl = "not-a-url"
        config.validate()
        // gatewayUrl is not corrected (no safe default), just warned
        XCTAssertEqual(config.gatewayUrl, "not-a-url")
    }

    func testValidate_ValidHttpsGatewayUrl_NoWarning() {
        var config = ClawConfig.defaultConfig
        config.gatewayUrl = "https://gateway.example.com"
        config.validate()
        XCTAssertEqual(config.gatewayUrl, "https://gateway.example.com")
    }
}

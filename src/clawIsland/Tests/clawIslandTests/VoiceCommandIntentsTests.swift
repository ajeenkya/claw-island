import XCTest
@testable import clawIsland

final class VoiceCommandIntentsTests: XCTestCase {
    func testSelectionRewriteIntent() {
        XCTAssertTrue(VoiceCommandIntents.isSelectionRewriteRequest("rewrite this to sound friendlier"))
        XCTAssertTrue(VoiceCommandIntents.isSelectionRewriteRequest("can you polish this?"))
        XCTAssertFalse(VoiceCommandIntents.isSelectionRewriteRequest("what time is it"))
    }

    func testDirectApplyRewriteIntent() {
        XCTAssertTrue(VoiceCommandIntents.isDirectApplyRewriteRequest("rewrite and apply"))
        XCTAssertTrue(VoiceCommandIntents.isDirectApplyRewriteRequest("just apply this"))
        XCTAssertFalse(VoiceCommandIntents.isDirectApplyRewriteRequest("rewrite this"))
    }

    func testApplyConfirmationIntent() {
        XCTAssertTrue(VoiceCommandIntents.isApplyConfirmation("apply"))
        XCTAssertTrue(VoiceCommandIntents.isApplyConfirmation("  yes apply  "))
        XCTAssertFalse(VoiceCommandIntents.isApplyConfirmation("okay maybe"))
    }

    func testCancelRewriteIntent() {
        XCTAssertTrue(VoiceCommandIntents.isCancelPendingRewrite("cancel"))
        XCTAssertTrue(VoiceCommandIntents.isCancelPendingRewrite("never mind"))
        XCTAssertFalse(VoiceCommandIntents.isCancelPendingRewrite("continue"))
    }

    func testExtractRewriteText() {
        XCTAssertEqual(
            VoiceCommandIntents.extractRewriteText(from: "Rewritten: Hello world"),
            "Hello world"
        )
        XCTAssertEqual(
            VoiceCommandIntents.extractRewriteText(from: "```Revised: Better sentence```"),
            "Better sentence"
        )
        XCTAssertEqual(
            VoiceCommandIntents.extractRewriteText(from: "  Plain output  "),
            "Plain output"
        )
    }

    func testParseTypeAndSendIntentWithSendKey() {
        let intent = VoiceCommandIntents.parseTypeAndSendIntent("Respond yes and then press send to Kodex")
        XCTAssertNotNil(intent)
        XCTAssertEqual(intent?.text, "yes")
        XCTAssertEqual(intent?.sendKey, .enter)
    }

    func testParseTypeAndSendIntentWithCommandEnter() {
        let intent = VoiceCommandIntents.parseTypeAndSendIntent("type \"looks good\" and press command enter")
        XCTAssertNotNil(intent)
        XCTAssertEqual(intent?.text, "looks good")
        XCTAssertEqual(intent?.sendKey, .commandEnter)
    }

    func testParseTypeAndSendIntentStripsLocationFiller() {
        let intent = VoiceCommandIntents.parseTypeAndSendIntent("type yes here and press the send key")
        XCTAssertNotNil(intent)
        XCTAssertEqual(intent?.text, "yes")
        XCTAssertEqual(intent?.sendKey, .enter)
    }

    func testParseTypeAndSendIntentRejectsNonActionPrompt() {
        XCTAssertNil(VoiceCommandIntents.parseTypeAndSendIntent("can you explain why this failed"))
    }

    // MARK: - Error Path Tests: Empty & Edge Cases

    func testSelectionRewriteIntent_EmptyString() {
        XCTAssertFalse(VoiceCommandIntents.isSelectionRewriteRequest(""))
        XCTAssertFalse(VoiceCommandIntents.isSelectionRewriteRequest("   "))
    }

    func testSelectionRewriteIntent_WhitespaceOnly() {
        XCTAssertFalse(VoiceCommandIntents.isSelectionRewriteRequest("\n\t  \n"))
    }

    func testDirectApplyRewriteIntent_EmptyString() {
        XCTAssertFalse(VoiceCommandIntents.isDirectApplyRewriteRequest(""))
        XCTAssertFalse(VoiceCommandIntents.isDirectApplyRewriteRequest("   "))
    }

    func testApplyConfirmation_EmptyString() {
        XCTAssertFalse(VoiceCommandIntents.isApplyConfirmation(""))
        XCTAssertFalse(VoiceCommandIntents.isApplyConfirmation("   "))
    }

    func testCancelRewrite_EmptyString() {
        XCTAssertFalse(VoiceCommandIntents.isCancelPendingRewrite(""))
        XCTAssertFalse(VoiceCommandIntents.isCancelPendingRewrite("   "))
    }

    // MARK: - Error Path Tests: Special Characters & Unicode

    func testSelectionRewriteIntent_WithSpecialCharacters() {
        XCTAssertTrue(VoiceCommandIntents.isSelectionRewriteRequest("rewrite!!! this??? please!!!"))
        XCTAssertTrue(VoiceCommandIntents.isSelectionRewriteRequest("rephrase@this#text"))
    }

    func testSelectionRewriteIntent_WithUnicode() {
        XCTAssertTrue(VoiceCommandIntents.isSelectionRewriteRequest("rewrite this café"))
        // Cyrillic text without English keywords doesn't match
        XCTAssertFalse(VoiceCommandIntents.isSelectionRewriteRequest("улучши́ть рефре́йз"))
    }

    func testExtractRewriteText_EmptyResponse() {
        XCTAssertEqual(VoiceCommandIntents.extractRewriteText(from: ""), "")
        XCTAssertEqual(VoiceCommandIntents.extractRewriteText(from: "   "), "")
    }

    func testExtractRewriteText_OnlyWhitespace() {
        XCTAssertEqual(VoiceCommandIntents.extractRewriteText(from: "\n\n\t\t"), "")
    }

    func testExtractRewriteText_WithMultipleBackticks() {
        // extractRewriteText removes all ``` occurrences, but leaves remaining single backticks
        XCTAssertEqual(
            VoiceCommandIntents.extractRewriteText(from: "```````Plain text```````"),
            "`Plain text`" // Odd number of backticks leaves one
        )
    }

    func testExtractRewriteText_MixedLabels() {
        XCTAssertEqual(
            VoiceCommandIntents.extractRewriteText(from: "rewritten: first line\nrevised: second line"),
            "first line\nrevised: second line" // Only first label prefix is stripped
        )
    }

    // MARK: - Error Path Tests: Intent Parsing Edge Cases

    func testParseTypeAndSendIntent_EmptyString() {
        XCTAssertNil(VoiceCommandIntents.parseTypeAndSendIntent(""))
    }

    func testParseTypeAndSendIntent_NoTypeOrSend() {
        XCTAssertNil(VoiceCommandIntents.parseTypeAndSendIntent("just speak this"))
    }

    func testParseTypeAndSendIntent_TypeWithoutSend() {
        XCTAssertNil(VoiceCommandIntents.parseTypeAndSendIntent("type hello world"))
    }

    func testParseTypeAndSendIntent_SendWithoutType() {
        XCTAssertNil(VoiceCommandIntents.parseTypeAndSendIntent("press send"))
    }

    func testParseTypeAndSendIntent_VeryLongText() {
        let longText = String(repeating: "a", count: 5000)
        let intent = VoiceCommandIntents.parseTypeAndSendIntent("type \"\(longText)\" and press send")
        XCTAssertNotNil(intent)
        XCTAssertEqual(intent?.text, longText)
    }

    func testParseTypeAndSendIntent_TextWithQuotes() {
        let intent = VoiceCommandIntents.parseTypeAndSendIntent("type \"hello \\\"world\\\" here\" and press send")
        XCTAssertNotNil(intent)
        // Note: Quote handling depends on implementation; just verify it parses
        XCTAssertFalse(intent?.text.isEmpty ?? true)
    }

    func testParseTypeAndSendIntent_UnknownSendKey() {
        let intent = VoiceCommandIntents.parseTypeAndSendIntent("type hello and press the crazy key")
        // Should either return nil or ignore unknown key
        // This test documents current behavior
        XCTAssertNil(intent) // Expected: unknown keys are rejected
    }

    // MARK: - Error Path Tests: Case Sensitivity

    func testApplyConfirmation_MixedCase() {
        XCTAssertTrue(VoiceCommandIntents.isApplyConfirmation("APPLY"))
        XCTAssertTrue(VoiceCommandIntents.isApplyConfirmation("Apply"))
        XCTAssertTrue(VoiceCommandIntents.isApplyConfirmation("aPpLy"))
    }

    func testCancelRewrite_MixedCase() {
        XCTAssertTrue(VoiceCommandIntents.isCancelPendingRewrite("CANCEL"))
        XCTAssertTrue(VoiceCommandIntents.isCancelPendingRewrite("Cancel"))
    }

    // MARK: - Error Path Tests: Boundary Conditions

    func testSelectionRewriteIntent_SingleWord() {
        XCTAssertTrue(VoiceCommandIntents.isSelectionRewriteRequest("rewrite"))
        XCTAssertFalse(VoiceCommandIntents.isSelectionRewriteRequest("hello"))
    }

    func testSelectionRewriteIntent_VeryLongString() {
        let longString = "rewrite " + String(repeating: "word ", count: 1000)
        XCTAssertTrue(VoiceCommandIntents.isSelectionRewriteRequest(longString))
    }

    func testApplyConfirmation_AlmostMatch() {
        XCTAssertFalse(VoiceCommandIntents.isApplyConfirmation("apply now"))
        XCTAssertFalse(VoiceCommandIntents.isApplyConfirmation("ok apply"))
        XCTAssertTrue(VoiceCommandIntents.isApplyConfirmation("apply")) // Exact match
    }

    func testExtractRewriteText_NestedMarkdown() {
        // All triple-backticks are removed, then label is stripped
        XCTAssertEqual(
            VoiceCommandIntents.extractRewriteText(from: "```Rewritten: ```nested code``````"),
            "nested code" // All backticks removed, then "Rewritten:" prefix stripped
        )
    }
}

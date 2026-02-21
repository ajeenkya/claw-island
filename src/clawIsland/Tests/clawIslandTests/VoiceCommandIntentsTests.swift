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
}

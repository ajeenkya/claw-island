import XCTest
@testable import clawIsland

final class SanitizeTests: XCTestCase {

    // MARK: - Markdown stripping

    func testStripsBold() {
        XCTAssertEqual(OpenClawClient.sanitize("This is **bold** text"), "This is bold text")
    }

    func testStripsUnderlineBold() {
        XCTAssertEqual(OpenClawClient.sanitize("This is __bold__ text"), "This is bold text")
    }

    func testStripsItalicStar() {
        XCTAssertEqual(OpenClawClient.sanitize("This is *italic* text"), "This is italic text")
    }

    func testStripsItalicUnderscoreBoundaryAware() {
        XCTAssertEqual(OpenClawClient.sanitize("This is _italic_ text"), "This is italic text")
    }

    func testPreservesUnderscoresInIdentifiers() {
        XCTAssertEqual(OpenClawClient.sanitize("Check my_file_name.txt"), "Check my_file_name.txt")
    }

    func testStripsStrikethrough() {
        XCTAssertEqual(OpenClawClient.sanitize("This is ~~removed~~ text"), "This is removed text")
    }

    func testStripsInlineCode() {
        XCTAssertEqual(OpenClawClient.sanitize("Run `npm install` now"), "Run npm install now")
    }

    func testStripsCodeFences() {
        // Code fences with no language tag
        XCTAssertEqual(OpenClawClient.sanitize("```\nlet x = 1\n```"), "let x = 1")
        // Verify backticks are removed
        XCTAssertFalse(OpenClawClient.sanitize("```\nsome code\n```").contains("```"))
    }

    func testStripsCodeFencesWithLanguageTag() {
        // Language tag (e.g., ```swift) should be stripped along with the backticks
        let result = OpenClawClient.sanitize("```swift\nlet x = 1\n```")
        XCTAssertFalse(result.contains("```"))
        XCTAssertFalse(result.contains("swift"))
        XCTAssertEqual(result, "let x = 1")
    }

    func testStripsHeadings() {
        XCTAssertEqual(OpenClawClient.sanitize("### My Heading"), "My Heading")
        XCTAssertEqual(OpenClawClient.sanitize("# Title"), "Title")
        XCTAssertEqual(OpenClawClient.sanitize("###### Deep"), "Deep")
    }

    func testStripsBulletPoints() {
        XCTAssertEqual(OpenClawClient.sanitize("- First item\n- Second item"), "First item\nSecond item")
        XCTAssertEqual(OpenClawClient.sanitize("* First\n* Second"), "First\nSecond")
    }

    func testStripsNumberedLists() {
        XCTAssertEqual(OpenClawClient.sanitize("1. First\n2. Second"), "First\nSecond")
    }

    func testStripsMixedMarkdown() {
        let input = "### **Title**\n- *Item one*\n- `code here`"
        let result = OpenClawClient.sanitize(input)
        XCTAssertFalse(result.contains("**"))
        XCTAssertFalse(result.contains("*"))
        XCTAssertFalse(result.contains("#"))
        XCTAssertFalse(result.contains("`"))
        XCTAssertFalse(result.contains("- "))
        XCTAssertTrue(result.contains("Title"))
        XCTAssertTrue(result.contains("Item one"))
        XCTAssertTrue(result.contains("code here"))
    }

    // MARK: - Emoji stripping

    func testStripsCommonEmojis() {
        XCTAssertEqual(OpenClawClient.sanitize("Hello 😀 world"), "Hello world")
        XCTAssertEqual(OpenClawClient.sanitize("Done ✅"), "Done")
        XCTAssertEqual(OpenClawClient.sanitize("Warning ⚠️"), "Warning")
    }

    func testStripsHeartEmoji() {
        // Heart ❤ is U+2764, in the BMP emoji range that was previously dead code
        XCTAssertEqual(OpenClawClient.sanitize("Love ❤️ this"), "Love this")
    }

    func testStripsSunEmoji() {
        // Sun ☀ is U+2600
        XCTAssertEqual(OpenClawClient.sanitize("Sunny ☀️ day"), "Sunny day")
    }

    func testStripsStarEmoji() {
        // Star ⭐ is U+2B50
        XCTAssertEqual(OpenClawClient.sanitize("Rating ⭐⭐⭐"), "Rating")
    }

    func testStripsTransportEmojis() {
        XCTAssertEqual(OpenClawClient.sanitize("Let's go 🚀"), "Let's go")
    }

    func testStripsMultipleEmojis() {
        XCTAssertEqual(OpenClawClient.sanitize("🎉 Party 🎊 time 🥳"), "Party time")
    }

    func testStripsHourglassAndMediaControls() {
        // Hourglass U+23F3 and fast-forward U+23E9 are in the 0x2300-0x23FF range
        XCTAssertEqual(OpenClawClient.sanitize("Loading ⏳ please wait"), "Loading please wait")
        XCTAssertEqual(OpenClawClient.sanitize("Play ⏩ next"), "Play next")
    }

    // MARK: - Edge cases

    func testEmptyString() {
        XCTAssertEqual(OpenClawClient.sanitize(""), "")
    }

    func testAlreadyCleanString() {
        XCTAssertEqual(OpenClawClient.sanitize("Just a normal sentence."), "Just a normal sentence.")
    }

    func testCollapsesMultipleSpaces() {
        XCTAssertEqual(OpenClawClient.sanitize("Hello   world"), "Hello world")
    }

    func testTrimsWhitespace() {
        XCTAssertEqual(OpenClawClient.sanitize("  hello  "), "hello")
    }

    func testOnlyEmojis() {
        XCTAssertEqual(OpenClawClient.sanitize("😀🎉🚀"), "")
    }
}
